# Backend API Testing Guide

## Prerequisites

Start the stack before running any requests:

```bash
cd backend
docker-compose up
```

All endpoints are available at `http://localhost:8080`.

Set a shell variable for convenience:

```bash
BASE=http://localhost:8080
```

---

## 1. Health Check

Verify the server is up and the database connection is healthy.

```bash
curl -s $BASE/healthz | jq .
```

Expected:

```json
{ "status": "ok" }
```

---

## 2. Create a Group

```bash
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name": "Trip to Vegas", "currency": "USD"}' | jq .)

echo $GROUP
GROUP_ID=$(echo $GROUP | jq -r '.group_id')
```

Expected (201 Created):

```json
{
  "group_id": "<uuid>",
  "name": "Trip to Vegas",
  "currency": "USD",
  "created_at": "2026-03-01T00:00:00Z"
}
```

---

## 3. Add Members

Add four members with equal 25% splits. The first member is the group leader.

```bash
# Leader
ALICE=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{
    "display_name": "Alice",
    "split_weight": 0.25,
    "is_leader": true,
    "plaid_access_token": "access-sandbox-alice",
    "plaid_account_id": "alice-checking-001"
  }' | jq .)

ALICE_ID=$(echo $ALICE | jq -r '.member_id')

# Members
BOB_ID=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Bob", "split_weight": 0.25}' | jq -r '.member_id')

CAROL_ID=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Carol", "split_weight": 0.25}' | jq -r '.member_id')

DAN_ID=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Dan", "split_weight": 0.25}' | jq -r '.member_id')
```

Expected per member (201 Created):

```json
{
  "member_id": "<uuid>",
  "user_id": "<uuid>",
  "display_name": "Alice",
  "split_weight": 0.25
}
```

---

## 4. Inspect Group State

```bash
curl -s $BASE/v1/groups/$GROUP_ID | jq .
```

Expected (200 OK):

```json
{
  "group_id": "<uuid>",
  "name": "Trip to Vegas",
  "currency": "USD",
  "members": [
    {
      "member_id": "<uuid>",
      "display_name": "Alice",
      "split_weight": 0.25,
      "tally_balance_cents": 0,
      "is_leader": true,
      "has_card": false
    },
    ...
  ]
}
```

Leaders appear first; remaining members are sorted by name.

---

## 5. Issue a Virtual Card

The card is issued to a specific member (typically the leader). The returned `card_token` is used to authorize purchases.

```bash
CARD=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{
    \"member_id\": \"$ALICE_ID\",
    \"first_name\": \"Alice\",
    \"last_name\": \"Smith\",
    \"email\": \"alice@example.com\"
  }" | jq .)

echo $CARD
CARD_TOKEN=$(echo $CARD | jq -r '.card_token')
```

Expected (201 Created):

```json
{
  "cardholder_id": "<highnote-cardholder-id>",
  "card_id": "<highnote-card-id>",
  "card_token": "<card-token>"
}
```

After issuing, `has_card: true` will appear in `GET /v1/groups/:id`.

---

## 6. Load Wallet Balances

Pre-load Tally wallet credit for members so Tier 1 of the funding waterfall can be exercised.

```bash
# Load $50.00 for Alice
curl -s -X POST $BASE/v1/wallets/load \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$ALICE_ID\", \"amount_cents\": 5000}" | jq .

# Load $50.00 for Bob
curl -s -X POST $BASE/v1/wallets/load \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$BOB_ID\", \"amount_cents\": 5000}" | jq .
```

Expected (200 OK):

```json
{ "new_balance_cents": 5000 }
```

---

## 7. JIT Authorization

### Generating an HMAC Signature

The `/v1/auth/jit` and `/v1/webhooks/highnote/authorization` endpoints require a valid HMAC-SHA256 signature. The secret defaults to `dev_webhook_secret_change_in_prod` when running locally.

```bash
WEBHOOK_SECRET="dev_webhook_secret_change_in_prod"

sign_body() {
  local body="$1"
  echo -n "$body" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'
}
```

### Scenario A — Tally Wallet Covers Full Amount (Tier 1)

Both Alice and Bob have $50 loaded. A $40 purchase splits to $10/member — covered entirely by Tally balances.

```bash
BODY='{
  "idempotency_key": "txn-001",
  "card_token": "'"$CARD_TOKEN"'",
  "amount_cents": 4000,
  "currency": "USD",
  "merchant_name": "The Steakhouse",
  "merchant_category": "5812"
}'

SIG=$(sign_body "$BODY")

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: txn-001" \
  -H "X-Tally-Signature: $SIG" \
  -d "$BODY" | jq .
```

Expected (200 OK):

```json
{
  "decision": "APPROVE",
  "transaction_id": "<uuid>",
  "approved_amount_cents": 4000,
  "reason": ""
}
```

### Scenario B — Direct Pull Fallback (Tier 2)

Members have $0 Tally balance, but Alice has a linked Plaid account. The mock Plaid client returns a non-zero balance, exercising the direct pull path.

```bash
# Confirm no wallet balance by checking group state
curl -s $BASE/v1/groups/$GROUP_ID | jq '.members[].tally_balance_cents'

BODY='{
  "idempotency_key": "txn-002",
  "card_token": "'"$CARD_TOKEN"'",
  "amount_cents": 2000,
  "currency": "USD",
  "merchant_name": "Walgreens",
  "merchant_category": "5912"
}'

SIG=$(sign_body "$BODY")

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: txn-002" \
  -H "X-Tally-Signature: $SIG" \
  -d "$BODY" | jq .
```

### Scenario C — Idempotency (Replay)

Re-send the same request with the same `Idempotency-Key`. The server must return the cached response without creating a second transaction.

```bash
# Resend txn-001 exactly as before
curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: txn-001" \
  -H "X-Tally-Signature: $SIG" \
  -d "$BODY" | jq .
```

The `transaction_id` must be identical to the first response.

### Scenario D — Invalid HMAC (Rejected)

```bash
curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: txn-bad" \
  -H "X-Tally-Signature: sha256=deadbeef" \
  -d "$BODY" | jq .
```

Expected (401 Unauthorized):

```json
{ "error": "invalid signature" }
```

### Scenario E — Decline (No Funds)

Use a card token that has no members with any balance and no Plaid accounts configured.

```bash
BODY='{
  "idempotency_key": "txn-decline",
  "card_token": "'"$CARD_TOKEN"'",
  "amount_cents": 99999999,
  "currency": "USD"
}'

SIG=$(sign_body "$BODY")

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: txn-decline" \
  -H "X-Tally-Signature: $SIG" \
  -d "$BODY" | jq .
```

Expected:

```json
{
  "decision": "DECLINE",
  "transaction_id": "",
  "approved_amount_cents": 0,
  "reason": "insufficient funds"
}
```

---

## 8. Highnote Webhook Authorization

The Highnote webhook uses the `HIGHNOTE_WEBHOOK_SECRET` for HMAC signing and expects a Highnote-specific payload format.

```bash
HN_SECRET="3ac94708bea182cb1bc6503fccff3347"  # matches .env default

sign_hn() {
  local body="$1"
  echo -n "$body" | openssl dgst -sha256 -hmac "$HN_SECRET" | awk '{print "sha256="$2}'
}

HN_BODY='{
  "id": "evt-hn-001",
  "type": "AUTHORIZATION_REQUEST",
  "authorizationRequestId": "hn-auth-req-001",
  "cardId": "'"$CARD_TOKEN"'",
  "transactionAmount": {
    "value": 3500,
    "currencyCode": "USD"
  },
  "merchantDetails": {
    "name": "MGM Grand",
    "categoryCode": "7011"
  }
}'

HN_SIG=$(sign_hn "$HN_BODY")

curl -s -X POST $BASE/v1/webhooks/highnote/authorization \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: hn-auth-req-001" \
  -H "X-Tally-Signature: $HN_SIG" \
  -d "$HN_BODY" | jq .
```

Expected (200 OK — always 200 per card processor spec):

```json
{
  "authorizationResponseCode": "APPROVED",
  "approvedTransactionAmount": {
    "value": 3500,
    "currencyCode": "USD"
  }
}
```

On decline, `authorizationResponseCode` will be `DO_NOT_HONOR` with no amount field.

---

## 9. List Transactions

Fetch the 50 most recent transactions for the group.

```bash
curl -s $BASE/v1/groups/$GROUP_ID/transactions | jq .
```

Expected (200 OK):

```json
{
  "transactions": [
    {
      "id": "<uuid>",
      "amount_cents": 4000,
      "currency": "USD",
      "merchant_name": "The Steakhouse",
      "merchant_category": "5812",
      "status": "PENDING",
      "created_at": "2026-03-01T00:00:00Z"
    }
  ]
}
```

---

## 10. Full Happy-Path Flow (End-to-End)

Run this sequence in order to exercise every layer of the system:

```bash
# 1. Verify health
curl -s $BASE/healthz | jq .

# 2. Create group
GROUP_ID=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name": "E2E Test Group"}' | jq -r '.group_id')

# 3. Add leader member
LEADER_ID=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Leader", "split_weight": 0.5, "is_leader": true}' \
  | jq -r '.member_id')

# 4. Add regular member
MEMBER_ID=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Member", "split_weight": 0.5}' \
  | jq -r '.member_id')

# 5. Load wallets
curl -s -X POST $BASE/v1/wallets/load \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$LEADER_ID\", \"amount_cents\": 10000}" | jq .

curl -s -X POST $BASE/v1/wallets/load \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$MEMBER_ID\", \"amount_cents\": 10000}" | jq .

# 6. Issue card
CARD_TOKEN=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{
    \"member_id\": \"$LEADER_ID\",
    \"first_name\": \"Test\",
    \"last_name\": \"Leader\",
    \"email\": \"leader@example.com\"
  }" | jq -r '.card_token')

# 7. Authorize a purchase
BODY="{
  \"idempotency_key\": \"e2e-$(date +%s)\",
  \"card_token\": \"$CARD_TOKEN\",
  \"amount_cents\": 8000,
  \"currency\": \"USD\",
  \"merchant_name\": \"E2E Merchant\"
}"

SIG=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "dev_webhook_secret_change_in_prod" | awk '{print "sha256="$2}')

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: e2e-$(date +%s)" \
  -H "X-Tally-Signature: $SIG" \
  -d "$BODY" | jq .

# 8. Verify transaction appears
curl -s $BASE/v1/groups/$GROUP_ID/transactions | jq '.transactions[0]'

# 9. Verify wallet balances decremented
curl -s $BASE/v1/groups/$GROUP_ID | jq '.members[].tally_balance_cents'
```

---

## 11. Edge Cases & Error Conditions

| Scenario | Expected Status | Notes |
|----------|----------------|-------|
| `POST /v1/groups` missing `name` | 400 | Required field |
| `POST /v1/groups/:id/members` bad group UUID | 404 | Group not found |
| `POST /v1/wallets/load` with `amount_cents: 0` | 400 | Must be > 0 |
| `POST /v1/wallets/load` unknown `member_id` | 404 | Member not found |
| `POST /v1/cards/issue` unknown `member_id` | 404 | Member not found |
| `POST /v1/auth/jit` missing HMAC header | 401 | Signature required |
| `POST /v1/auth/jit` wrong HMAC secret | 401 | Constant-time compare |
| `POST /v1/auth/jit` duplicate `Idempotency-Key` (concurrent) | 409 | Lock contention |
| `GET /v1/groups/:id` unknown group | 404 | Group not found |
| `GET /v1/groups/:id/transactions` unknown group | 404 | Group not found |

---

## Swagger UI

Interactive API documentation is available at:

```
http://localhost:8080/swagger/index.html
```

All endpoints can be tested directly from the browser using the Swagger UI.
