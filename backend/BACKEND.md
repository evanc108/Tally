# Tally Backend — Technical Writeup

## Overview

Tally's backend is a Go service that powers real-time group spending using a **Proxy Card Architecture**. Rather than sharing a single card, each group member receives their own unique virtual card token — all mapped to the same group. When any member taps their token at a merchant, the backend authorizes the charge in milliseconds by confirming that every member has a linked debit card, then charges each member's card asynchronously at settlement.

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Language | Go 1.23 | Goroutines for concurrent ledger writes; fast compile + deploy |
| HTTP Framework | Gin | High-performance routing with middleware chains |
| Database | PostgreSQL 16 | Double-entry ledger requires ACID guarantees + serializable transactions |
| Cache / Lock | Redis 7 | Sub-millisecond idempotency checks and distributed locking |
| Card Issuing | Stripe Issuing | Virtual card issuance; Apple/Google Wallet provisioning; JIT authorization webhooks |
| Debit Charging | Stripe PaymentIntents | Settlement charges against linked debit cards |
| Bank Linking | Stripe Financial Connections | Debit card attachment via SetupIntent |
| Identity / KYC | Stripe Identity | Document verification before card issuance |
| Auth | Clerk | RS256 JWT verification via JWKS |
| Schema Migrations | golang-migrate | SQL files embedded in the binary; runs automatically on boot |
| Containerization | Docker Compose | Single command brings up the full local stack |

---

## Project Structure

```
backend/
├── main.go                              Entry point — wires everything together
├── docker-compose.yml                   Local stack: Postgres + Redis + App
├── Dockerfile                           Multi-stage build → distroless runtime image
├── go.mod
└── internal/
    ├── auth/
    │   └── jit.go                       POST /v1/auth/jit — JIT authorization handler
    ├── cards/
    │   └── handler.go                   POST /v1/cards/issue — card issuance with KYC gate
    ├── config/
    │   └── config.go                    Loads all config from environment variables
    ├── db/
    │   ├── db.go                        Connection pool (Postgres + Redis)
    │   ├── migrate.go                   Runs embedded SQL migrations on boot
    │   └── migrations/
    │       ├── 000001_init.up.sql       Full base schema
    │       ├── 000007_stripe_migration  Drops Plaid/Highnote columns, adds Stripe columns
    │       ├── 000008_kyc_status        Adds kyc_status to members
    │       ├── 000012_cards             cards table with lifecycle status + backward-compat trigger
    │       ├── 000013_receipts          receipts, receipt_items, receipt_item_assignments tables
    │       └── ...
    ├── groups/
    │   └── handler.go                   Group, member, transaction, IOU, leader auth endpoints
    ├── ledger/
    │   └── posting.go                   Double-entry accounting engine (bulk inserts)
    ├── receipts/
    │   └── session_handler.go           Receipt session CRUD — create/assign/finalize/cancel
    ├── middleware/
    │   ├── clerk.go                     Clerk JWT verification (RS256 via JWKS)
    │   ├── devauth.go                   Dev bypass — injects DEV_USER_ID when CLERK_JWKS_URL unset
    │   ├── group.go                     RequireGroupMember, RequireGroupLeader
    │   ├── hmac.go                      HMAC-SHA256 verification for /v1/auth/jit
    │   ├── idempotency.go               Redis-backed request deduplication
    │   ├── logger.go                    Structured JSON request logging
    │   └── ratelimit.go                 Redis rate limiter
    ├── settlement/
    │   └── settle.go                    SettleApprovedTransaction + background worker
    ├── stripeidentity/
    │   └── client.go                    Stripe Identity KYC — real + mock
    ├── stripeissuing/
    │   └── client.go                    Stripe Issuing cardholder + card — real + mock
    ├── stripepayment/
    │   └── client.go                    Stripe SetupIntent + PaymentIntent — real + mock
    ├── users/
    │   └── handler.go                   User upsert, payment method, KYC endpoints
    ├── waterfall/
    │   └── waterfall.go                 Resolves card token → group + members; builds funding plan
    └── webhooks/
        └── stripe.go                    Stripe Issuing authorization, reversal, Identity webhooks
```

---

## Database Schema

Eleven tables form the complete data model. All monetary values are stored as **integer cents** (never floats) to avoid rounding errors.

### `users`
One row per Tally user account, keyed by Clerk user ID.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| clerk_user_id | TEXT | Unique. From the Clerk JWT `sub` claim |
| email | TEXT | |
| first_name | TEXT | |
| last_name | TEXT | |

### `tally_groups`
Represents a spending group (e.g. "Weekend Trip", "Shared Apartment").

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| name | TEXT | Short identifier |
| display_name | TEXT | Human-readable label |
| currency | CHAR(3) | Default `USD` |

### `members`
One row per user per group. A user in three groups has three rows.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| group_id | UUID | FK → tally_groups |
| user_id | UUID | FK → users |
| display_name | TEXT | Name shown in the group UI |
| card_token | TEXT | Unique. The member's virtual card token (Stripe Issuing) |
| stripe_cardholder_id | TEXT | Stripe Issuing cardholder ID |
| stripe_card_id | TEXT | Stripe Issuing card ID |
| stripe_payment_method_id | TEXT | Primary linked debit card. Used for settlement |
| stripe_backup_payment_method_id | TEXT | Fallback debit card if primary fails |
| kyc_status | TEXT | `pending` / `approved` / `rejected`. Card issuance requires `approved` |
| tally_balance_cents | BIGINT | Reserved; not currently used |
| split_weight | NUMERIC(7,6) | Fractional share (e.g. `0.250000` for a 4-way equal split). Sum across group must = 1.0 |
| is_leader | BOOL | True for the one designated group leader |
| leader_pre_authorized | BOOL | Leader has opted in to cover member card failures for the current outing |
| leader_pre_authorized_at | TIMESTAMPTZ | When pre-authorization was set. Expires after 24 hours |

Linking a debit card (`stripe_payment_method_id`) is required before a user can join a group. This invariant allows the JIT handler to always approve without checking balances.

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
| `PENDING` | Created when the swipe arrives |
| `APPROVED` | Ledger entries written; Stripe told to approve |
| `DECLINED` | Could not be authorized |
| `SETTLED` | All members' debit cards have been charged |
| `REVERSED` | Transaction was unwound (e.g. merchant refund) |

The `idempotency_key` column has a `UNIQUE` constraint as a backstop against duplicate processing if Redis is bypassed.

### `journal_entries`
The immutable double-entry ledger. Every financial event writes at least one row here. Entries are never deleted or updated; reversals create new offsetting rows.

| Column | Notes |
|---|---|
| debit_account_id | The account being debited |
| credit_account_id | The account being credited |
| amount_cents | Always positive |
| status | `PENDING` → `SETTLED` or `REVERSED` |

A constraint (`chk_no_self_entry`) enforces that debit and credit accounts can never be the same.

### `funding_pulls`
Records how each member's share will be (or was) collected. One row per member per transaction.

| funding_type | Meaning |
|---|---|
| `direct_pull` | Charged to the member's linked debit card via Stripe at settlement |
| `leader_overwrite` | Member's cards failed; leader's card covered the share. An IOU is recorded |
| `tally_balance` | Reserved; not used in current flow |

### `iou_entries`
Records shortfalls covered by the group leader. Created by the settlement worker when a member's primary and backup cards both fail and leader cover is active.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| debtor_member_id | UUID | The member who was short |
| creditor_member_id | UUID | The leader who covered |
| transaction_id | UUID | The transaction that triggered the IOU |
| amount_cents | BIGINT | Amount covered |
| status | TEXT | `OUTSTANDING` → `SETTLED` |

### `receipts`
One row per receipt session. Created before a card swipe to enable itemized splitting.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| group_id | UUID | FK → tally_groups |
| created_by_user_id | TEXT | Clerk user ID of the member who scanned the receipt |
| merchant_name | TEXT | From the parsed receipt |
| total_cents | BIGINT | Total bill amount in cents |
| status | TEXT | `draft` → `finalized` → `deleted` |
| transaction_id | UUID | Set atomically by JIT when this receipt is consumed. NULL until then |
| updated_at | TIMESTAMPTZ | Used to compute the 2-hour finalization expiry window |

A receipt is consumable only once: the JIT handler sets `transaction_id` with `WHERE transaction_id IS NULL`, so concurrent JIT requests cannot both claim the same receipt.

### `receipt_items`
One row per line item on a receipt.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| receipt_id | UUID | FK → receipts |
| name | TEXT | Item description |
| quantity | INT | Number of units |
| unit_price_cents | BIGINT | Per-unit price |
| total_cents | BIGINT | `quantity × unit_price_cents` |

### `receipt_item_assignments`
Records which member claimed which item and how much they owe for it.

| Column | Type | Notes |
|---|---|---|
| id | UUID | Primary key |
| receipt_item_id | UUID | FK → receipt_items |
| member_id | UUID | FK → members |
| amount_cents | BIGINT | Member's share of this item (validated server-side) |

A UNIQUE constraint on `(receipt_item_id, member_id)` prevents duplicate claims. Server validation enforces that `amount_cents` falls within the mathematically correct floor/ceil range for each item.

---

## The Double-Entry Ledger

Every card swipe produces one journal entry **per member**:

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

**Example — Bob's card declines at settlement, leader cover activates:**

Journal entries are written identically at JIT time (all `direct_pull`). When the settlement worker charges Bob's card and it fails:

1. Retry Bob's primary card — fails
2. Try Bob's backup card — fails
3. Leader (Dave) is pre-authorized — charge Dave's card for Bob's $25
4. Update Bob's `funding_pull` to `leader_overwrite`
5. Write `iou_entry`: Bob owes Dave $25

The journal entries themselves do not change. Settlement status is tracked in `funding_pulls` and `iou_entries`.

**On reversal**, debit and credit sides are swapped in new offsetting entries. Original entries are never touched.

The ledger package exposes three functions:
- `PostPendingTransaction` — writes PENDING journal entries and funding_pulls atomically (bulk inserts)
- `SettleTransaction` — marks entries SETTLED after the settlement worker has charged all cards
- `ReverseTransaction` — writes offsetting entries to unwind an approved transaction

All three use **SERIALIZABLE isolation** to prevent phantom reads when multiple authorizations arrive simultaneously for the same group.

---

## The JIT Authorization Flow

`POST /v1/auth/jit` is the critical path. Stripe sends this webhook when a member taps their card. **Stripe requires a response within ~2 seconds or it auto-declines.**

### Why 2 Seconds Is Easily Met

The JIT handler makes **zero external API calls**. All data is in Postgres.

```
Step                           How                  Typical latency
──────────────────────────────────────────────────────────────────
1. resolveCard()               Postgres read         ~5–15ms
2. insertPendingTransaction()  Postgres write        ~5–10ms
3. ResolveReceiptSplit()       Postgres read         ~5–10ms  (optional)
4. buildFundingPlan()          In-memory             <1ms
5. PostPendingTransaction()    Postgres write        ~5–10ms
6. linkReceiptToTransaction()  Postgres write        ~3–5ms   (optional)
──────────────────────────────────────────────────────────────────
Total JIT handler time (no receipt)                ~20–40ms
Total JIT handler time (with receipt)              ~30–50ms
Stripe's response deadline                         ~2,000ms
Safety margin                                      ~40×
```

This is possible because members must link a debit card before joining a group. By swipe time, every member is guaranteed to have a `stripe_payment_method_id`. No balance checks, no external calls needed.

```
Stripe Issuing
     │
     │  POST /v1/auth/jit  (or /v1/webhooks/stripe/issuing-authorization)
     │  X-Tally-Signature: sha256=<hex>
     │  Idempotency-Key: <uuid>
     ▼
┌────────────────────────────────────────────────────────────────┐
│  Middleware Chain                                              │
│  1. RateLimit            — per-IP request cap                 │
│  2. HMACVerification     — reject unsigned requests           │
│  3. Idempotency          — replay cached response if repeat   │
└────────────────────────────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────────────────┐
│  JIT Handler  (1.5s timeout)                                  │
│                                                                │
│  1. ResolveCard()                                              │
│     card_token → group_id + all member rows + account IDs     │
│                                                                │
│  2. insertPendingTransaction()                                 │
│     Writes PENDING transaction row immediately                 │
│                                                                │
│  3. ResolveReceiptSplit()       [if receipt session active]   │
│     Finds finalized receipt for this group with no txn linked │
│     Validates updated_at within 2-hour window                 │
│     Returns map[memberID]amountCents from assignments          │
│                                                                │
│  4. BuildFundingPlan()  (receipt-based or split_weight)       │
│     With receipt: use item assignment amounts per member       │
│     Without: compute each member's share from split_weight    │
│     Fallback: if receipt produced 0 splits → use split_weight  │
│     Hard decline: if still 0 splits → DECLINE no_funding_plan │
│                                                                │
│  5. PostPendingTransaction()                                   │
│     Serializable Postgres transaction writes atomically:       │
│       • N journal_entries  (one per member, PENDING)           │
│       • N funding_pulls    (one per member, direct_pull)       │
│                                                                │
│  6. LinkReceiptToTransaction()  [if receipt was used]         │
│     UPDATE receipts SET transaction_id = $1                   │
│     WHERE id = $2 AND transaction_id IS NULL                   │
│     (atomic — concurrent JIT requests cannot both claim it)   │
│                                                                │
│  7. Respond to Stripe (~30–50ms after request arrived)        │
└────────────────────────────────────────────────────────────────┘
     │
     ▼
{ "decision": "APPROVE", "transaction_id": "..." }
```

---

## Receipt Sessions (Itemized Splitting)

Receipt sessions allow members to claim specific items on a bill before swiping, so each person is charged only for what they ordered. The flow is entirely pre-swipe; by the time the card is tapped, JIT just reads pre-computed amounts.

### Session Lifecycle

```
POST /v1/groups/:id/receipts          → status: draft
PUT  /v1/groups/:id/receipts/:id/assignments  (each member, one or more times)
POST /v1/groups/:id/receipts/:id/finalize     → status: finalized  (leader only)
                                        ↓
                             card swipe triggers JIT
                                        ↓
                     receipts.transaction_id = <txn_id>   (consumed)
```

Cancellation is available at any point before finalization (`DELETE /v1/groups/:id/receipts/:id`).

### Security Properties

| Property | Implementation |
|---|---|
| IDOR prevention | All queries scope receipt to `group_id`; members can only access their own group's receipts |
| Finalize authorization | Leader-only (checked via `IsLeaderKey` in gin context) |
| Cancel authorization | Creator or leader only |
| Amount validation | Server recomputes floor/ceil from `receipt_items.total_cents`; client-supplied `amount_cents` is rejected if outside that range |
| Concurrent sessions | `CreateReceipt` auto-cancels any existing unlinked draft for the group inside the same DB transaction |
| Single-use enforcement | `UPDATE receipts SET transaction_id = $1 WHERE id = $2 AND transaction_id IS NULL`; only one JIT request can claim a receipt |
| Expiry | Receipt must have `updated_at > NOW() - INTERVAL '2 hours'` at JIT time (starts from finalization, not creation) |

### Fallback Behavior

| Scenario | JIT Result |
|---|---|
| No finalized receipt exists for the group | Use `split_weight` allocation (normal flow) |
| Finalized receipt exists but all assignments sum to 0 | Fall back to `split_weight` |
| Fallback also produces 0 splits | DECLINE with `no_funding_plan` |

---

## Settlement

Settlement is decoupled from authorization. Stripe has already fronted the merchant charge; settlement recoups that from each member's debit card.

```
For each APPROVED transaction:

  For each member:
    1. Charge stripe_payment_method_id (Stripe PaymentIntent, with idempotency key)
    2. On failure: retry once (same card)
    3. On retry failure: charge stripe_backup_payment_method_id
    4. On both fail + leader pre-authorized (within 24h):
         a. Charge leader's stripe_payment_method_id for member's share
         b. Write iou_entry (debtor=member, creditor=leader)
         c. Update funding_pull.funding_type = 'leader_overwrite'
    5. On all paths fail: funding_pull.status = FAILED, alert ops

  After all members settled:
    → ledger.SettleTransaction()
    → transaction.status = SETTLED
```

The settlement worker runs as a goroutine immediately after each JIT APPROVE, and also as a background poll every 30 seconds as a safety net for any missed goroutines.

---

## Leader Cover

Leader cover is a settlement-layer fail-safe. Because every member must link a card before joining, JIT always approves. Leader cover handles what happens when a member's card **declines at settlement**.

Before a group outing the leader taps **Pre-authorize** in the app:
- Sets `leader_pre_authorized = true`, `leader_pre_authorized_at = NOW()`
- Authorization window is **24 hours**

| Scenario | Result |
|---|---|
| Member's card declines at settlement | Retry → backup card → leader cover → FAILED |
| Leader authorization expired (>24h) | Leader cover skipped; pull marked FAILED |
| Leader's own card declines | Flagged for review; no self-cover |

---

## Safety & Reliability

### Two Webhook Signature Schemes

**`/v1/auth/jit` — Custom HMAC:**
```
X-Tally-Signature: sha256=<hex(HMAC-SHA256(WEBHOOK_SECRET, rawBody))>
```

**`/v1/webhooks/stripe/*` — Stripe's native scheme:**
```
Stripe-Signature: t=<timestamp>,v1=<sig>
```
Verified via `webhook.ConstructEvent()` from the Stripe Go SDK. This scheme includes a timestamp to prevent replay attacks. The custom HMAC middleware must **not** be applied to these routes.

### Idempotency

1. **Cache check** — if `idem:resp:<key>` exists in Redis, replay immediately
2. **Distributed lock** — acquire `idem:lock:<key>` with `SET NX`. Concurrent duplicate gets `409`
3. **Cache write** — response cached for 24 hours (non-5xx only)
4. **DB backstop** — `UNIQUE(idempotency_key)` on `transactions` catches anything Redis misses

### Rate Limiting

The JIT endpoint and Stripe webhook endpoints are rate-limited via Redis. The JIT limit prevents a compromised HMAC key from flooding Postgres writes.

---

## Middleware Stack

```
gin.Recovery()          Catches panics, returns 500
RequestLogger()         Structured JSON logging (method, path, status, latency_ms)
RateLimit()             Redis sliding window                [/v1/auth, /v1/webhooks/stripe]
HMACVerification()      X-Tally-Signature validation        [/v1/auth/jit only]
Idempotency()           Redis cache + SET NX lock           [/v1/auth/jit only]
ClerkAuth() or DevAuth() JWT verification or dev bypass    [all /v1 user-facing routes]
RequireGroupMember()    Verifies caller is in the group     [/v1/groups/:id/*]
RequireGroupLeader()    Verifies caller is group leader     [leader authorize endpoints]
```

---

## Local Development

```bash
cd backend

# 1. Copy and configure environment
cp .env.example .env
# Set WEBHOOK_SECRET to any string. Leave Stripe keys empty to use mock clients.

# 2. Start the full stack
docker compose up --build

# 3. App is live at http://localhost:8080
# 4. Swagger UI at http://localhost:8080/swagger/index.html
```

Migrations run automatically on boot. They are embedded in the binary via `//go:embed migrations/*.sql` and are safe to run multiple times (all use `IF NOT EXISTS` / `IF EXISTS`).

With `STRIPE_SECRET_KEY` empty, the app uses mock Stripe clients that return deterministic fake IDs — no Stripe account required for local development.

With `CLERK_JWKS_URL` empty, all user-facing routes authenticate as `DEV_USER_ID` automatically — no Clerk token required.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Postgres connection string |
| `REDIS_URL` | — | Redis connection URL |
| `WEBHOOK_SECRET` | — | Shared HMAC secret for `/v1/auth/jit` |
| `STRIPE_SECRET_KEY` | *(empty)* | Stripe API key — empty = mock clients |
| `STRIPE_WEBHOOK_SECRET` | *(empty)* | Stripe webhook signing secret for `/v1/webhooks/stripe/*` |
| `STRIPE_ISSUING_CARD_PRODUCT` | *(empty)* | Stripe Issuing card product ID |
| `CLERK_JWKS_URL` | *(empty)* | Clerk JWKS URL — empty = dev auth bypass |
| `DEV_USER_ID` | `dev-user-local` | User ID injected by dev auth bypass |
| `PORT` | `8080` | HTTP listen port |
| `ENV` | `development` | `production` enables Gin release mode |
