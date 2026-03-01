# Tally

**Real-time group spending. No one fronts. No one chases.**

Tally is a next-generation fintech platform that eliminates the social and financial friction of group spending. Unlike IOU trackers (Splitwise) or P2P apps (Venmo), Tally splits a payment at the exact millisecond of the transaction — so nobody fronts money and nobody has to ask for it back.

---

## Why Tally Exists

Every group payment tool today has the same flaw: **one person gets stuck covering the bill**. They front $300 for dinner, then spend the next week sending passive-aggressive reminders to friends. The debt lingers. The friendship strains.

Tally solves this at the infrastructure level. When a Tally card is swiped, the system identifies the group, verifies every member's balance simultaneously, and authorizes the transaction only when everyone can cover their share — in under two seconds.

---

## How It Works

### 1. Just-In-Time (JIT) Funding

The centerpiece of Tally is its authorization engine. When a Tally card is presented at a merchant:

```
Card swiped at register
        │
        ▼
Tally backend receives authorization request
        │
        ▼
Identify group members from card token
        │
        ▼
Check all members' balances simultaneously (parallel Plaid calls)
        │
        ├─ Everyone can cover their share?
        │         │
        │         ▼
        │    APPROVE — merchant gets full amount
        │    Each member's account is debited their share atomically
        │
        └─ Anyone short?
                  │
                  ▼
             Apply Leader Cover or DECLINE
```

Total latency budget: **8 seconds** (bounded by the card network's authorization window). In practice, parallel balance checks typically resolve in 50–100ms.

### 2. Hybrid Funding Waterfall

Each member's share is funded in priority order:

| Tier | Source | When Used |
|------|--------|-----------|
| 1 | **Tally Wallet** (pre-loaded balance) | Preferred — no external call at settlement |
| 2 | **Direct Pull** (linked bank via Plaid/ACH) | When wallet is insufficient but bank covers the gap |
| — | **DECLINE** | If `wallet + bank < share` for any member |

A partial approval is never issued. Either the full amount is approved with every member covered, or the transaction is declined entirely.

### 3. Leader Cover Fail-Safe

To prevent embarrassing card declines when one member is temporarily short, Tally supports a **Leader Cover** system:

- Each group designates a **Group Leader** (typically the organizer)
- If a member cannot cover their share at the moment of a swipe, the Leader's account automatically covers the gap
- Tally records this as an internal **Social Debt** in the ledger
- The shortfall member owes the Leader — tracked in-app, settled on their own timeline

The card never declines due to one person's insufficient funds. The group always completes the purchase.

### 4. The Double-Entry Ledger

Every swipe produces an immutable accounting record using double-entry bookkeeping:

```
Debit  → member's asset account      (member now owes their share)
Credit → group's clearing account    (group absorbed the merchant charge)
```

**Example — $100 dinner, 4 members, equal split:**

| Entry | Debit | Credit | Amount |
|-------|-------|--------|--------|
| 1 | Alice's account | Group clearing | $25.00 |
| 2 | Bob's account | Group clearing | $25.00 |
| 3 | Carol's account | Group clearing | $25.00 |
| 4 | Dave's account | Group clearing | $25.00 |

Reversals (merchant refunds) create new offsetting entries — original records are never modified.

---

## User Workflows

### Setting Up a Spending Circle

1. **Create a Circle** — Give it a name ("Ski Trip 2026", "Shared Apartment") and currency
2. **Add Members** — Invite friends; each member links their bank account via Plaid
3. **Configure Splits** — Choose equal, percentage-based, or weighted splits (e.g., one person pays 2× because they're upgrading their room)
4. **Designate a Leader** — The person whose account serves as the fail-safe backstop
5. **Issue a Card** — A virtual card is issued instantly to the leader's Apple/Google Wallet, or a physical card can be ordered

### Making a Purchase

1. Member (typically the leader) taps/swipes the Tally card at a merchant
2. The card network pings Tally's backend with the charge amount
3. Tally checks every member's balance in parallel — this takes ~50–100ms
4. If approved, the merchant receives the full amount; each member's share is debited simultaneously
5. Every member sees the transaction appear in the app in real-time with their individual share

### When a Member Is Short

**Option A — Direct Pull covers it:** If the member's Tally wallet is empty but their linked bank has enough, Tally automatically pulls the difference. The member doesn't need to do anything.

**Option B — Leader Cover activates:** If the bank also can't cover the share, the Leader's account absorbs the shortfall. A Social Debt is created in the ledger. The member sees a notification and can repay the leader through the app at any time.

**Option C — Transaction declines:** If the Leader also cannot cover, the transaction is declined and the card is returned to the merchant. No charges are applied to anyone.

### Preloading a Wallet

For trips or events where you want guaranteed authorization speed:

1. Navigate to your Circle → **Load Wallet**
2. Enter an amount to transfer from your linked bank
3. Funds are available immediately in your Tally wallet
4. Future purchases draw from the wallet first (no Plaid call needed at the register)

### Viewing History

- The **Circle feed** shows every transaction in real-time, each with individual member amounts and funding sources
- Members can see whether their share came from their wallet or a direct bank pull
- Social debts are tracked separately under **Owed to Leader**

---

## Spending Configurations

Tally supports three split modes, configurable per-circle:

| Mode | How It Works | Example |
|------|-------------|---------|
| **Equal** | Total ÷ number of members | 4 people, $100 dinner → $25 each |
| **Percentage** | Fixed percentages set per member | Alice 50%, Bob 25%, Carol 25% |
| **Weighted** | Fractional multipliers | Bob has 2× weight → pays double Alice's share |

Split weights are stored as 6-decimal-precision fractions (e.g., `0.250000`). The sum of all weights in a group must equal `1.000000`.

---

## Card Types

| Type | Issuance | Best For |
|------|----------|----------|
| **Virtual Card** | Instant — added to Apple/Google Wallet | Weekend trips, one-time events |
| **Physical Card** | 3–5 business days | Recurring groups (roommates, teams) |

Cards are issued via Highnote (card processor) and linked to a specific member within a circle. A single member can hold cards across multiple circles.

---

## Comparison

| Feature | Splitwise / Tab | Venmo / Cash App | **Tally** |
|---------|----------------|-----------------|-----------|
| Payment Timing | Manual (post-event) | Manual (post-event) | **Real-time (at swipe)** |
| Who Fronts? | One person fronts 100% | One person fronts 100% | **Nobody** |
| Card Issuer | No | No | **Yes** |
| Bank Integration | No | Limited | **Plaid (read) + ACH (write)** |
| Fail-Safe | None | None | **Leader Cover** |
| Automation | Low | Low | **High (JIT Engine)** |
| Ledger | No | No | **Double-entry, immutable** |

---

## Architecture

Tally is a monorepo containing an iOS client and a Go backend.

```
Tally/
├── Tally/                  iOS app (Swift/Xcode)
├── TallyTests/             iOS unit tests
├── TallyUITests/           iOS UI tests
└── backend/                Go API server
```

### Backend Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | Go 1.22 | Goroutines make parallel bank checks trivial; deterministic latency |
| HTTP | Gin | High-performance routing with composable middleware |
| Database | PostgreSQL 16 | ACID + serializable transactions for ledger integrity |
| Cache / Lock | Redis 7 | Sub-millisecond idempotency checks and distributed locking |
| Card Processor | Highnote | Card issuance and authorization webhooks |
| Bank Data | Plaid | Balance verification and ACH pull authorization |
| Migrations | golang-migrate | SQL embedded in binary; auto-runs on boot |
| Containers | Docker Compose | Single command brings up the full local stack |

### Key Design Decisions

**Why Go?** The JIT authorization handler fans out one goroutine per group member to check balances simultaneously. In Python or Node, you'd need async/await gymnastics. In Go, `sync.WaitGroup` + goroutines is idiomatic and the concurrency model is trivially correct.

**Why PostgreSQL with SERIALIZABLE isolation?** Two simultaneous swipes for the same group could race to read member balances and both approve, double-spending. `SERIALIZABLE` isolation causes one transaction to abort and retry, preventing phantom reads without application-level locking.

**Why integer cents?** Floating-point arithmetic on money causes rounding errors that compound across a ledger. All amounts are stored as `BIGINT` cents. `$25.99` is stored as `2599`.

**Why Redis for idempotency instead of just the DB?** The database's `UNIQUE(idempotency_key)` is the backstop, but a DB constraint requires a round-trip and produces a hard error. Redis catches duplicates before the handler runs — returning the cached response in microseconds without touching Postgres.

**Why double-entry?** It makes the ledger self-auditing. If debits ≠ credits, something is wrong. It also enables clean reversals: a refund is just new offsetting entries rather than mutations to existing rows.

---

## Getting Started (Backend)

### Prerequisites

- Docker Desktop
- Go 1.22+

### Run Locally

```bash
cd backend

# Install dependencies
go mod tidy

# Start the full stack (Postgres + Redis + App + pgAdmin)
docker compose up --build
```

The API is available at `http://localhost:8080`.
Swagger UI (interactive docs) is at `http://localhost:8080/swagger/index.html`.
pgAdmin is at `http://localhost:5050` (email: `admin@tally.local`, password: `admin`).

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgres://tally:tally_secret@localhost:5432/tally?sslmode=disable` | Postgres connection string |
| `REDIS_URL` | `redis://localhost:6379` | Redis URL |
| `WEBHOOK_SECRET` | `dev_webhook_secret_change_in_prod` | HMAC secret for JIT auth endpoint |
| `HIGHNOTE_WEBHOOK_SECRET` | `3ac94708bea182cb1bc6503fccff3347` | HMAC secret for Highnote webhooks |
| `PORT` | `8080` | HTTP listen port |
| `ENV` | `development` | Set to `production` for Gin release mode |
| `PLAID_CLIENT_ID` | *(empty)* | Leave empty to use the mock Plaid client |
| `PLAID_SECRET` | *(empty)* | Leave empty to use the mock Plaid client |

---

## API Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/healthz` | Health check |
| `POST` | `/v1/groups` | Create a spending circle |
| `GET` | `/v1/groups/:id` | Get group with members |
| `POST` | `/v1/groups/:id/members` | Add a member to a group |
| `GET` | `/v1/groups/:id/transactions` | List recent transactions |
| `POST` | `/v1/cards/issue` | Issue a virtual card to a member |
| `POST` | `/v1/wallets/load` | Pre-load a member's Tally wallet |
| `POST` | `/v1/auth/jit` | JIT authorization (called by card processor) |
| `POST` | `/v1/webhooks/highnote/authorization` | Highnote authorization webhook |

Full request/response examples: see [backend/TESTING.md](backend/TESTING.md).
Full backend technical writeup: see [backend/BACKEND.md](backend/BACKEND.md).

### Security

All requests to `/v1/auth/jit` and Highnote webhook endpoints require an HMAC-SHA256 signature:

```
X-Tally-Signature: sha256=<hex(HMAC-SHA256(secret, rawBody))>
```

The middleware uses constant-time comparison (`hmac.Equal`) to prevent timing-oracle attacks. Unsigned requests receive `401` and never reach the handler.

---

## What's Next

| Feature | Status | Notes |
|---------|--------|-------|
| Real Plaid integration | Mock only | Swap `NewMockClient()` for the Plaid Go SDK |
| Settlement worker | Not wired | Async worker to call `SettleTransaction()` on ACH confirmation |
| Reversal webhook | Logic exists | Needs `/v1/webhooks/reversal` endpoint |
| User authentication | None yet | JWT or session middleware for iOS client |
| Wallet top-up from iOS | API ready | iOS UI not yet connected |
| Leader Cover logic | Designed | Not yet implemented in JIT handler |
| Spending analytics | Planned | Per-member and per-circle spend summaries |
