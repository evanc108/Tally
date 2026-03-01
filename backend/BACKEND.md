# Tally Backend — Technical Writeup

## Overview

Tally's backend is a Go service that powers real-time group spending. When one member of a group swipes a card, the backend authorizes the charge in milliseconds by verifying that every member of the group can cover their individual share — simultaneously — before approving the transaction.

The core metaphor is the **Tally Stick**: a single transaction is split into multiple verifiable pieces, one per member, each recorded as an immutable ledger entry.

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Language | Go 1.22 | Goroutines make parallel bank checks trivial; fast compile + deploy |
| HTTP Framework | Gin | High-performance routing with middleware chains |
| Database | PostgreSQL 16 | Double-entry ledger requires ACID guarantees + serializable transactions |
| Cache / Lock | Redis 7 | Sub-millisecond idempotency checks and distributed locking |
| Schema Migrations | golang-migrate | SQL files embedded in the binary; runs automatically on boot |
| Containerization | Docker Compose | Single command brings up the full local stack |

---

## Project Structure

```
backend/
├── main.go                          Entry point — wires everything together
├── docker-compose.yml               Local stack: Postgres + Redis + App + pgAdmin
├── Dockerfile                       Multi-stage build → distroless runtime image
├── go.mod
└── internal/
    ├── config/config.go             Loads all config from environment variables
    ├── db/
    │   ├── db.go                    Connection pool (Postgres) + Redis client
    │   ├── migrate.go               Runs embedded SQL migrations on boot
    │   └── migrations/
    │       ├── 000001_init.up.sql   Full schema definition
    │       └── 000001_init.down.sql Teardown (drops all tables)
    ├── ledger/
    │   └── posting.go               Double-entry accounting engine
    ├── middleware/
    │   ├── hmac.go                  Webhook signature verification
    │   ├── idempotency.go           Redis-backed request deduplication
    │   └── logger.go                Structured JSON request logging
    ├── plaid/
    │   └── mock.go                  Mock Plaid client (swap for real SDK in prod)
    └── auth/
        └── jit.go                   POST /v1/auth/jit — core authorization handler
```

---

## Database Schema

Six tables form the complete data model. All monetary values are stored as **integer cents** (never floats) to avoid rounding errors.

### `tally_groups`
Represents a spending group (e.g. "Weekend Trip", "Shared Apartment").

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| name | TEXT | Display name |
| currency | CHAR(3) | Default `USD` |

### `members`
One row per user per group. A user in three groups has three rows.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| group_id | UUID | FK → tally_groups |
| card_token | TEXT | Unique. The virtual card ID issued by the card processor |
| plaid_access_token | TEXT | Plaid Link credential for this member's bank |
| plaid_account_id | TEXT | Specific bank account to check |
| tally_balance_cents | BIGINT | Pre-loaded wallet balance. Checked first before hitting the bank |
| split_weight | NUMERIC(7,6) | Fractional share of group expenses (e.g. `0.250000` for a 4-way equal split) |

### `accounts`
Ledger accounts. Each **member** gets one `asset` account. Each **group** gets one `liability` (clearing) account.

| Column | Type | Notes |
|---|---|---|
| owner_type | TEXT | `'member'` or `'group'` |
| owner_id | UUID | Points to a member or group row |
| account_type | TEXT | `'asset'` or `'liability'` |

### `transactions`
One row per card swipe. Tracks the lifecycle from authorization to settlement.

| Status | Meaning |
|---|---|
| `PENDING` | Created when the swipe arrives, before balance checks complete |
| `APPROVED` | All members can cover their share; ledger entries written |
| `DECLINED` | At least one member could not cover their share |
| `SETTLED` | Money has been collected from all members |
| `REVERSED` | Transaction was unwound (e.g. merchant refund) |

The `idempotency_key` column has a `UNIQUE` constraint — this is the database-level backstop against duplicate processing even if Redis is bypassed.

### `journal_entries`
The immutable double-entry ledger. Every financial event writes at least one row here. Entries are never deleted or updated in place; reversals create new offsetting rows.

| Column | Notes |
|---|---|
| debit_account_id | The account being debited |
| credit_account_id | The account being credited |
| amount_cents | Always positive |
| status | `PENDING` → `SETTLED` or `REVERSED` |

A database constraint (`chk_no_self_entry`) enforces that debit and credit accounts can never be the same row.

### `funding_pulls`
Records how each member's share will be (or was) collected. One row per member per transaction.

| funding_type | Meaning |
|---|---|
| `tally_balance` | Deducted from the member's pre-loaded Tally wallet |
| `direct_pull` | Pulled directly from the member's linked bank account via ACH |

---

## The Double-Entry Ledger

Every card swipe produces one journal entry **per member**. The accounting equation is:

```
Debit  → member's asset account      (the member now "owes" their share)
Credit → group's liability account   (the group absorbed the merchant charge)
```

**Example — $100 dinner split 4 ways equally:**

| Entry | Debit | Credit | Amount |
|---|---|---|---|
| 1 | Alice's asset account | Group clearing account | $25 |
| 2 | Bob's asset account | Group clearing account | $25 |
| 3 | Carol's asset account | Group clearing account | $25 |
| 4 | Dave's asset account | Group clearing account | $25 |

The group clearing account now has $100 credit, exactly matching the merchant charge. The books balance.

**On reversal**, the debit and credit sides are swapped exactly, creating four new offsetting entries. The original entries are never touched.

The ledger package exposes three functions:

- `PostPendingTransaction` — writes PENDING entries for all splits atomically
- `SettleTransaction` — marks entries SETTLED and deducts `tally_balance` wallets
- `ReverseTransaction` — writes offsetting entries to unwind an approved transaction

All three use **SERIALIZABLE isolation** in Postgres to prevent phantom reads when multiple authorizations arrive simultaneously for the same group.

---

## The JIT Authorization Flow

`POST /v1/auth/jit` is the critical path. It must respond within milliseconds or the card processor will timeout and decline automatically. The handler has an **8-second budget** for the entire flow.

```
Card Processor
     │
     │  POST /v1/auth/jit
     │  X-Tally-Signature: sha256=<hex>
     │  Idempotency-Key: <uuid>
     ▼
┌─────────────────────────────────────────────────────────────┐
│  Middleware Chain                                           │
│  1. HMAC Verification  — reject unsigned requests          │
│  2. Idempotency Check  — return cached response if repeat  │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│  JIT Handler                                                │
│                                                             │
│  Step 1: resolveCard()                                      │
│    SQL query: card_token → group_id + all member rows       │
│    Also fetches each member's asset account ID and          │
│    the group's clearing account ID. Single round-trip.      │
│                                                             │
│  Step 2: insertPendingTransaction()                         │
│    Writes a PENDING transaction row immediately.            │
│    The UNIQUE(idempotency_key) constraint is a DB backstop. │
│                                                             │
│  Step 3: parallelBalanceCheck()                             │
│    Spawns one Goroutine per member.                         │
│    Each goroutine calls Plaid GetAccountBalance().          │
│    All goroutines run concurrently — total time ≈           │
│    slowest single Plaid call, not sum of all calls.         │
│                                                             │
│  Step 4: buildFundingPlan()                                 │
│    For each member:                                         │
│      if tally_balance >= share  →  fund from wallet         │
│      elif wallet + bank >= share →  direct_pull shortfall   │
│      else                       →  DECLINE entire txn       │
│                                                             │
│  Step 5: PostPendingTransaction() (if all members approved) │
│    Serializable Postgres transaction writes:                │
│      • N journal_entries (one per member)                   │
│      • N funding_pulls   (one per member)                   │
│      • Updates transaction.status → APPROVED               │
│    Single atomic commit. If it fails, nothing is written.   │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
{ "decision": "APPROVE", "transaction_id": "..." }
       or
{ "decision": "DECLINE", "reason": "insufficient_funds" }
```

---

## Safety & Reliability

### HMAC Webhook Verification
Every request to `/v1/auth/jit` must include:
```
X-Tally-Signature: sha256=<hex(HMAC-SHA256(webhookSecret, rawBody))>
```
The middleware computes the expected signature and compares using `hmac.Equal` — a **constant-time comparison** that prevents timing-oracle attacks. Requests without a valid signature receive `401` and never reach the handler.

HMAC verification runs **before** idempotency middleware so spoofed requests cannot pollute the response cache.

### Idempotency (Redis)
Network retries are a reality in payment systems. The idempotency middleware prevents a retry from double-charging:

1. **Cache check** — if `idem:resp:<key>` exists in Redis, replay the cached response immediately without executing the handler.
2. **Distributed lock** — if no cache, acquire `idem:lock:<key>` with `SET NX` (set-if-not-exists, 30s TTL). A concurrent duplicate request that loses the lock gets `409 Conflict` and is told to retry in ~1s.
3. **Cache write** — after the handler completes, the response is cached for 24 hours. Only non-5xx responses are cached (5xx errors may be transient and should not be replayed).
4. **Lock release** — the lock is released via `defer` so it's always removed even if the handler panics.

The database's `UNIQUE(idempotency_key)` on the `transactions` table is a final backstop if Redis is ever unavailable.

### Parallel Bank Verification
Balance checks use `sync.WaitGroup` to fan out one goroutine per group member. For a 4-member group, all four Plaid calls happen simultaneously. Total latency is bounded by the **slowest single call**, not the sum — typically ~50-100ms instead of 200-400ms.

All goroutines respect the request's context deadline (8s). If the context is cancelled (e.g. the card processor closed the connection), the Plaid calls return immediately via `ctx.Done()`.

### Hybrid Funding Logic
Each member's share is funded in this priority order:

1. **tally_balance** (the member's pre-loaded Tally wallet) — preferred because it requires no external call at settlement time
2. **direct_pull** (ACH pull from linked bank) — used when the wallet balance is insufficient but the bank balance covers the gap

If a member's `tally_balance + bankBalance` is less than their share, the **entire transaction is declined**. A partial approval is never issued.

---

## Middleware Stack

Every request passes through this chain (in order):

```
gin.Recovery()          Catches panics, returns 500 instead of crashing
RequestLogger()         Logs method, path, status, latency_ms as structured JSON
HMACVerification()      Validates X-Tally-Signature header  [/v1/auth only]
Idempotency()           Redis cache + SET NX lock            [/v1/auth only]
```

---

## Local Development

```bash
cd backend

# 1. Install dependencies and generate go.sum
go mod tidy

# 2. Start the full stack (Postgres + Redis + App + pgAdmin)
docker compose up --build

# 3. App is live at http://localhost:8080
# 4. pgAdmin is at http://localhost:5050
#    Email: admin@tally.local  |  Password: admin
#    Connect to host: postgres, port: 5432, db: tally, user: tally, pw: tally_secret
```

Migrations run automatically when the app boots. They are embedded in the binary via `//go:embed migrations/*.sql` in [internal/db/migrate.go](internal/db/migrate.go) and are safe to run multiple times.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgres://tally:tally_secret@localhost:5432/tally?sslmode=disable` | Postgres connection string |
| `REDIS_URL` | `redis://localhost:6379` | Redis connection URL |
| `WEBHOOK_SECRET` | `dev_webhook_secret_change_in_prod` | Shared secret for HMAC signature verification |
| `PORT` | `8080` | HTTP listen port |
| `ENV` | `development` | Set to `production` to enable Gin release mode |
| `PLAID_CLIENT_ID` | *(empty)* | Leave empty to use the mock Plaid client |
| `PLAID_SECRET` | *(empty)* | Leave empty to use the mock Plaid client |

---

## What Is Not Yet Built

The following are stubbed or deferred for future implementation:

| Feature | Current State | Notes |
|---|---|---|
| Real Plaid integration | Mock client with simulated latency | Swap `plaid.NewMockClient()` in [auth/jit.go](internal/auth/jit.go) for the Plaid Go SDK |
| Settlement worker | `SettleTransaction()` exists but is not called | Needs an async worker that listens for ACH confirmations and calls it |
| Member / group management APIs | No endpoints | CRUD routes for creating groups and adding members |
| Authentication | No user auth | JWT or session middleware for the iOS client |
| Wallet top-up | `tally_balance_cents` column exists | No endpoint to add funds to a member's wallet yet |
| Reversal webhook | `ReverseTransaction()` exists but is not wired | Needs a `/v1/webhooks/reversal` endpoint |
