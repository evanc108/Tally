# Backend API Testing Guide

## Prerequisites

```bash
cd backend

# Configure environment (first time only)
cp .env.example .env
# Set WEBHOOK_SECRET to any string, e.g. "localtestingsecret"
# Leave STRIPE_SECRET_KEY empty to use mock Stripe clients

# Start the full stack
docker compose up --build
```

All endpoints are available at `http://localhost:8080`.

```bash
BASE=http://localhost:8080

# Optional: install jq for pretty JSON output
# brew install jq
```

With `CLERK_JWKS_URL` unset, all user-facing routes authenticate as `DEV_USER_ID` automatically — no token needed.

---

## 1. Health Check

```bash
curl -s $BASE/healthz | jq .
# → {"status":"ok"}
```

---

## 2. Create a User

```bash
USER=$(curl -s -X POST $BASE/v1/users/me \
  -H "Content-Type: application/json" \
  -d '{
    "clerk_user_id": "dev-user-local",
    "email": "test@example.com",
    "first_name": "Test",
    "last_name": "User"
  }')

echo $USER | jq .
USER_ID=$(echo $USER | jq -r '.user_id')
```

---

## 3. Create a Group

```bash
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name": "trip-to-vegas", "display_name": "Trip to Vegas"}')

echo $GROUP | jq .
GROUP_ID=$(echo $GROUP | jq -r '.group_id')

# The creator is automatically added as the first member.
# The creator member_id is returned in the response.
CREATOR_MEMBER_ID=$(echo $GROUP | jq -r '.creator_member_id')
```

---

## 4. Add More Members

Add a second member with a complementary split weight. All weights in the group must sum to exactly `1.0`.

```bash
# Update creator split to 0.5 first — requires psql since there's no update endpoint yet
docker compose exec postgres psql -U tally -d tally -c \
  "UPDATE members SET split_weight = 0.5 WHERE id = '$CREATOR_MEMBER_ID';"

# Add second member (another user would need their own user row in prod)
MEMBER2=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Friend", "split_weight": 0.5}')

echo $MEMBER2 | jq .
MEMBER2_ID=$(echo $MEMBER2 | jq -r '.member_id')
```

---

## 5. Set Up KYC and Debit Card (dev shortcut)

Stripe Identity KYC requires real document photos in production. For local dev, set `kyc_status` directly in Postgres. Similarly, `stripe_payment_method_id` is normally set via the SetupIntent flow — for testing, insert a mock value.

```bash
# Approve KYC and set payment methods for both members
docker compose exec postgres psql -U tally -d tally -c "
  UPDATE members
  SET kyc_status = 'approved',
      stripe_payment_method_id = 'pm_mock_primary',
      stripe_backup_payment_method_id = 'pm_mock_backup'
  WHERE group_id = '$GROUP_ID';"
```

---

## 6. Issue Virtual Cards

Each member gets their own unique card token (mock returns `card_mock_1`, `card_mock_2`, etc.).

```bash
# Issue card to creator
CARD1=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{
    \"member_id\": \"$CREATOR_MEMBER_ID\",
    \"first_name\": \"Test\",
    \"last_name\": \"User\",
    \"email\": \"test@example.com\"
  }")

echo $CARD1 | jq .
CARD_TOKEN=$(echo $CARD1 | jq -r '.card_token')

# Issue card to second member
CARD2=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{
    \"member_id\": \"$MEMBER2_ID\",
    \"first_name\": \"Friend\",
    \"last_name\": \"Smith\",
    \"email\": \"friend@example.com\"
  }")

echo $CARD2 | jq .
CARD2_TOKEN=$(echo $CARD2 | jq -r '.card_token')
```

---

## 7. Inspect Group State

```bash
curl -s $BASE/v1/groups/$GROUP_ID | jq .
```

Each member should show `"has_card": true` after card issuance.

---

## 8. JIT Authorization

### Helper — generate HMAC signature

```bash
WEBHOOK_SECRET="localtestingsecret"  # must match WEBHOOK_SECRET in .env

sign_body() {
  local body="$1"
  printf '%s' "$body" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'
}
```

### Scenario A — Successful Authorization (APPROVE)

Any member's card token can initiate a purchase for the whole group.

**Use the same `WEBHOOK_SECRET` as in `backend/.env`.** Avoid putting `# comments` on the same line as variable assignments when pasting into zsh, or the comment can be run as a command and the variable may not be set.

```bash
# Set secret exactly as in backend/.env (no trailing comment on this line)
WEBHOOK_SECRET="27d557ac4f56a640cb084c2d0c27dadcafe5032d94680f52647bbf6691d0b71a"
BASE=http://localhost:8080
sign_body() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'; }

BODY=$(cat <<EOF
{
  "idempotency_key": "txn-001",
  "card_token": "$CARD_TOKEN",
  "amount_cents": 10000,
  "currency": "usd",
  "merchant_name": "The Steakhouse",
  "merchant_category": "5812"
}
EOF
)

SIG=$(sign_body "$BODY")

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $SIG" \
  -H "Idempotency-Key: txn-001" \
  -d "$BODY" | jq .
```

**Full flow in one go** (so `GROUP_ID` and `TXN_ID` are set for later steps like GET transaction). Run from repo root; ensure `backend/.env` has the same `WEBHOOK_SECRET` and `DEV_USER_ID` (e.g. `dev-user-local`).

```bash
BASE=http://localhost:8080
export WEBHOOK_SECRET=$(grep '^WEBHOOK_SECRET=' backend/.env | cut -d= -f2)
sign_body() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'; }

curl -s -X POST $BASE/v1/users/me -H "Content-Type: application/json" -d '{"clerk_user_id":"dev-user-local","email":"test@example.com","first_name":"Test","last_name":"User"}' > /dev/null
GROUP=$(curl -s -X POST $BASE/v1/groups -H "Content-Type: application/json" -d '{"name":"jit-test","display_name":"JIT Test"}')
GROUP_ID=$(echo "$GROUP" | jq -r '.group_id')
MEMBER_ID=$(echo "$GROUP" | jq -r '.member_id')

curl -s -X POST $BASE/v1/users/me/payment-method -H "Content-Type: application/json" > /dev/null
curl -s -X POST $BASE/v1/users/me/payment-method/confirm -H "Content-Type: application/json" -d "{\"member_id\":\"$MEMBER_ID\",\"payment_method_id\":\"pm_mock_primary\"}" > /dev/null
docker compose -f backend/docker-compose.yml exec -T postgres psql -U tally -d tally -c "UPDATE members SET kyc_status = 'approved' WHERE id = '$MEMBER_ID';" > /dev/null 2>&1

CARD=$(curl -s -X POST $BASE/v1/cards/issue -H "Content-Type: application/json" -d "{\"member_id\":\"$MEMBER_ID\",\"first_name\":\"Test\",\"last_name\":\"User\",\"email\":\"test@example.com\"}")
CARD_TOKEN=$(echo "$CARD" | jq -r '.card_token')

IDEM_KEY="txn-$(date +%s)"
BODY="{\"idempotency_key\":\"$IDEM_KEY\",\"card_token\":\"$CARD_TOKEN\",\"amount_cents\":10000,\"currency\":\"usd\",\"merchant_name\":\"The Steakhouse\",\"merchant_category\":\"5812\"}"
SIG=$(sign_body "$BODY")
JIT=$(curl -s -X POST $BASE/v1/auth/jit -H "Content-Type: application/json" -H "X-Tally-Signature: $SIG" -H "Idempotency-Key: $IDEM_KEY" -d "$BODY")
echo "$JIT" | jq .
TXN_ID=$(echo "$JIT" | jq -r '.transaction_id')
echo "GROUP_ID=$GROUP_ID TXN_ID=$TXN_ID"
```

Then wait 35s and run: `curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq .`

Expected (200 OK):
```json
{
  "decision": "APPROVE",
  "transaction_id": "<uuid>"
}
```

### Scenario B — Idempotency (same key, replayed)

Re-send the exact same request. The server must return the cached response without creating a duplicate transaction.

```bash
curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $SIG" \
  -H "Idempotency-Key: txn-001" \
  -d "$BODY" | jq .
# transaction_id must be identical to the first response
```

### Scenario C — Invalid HMAC (rejected)

```bash
curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: sha256=deadbeef" \
  -H "Idempotency-Key: txn-bad" \
  -d "$BODY" | jq .
# → {"error":"invalid_signature"}  (401)
```

### Scenario D — Unknown card token (DECLINE)

```bash
BAD_BODY='{"idempotency_key":"txn-unknown","card_token":"card_does_not_exist","amount_cents":1000,"currency":"usd"}'
BAD_SIG=$(sign_body "$BAD_BODY")

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $BAD_SIG" \
  -H "Idempotency-Key: txn-unknown" \
  -d "$BAD_BODY" | jq .
# → {"decision":"DECLINE","reason":"authorization_failed"}
```

---

## 9. List Transactions

```bash
curl -s $BASE/v1/groups/$GROUP_ID/transactions | jq .
```

---

## 10. Transaction Detail

```bash
TXN_ID="<transaction_id from step 8>"

curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq .
```

Returns the transaction with per-member splits and any IOUs.

---

## 10b. Settlement test (30-second sweep)

When you use `POST /v1/auth/jit` (not the Stripe webhook), settlement is **not** triggered immediately. The background worker sweeps for `APPROVED` transactions older than 30 seconds and runs settlement then. To verify settlement (mock “pull” from the dummy debit card):

1. Run the full flow through JIT (user → group → debit card → KYC → issue card → JIT) so you have `TXN_ID` and `GROUP_ID`.
2. Wait **35 seconds** for the sweep to pick up the transaction.
3. Get the transaction detail; you should see `"status": "SETTLED"` and each split `"status": "COMPLETED"`.

```bash
# After JIT, wait for settlement sweep (30s interval)
sleep 35

curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq .
# Expect: status "SETTLED", splits[].status "COMPLETED"
```

With mock Stripe, the “debit card” is `pm_mock_primary` (from payment-method/confirm). The settlement worker calls the mock client, which returns success without a real charge. To test a **real** Stripe charge (test mode, no real money), set `STRIPE_SECRET_KEY` in `.env`, attach a test PaymentMethod (e.g. card `4242 4242 4242 4242` via Stripe.js or Stripe CLI), then run the same flow; settlement will create a real PaymentIntent against that card.

**Verifying settlement and correct amounts**

1. **Settlement ran** — `GET .../transactions/$TXN_ID` → `status` is `"SETTLED"` and every `splits[].status` is `"COMPLETED"`.
2. **Right amounts per member** — Splits follow each member's `split_weight`. Single member: `splits[0].amount_cents` should equal the transaction `amount_cents`. Multiple members: sum of `splits[].amount_cents` must equal the transaction total, and each split = total × that member's split_weight (e.g. equal 4-way → 25% each).
   ```bash
   curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq '{ total: .amount_cents, sum_splits: ([.splits[].amount_cents] | add), splits: [.splits[] | {display_name, amount_cents, status}] }'
   ```
   Check `sum_splits == total` and each split amount matches the expected share.
3. **Real Stripe (test mode)** — With `STRIPE_SECRET_KEY` set and a real test PaymentMethod, after settlement check Stripe Dashboard → Payments (or `stripe payment_intents list`); the charged amount should match that member's split for that transaction.
4. **DB (optional)** — Query `funding_pulls` and `journal_entries` to confirm amounts in SQL.

---

## 11. Leader Pre-Authorization

The creator must be marked as leader first:

```bash
docker compose exec postgres psql -U tally -d tally -c \
  "UPDATE members SET is_leader = true WHERE id = '$CREATOR_MEMBER_ID';"
```

Then pre-authorize via the API (caller must be the leader):

```bash
# Pre-authorize (valid for 24 hours)
curl -s -X POST $BASE/v1/groups/$GROUP_ID/leader/authorize | jq .

# Check status (any member can read)
curl -s $BASE/v1/groups/$GROUP_ID/leader/authorize | jq .

# Revoke
curl -s -X DELETE $BASE/v1/groups/$GROUP_ID/leader/authorize | jq .
```

---

## 12. IOUs

IOUs are created automatically by the settlement worker when a member's cards fail and leader cover activates. To inspect them:

```bash
curl -s $BASE/v1/groups/$GROUP_ID/ious | jq .
```

Mark an IOU settled (after the member pays the leader back out-of-band):

```bash
IOU_ID="<iou_id>"
curl -s -X POST $BASE/v1/groups/$GROUP_ID/ious/$IOU_ID/settle | jq .
```

---

## 13. Payment Method Flow (with real Stripe)

> These endpoints require `STRIPE_SECRET_KEY` to be set in `.env`. Skip for mock mode.

```bash
# Step 1: Create SetupIntent — returns client_secret for iOS app
curl -s -X POST $BASE/v1/users/me/payment-method | jq .

# Step 2: iOS app completes SetupIntent using client_secret (Stripe handles card entry)
# After completion, iOS gets the pm_id from Stripe and calls:

curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d '{"payment_method_id": "pm_xxxx"}' | jq .

# Same flow for backup card:
curl -s -X POST $BASE/v1/users/me/payment-method/backup | jq .
curl -s -X POST $BASE/v1/users/me/payment-method/backup/confirm \
  -H "Content-Type: application/json" \
  -d '{"payment_method_id": "pm_yyyy"}' | jq .
```

---

## 14. KYC Flow (with real Stripe)

> Requires `STRIPE_SECRET_KEY` to be set in `.env`. Skip for mock mode — use the psql shortcut in Step 5 instead.

```bash
# Step 1: Create Identity verification session — returns URL for iOS WebView
curl -s -X POST $BASE/v1/users/me/kyc \
  -H "Content-Type: application/json" \
  -d '{"member_id": "<member_id>"}' | jq .

# Step 2: User completes identity check in iOS WebView

# Step 3: Stripe sends identity.verification_session.verified webhook to:
# POST /v1/webhooks/stripe/identity
# This updates kyc_status to 'approved' automatically
```

---

## 15. Full Happy-Path (End-to-End)

```bash
BASE=http://localhost:8080
WEBHOOK_SECRET="localtestingsecret"

# 1. Health check
curl -s $BASE/healthz

# 2. Create user
curl -s -X POST $BASE/v1/users/me \
  -H "Content-Type: application/json" \
  -d '{"clerk_user_id":"dev-user-local","email":"test@example.com","first_name":"Test","last_name":"User"}'

# 3. Create group (creator auto-added as member)
GROUP_RESP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name":"e2e-test","display_name":"E2E Test"}')
GROUP_ID=$(echo $GROUP_RESP | jq -r '.group_id')
MEMBER_ID=$(echo $GROUP_RESP | jq -r '.creator_member_id')

# 4. Set up member (kyc + payment method via psql shortcut)
docker compose exec postgres psql -U tally -d tally -c \
  "UPDATE members SET kyc_status='approved', stripe_payment_method_id='pm_mock', split_weight=1.0 WHERE id='$MEMBER_ID';"

# 5. Issue card
CARD_RESP=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$MEMBER_ID\",\"first_name\":\"Test\",\"last_name\":\"User\",\"email\":\"test@example.com\"}")
CARD_TOKEN=$(echo $CARD_RESP | jq -r '.card_token')

# 6. Authorize a purchase
BODY="{\"idempotency_key\":\"e2e-$(date +%s)\",\"card_token\":\"$CARD_TOKEN\",\"amount_cents\":5000,\"currency\":\"usd\",\"merchant_name\":\"Test Merchant\"}"
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}')
IDEMPKEY="e2e-$(date +%s)"

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $SIG" \
  -H "Idempotency-Key: $IDEMPKEY" \
  -d "$BODY" | jq .

# 7. Verify transaction in group history
curl -s $BASE/v1/groups/$GROUP_ID/transactions | jq '.transactions[0]'
```

---

## Edge Cases

| Scenario | Expected Status | Notes |
|----------|----------------|-------|
| `POST /v1/groups` missing `display_name` | 400 | Required field |
| `POST /v1/groups/:id/members` with weights summing > 1.0 | 422 | Split weight validation |
| `POST /v1/cards/issue` with `kyc_status = 'pending'` | 403 | KYC required |
| `POST /v1/cards/issue` unknown `member_id` | 404 | Member not found |
| `POST /v1/auth/jit` missing HMAC header | 401 | `missing_signature` |
| `POST /v1/auth/jit` wrong HMAC secret | 401 | `invalid_signature` |
| `POST /v1/auth/jit` duplicate `Idempotency-Key` (concurrent) | 409 | Lock contention — retry in ~1s |
| `POST /v1/auth/jit` unknown card token | 422 | `DECLINE` / `authorization_failed` |
| `GET /v1/groups/:id` caller not a member | 403 | Group membership required |
| `POST /v1/groups/:id/leader/authorize` caller not leader | 403 | Leader role required |

---

## Swagger UI

Interactive API documentation with all endpoints and schemas:

```
http://localhost:8080/swagger/index.html
```
