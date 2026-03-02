# Tally

**Real-time group spending. No one fronts. No one chases.**

Tally is a fintech platform that eliminates the social and financial friction of group spending. Unlike IOU trackers (Splitwise) or P2P apps (Venmo), Tally splits a payment at the exact millisecond of the transaction — so nobody fronts money and nobody has to ask for it back.

---

## Why Tally Exists

Every group payment tool today has the same flaw: **one person gets stuck covering the bill**. They front $300 for dinner, then spend the next week sending passive-aggressive reminders to friends. The debt lingers. The friendship strains.

Tally solves this at the infrastructure level. When a Tally card is swiped, the system identifies the group and authorizes the transaction in under two seconds — then charges every member's linked debit card automatically.

---

## How It Works

### 1. The Proxy Card Architecture

Each Tally group has a single virtual card account (via Stripe Issuing). Every member gets their own unique virtual card token, added to their Apple/Google Wallet. To each user it feels like they're all using the "Group Card."

When any member taps at a merchant, Tally's backend resolves their card token to the group, splits the charge across all members, and responds to Stripe with APPROVE or DECLINE — in ~20ms.

| Problem | Traditional Shared Card | Tally Proxy Model |
|---------|------------------------|-------------------|
| KYC/Identity | Who is legally responsible? | Each member is KYC'd individually via Stripe Identity |
| Security | One lost card locks everyone out | Freeze one member's token without affecting others |
| Tracking | Hard to see who spent what | Every transaction is tagged with the initiating member's token |
| Limits | One shared limit for the whole group | Per-member controls |

### 2. Just-In-Time (JIT) Authorization

When any group member taps their card at a merchant, Stripe sends an authorization webhook to Tally's backend:

```
Member taps card at register
        │
        ▼
Stripe sends issuing_authorization.created webhook
        │
        ▼
Backend resolves card token → group + all members
        │
        ▼
Verify every member has a linked debit card
        │
        ▼
Write PENDING ledger entries for all members
        │
        ▼
APPROVE — Stripe fronts the merchant charge
        │
        ▼
Settlement worker charges each member's debit card
```

Total JIT latency: **~20–50ms** (Postgres reads only, no external API calls). Stripe's deadline is 2 seconds — Tally responds with a 40× safety margin.

### 3. Funding Model

Every member must link a debit card (Stripe PaymentMethod) before joining a group. This single invariant makes the JIT handler simple: because every member has a card on file, the transaction is always approved at swipe time. The actual debit happens at settlement.

| Stage | What Happens |
|-------|-------------|
| **Card swipe** | Stripe fronts the merchant charge from Stripe's own funds |
| **Settlement** | Settlement worker charges each member's linked debit card via Stripe PaymentIntent |
| **Card failure** | Retry → backup card → leader cover → flag for review |

There is no wallet preloading or ACH balance check. Funding is debit-only.

### 4. Leader Cover Fail-Safe

To prevent embarrassing declines when a member's card fails at settlement:

- Each group designates a **Group Leader**
- Before an outing, the leader taps **Pre-authorize** in the app (valid for 24 hours)
- If a member's primary and backup cards both fail at settlement, the leader's card covers the shortfall
- An **IOU** is recorded in the ledger: the member owes the leader
- The IOU is tracked in-app and can be marked settled when repaid out-of-band

The card never declines because of one member's card failure — leader cover ensures the group always completes the purchase.

### 5. The Double-Entry Ledger

Every swipe produces an immutable accounting record:

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
2. **Link a Debit Card** — Each member links their bank debit card via Stripe
3. **Complete KYC** — Each member verifies their identity via Stripe Identity
4. **Configure Splits** — Choose equal, percentage-based, or weighted splits
5. **Designate a Leader** — The person who serves as the fail-safe backstop
6. **Issue Card Tokens** — Each member receives their own virtual card token for Apple/Google Wallet

### Making a Purchase

1. **Any member** taps their personal card token at a merchant
2. Stripe sends an authorization webhook to Tally's backend
3. Tally resolves the card token to the group and loads all members
4. Tally writes PENDING ledger entries and responds APPROVE (~20ms)
5. Stripe pays the merchant from Stripe's funds
6. Settlement worker immediately charges each member's debit card
7. All members see the transaction in-app with their individual share

### When a Member's Card Fails at Settlement

1. **Retry** — The settlement worker retries the primary card once
2. **Backup card** — If retry fails, the backup card is charged
3. **Leader Cover** — If both fail and the leader has pre-authorized, the leader's card covers the shortfall and an IOU is recorded
4. **Flag for review** — If all paths fail, the funding pull is marked FAILED and ops is alerted

---

## Spending Configurations

| Mode | How It Works | Example |
|------|-------------|---------|
| **Equal** | Total ÷ number of members | 4 people, $100 dinner → $25 each |
| **Percentage** | Fixed percentages per member | Alice 50%, Bob 25%, Carol 25% |
| **Weighted** | Fractional multipliers | Bob has 2× weight → pays double Alice's share |

Split weights are stored as 6-decimal-precision fractions (e.g. `0.250000`). The sum of all weights in a group must equal `1.000000`.

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
| Language | Go 1.23 | Goroutines for concurrent ledger writes; deterministic latency |
| HTTP | Gin | High-performance routing with composable middleware |
| Database | PostgreSQL 16 | ACID + serializable transactions for ledger integrity |
| Cache / Lock | Redis 7 | Sub-millisecond idempotency checks and distributed locking |
| Card Issuing | Stripe Issuing | Virtual card issuance; Apple/Google Wallet provisioning; JIT webhooks |
| Debit Charging | Stripe PaymentIntents | Settlement charges against linked debit cards |
| Bank Linking | Stripe Financial Connections | Debit card attachment via SetupIntent flow |
| Identity / KYC | Stripe Identity | Document verification before card issuance |
| Auth | Clerk | RS256 JWT for user-facing routes |
| Migrations | golang-migrate | SQL embedded in binary; auto-runs on boot |
| Containers | Docker Compose | Single command brings up the full local stack |

### Key Design Decisions

**JIT is Postgres-only.** The authorization handler makes zero external API calls. All data needed to approve or decline is stored in Postgres. This is how the 2-second Stripe window is met with a 40× margin.

**Debit required before joining.** Every member must link a debit card (`stripe_payment_method_id`) before they can be added to a group. This invariant means JIT can always approve — there are no missing cards to discover at swipe time.

**Leader cover lives at settlement, not JIT.** Since all members have cards, JIT always approves. Leader cover fires in the settlement worker when a member's card actually declines — exactly where the failure occurs.

**Integer cents everywhere.** All monetary amounts are stored as `BIGINT` cents. `$25.99` is stored as `2599`. No floating-point rounding errors.

**Two webhook signature schemes.** `/v1/auth/jit` uses a custom HMAC-SHA256 scheme. `/v1/webhooks/stripe/*` uses Stripe's native `stripe.ConstructEvent()` with a timestamp to prevent replay attacks.

**Redis idempotency + DB backstop.** The Redis cache returns cached responses in microseconds for retry requests. The database `UNIQUE(idempotency_key)` constraint is a final backstop if Redis is unavailable.

---

## Getting Started (Backend)

### Prerequisites

- Docker Desktop
- Go 1.23+

### Run Locally

```bash
cd backend

# Copy and configure environment
cp .env.example .env
# Edit .env — WEBHOOK_SECRET is required; Stripe keys optional (mock clients used if unset)

# Start the full stack (Postgres + Redis + App)
docker compose up --build
```

The API is available at `http://localhost:8080`.
Swagger UI (interactive docs) is at `http://localhost:8080/swagger/index.html`.

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | Postgres connection string |
| `REDIS_URL` | Yes | Redis URL |
| `WEBHOOK_SECRET` | Yes | HMAC secret for `/v1/auth/jit` signature verification |
| `STRIPE_SECRET_KEY` | No | Stripe API key — leave empty to use mock clients |
| `STRIPE_WEBHOOK_SECRET` | No | Stripe webhook signing secret for `/v1/webhooks/stripe/*` |
| `STRIPE_ISSUING_CARD_PRODUCT` | No | Stripe Issuing card product ID |
| `CLERK_JWKS_URL` | No | Clerk JWKS URL — leave empty to use dev auth bypass |
| `DEV_USER_ID` | No | User ID injected by dev auth bypass (default: `dev-user-local`) |
| `PORT` | No | HTTP listen port (default: `8080`) |
| `ENV` | No | `development` or `production` |

---

## API Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/healthz` | Health check |
| `POST` | `/v1/users/me` | Create or update the authenticated user |
| `POST` | `/v1/users/me/kyc` | Start a Stripe Identity KYC session |
| `POST` | `/v1/users/me/payment-method` | Create a SetupIntent to link a primary debit card |
| `POST` | `/v1/users/me/payment-method/confirm` | Save the linked primary debit card |
| `POST` | `/v1/users/me/payment-method/backup` | Create a SetupIntent to link a backup debit card |
| `POST` | `/v1/users/me/payment-method/backup/confirm` | Save the linked backup debit card |
| `POST` | `/v1/groups` | Create a spending group |
| `GET` | `/v1/groups` | List groups the authenticated user belongs to |
| `GET` | `/v1/groups/:id` | Get group details and members |
| `POST` | `/v1/groups/:id/members` | Add a member to a group |
| `GET` | `/v1/groups/:id/transactions` | List recent transactions |
| `GET` | `/v1/groups/:id/transactions/:txnId` | Get transaction detail with per-member splits |
| `GET` | `/v1/groups/:id/ious` | List outstanding IOUs in the group |
| `POST` | `/v1/groups/:id/ious/:iouId/settle` | Mark an IOU as settled |
| `POST` | `/v1/groups/:id/leader/authorize` | Leader pre-authorizes cover for the next 24 hours |
| `DELETE` | `/v1/groups/:id/leader/authorize` | Leader revokes pre-authorization |
| `GET` | `/v1/groups/:id/leader/authorize` | Get leader pre-authorization status |
| `POST` | `/v1/cards/issue` | Issue a virtual card to a member (KYC required) |
| `POST` | `/v1/auth/jit` | JIT authorization endpoint (called by card processor) |
| `POST` | `/v1/webhooks/stripe/issuing-authorization` | Stripe Issuing authorization webhook |
| `POST` | `/v1/webhooks/stripe/reversal` | Stripe reversal/refund webhook |
| `POST` | `/v1/webhooks/stripe/identity` | Stripe Identity KYC result webhook |

Full request/response examples: see [backend/TESTING.md](backend/TESTING.md).
Full backend technical writeup: see [backend/BACKEND.md](backend/BACKEND.md).

### Security

**User-facing routes** (`/v1/groups/*`, `/v1/cards/*`, `/v1/users/*`) require a Clerk JWT in the `Authorization: Bearer <token>` header. In local development with `CLERK_JWKS_URL` unset, `DEV_USER_ID` is injected automatically.

**JIT endpoint** (`/v1/auth/jit`) requires an HMAC-SHA256 signature:
```
X-Tally-Signature: sha256=<hex(HMAC-SHA256(WEBHOOK_SECRET, rawBody))>
```

**Stripe webhook endpoints** (`/v1/webhooks/stripe/*`) use Stripe's native signature scheme verified via `stripe.ConstructEvent()`.

---

## What's Next

| Feature | Status |
|---------|--------|
| Push notifications (APNS/FCM) | Planned |
| Stripe PM background validity refresh | Planned |
| Spending analytics per member / per group | Planned |
| iOS UI for all new endpoints | In progress |
