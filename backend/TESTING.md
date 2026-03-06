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

## Testing with real Stripe (STRIPE_SECRET_KEY set)

### Setup

1. Add your test key to `.env`: `STRIPE_SECRET_KEY=sk_test_...`
2. **Optional:** `STRIPE_ISSUING_CARD_PRODUCT=ic_...` (Stripe Dashboard → Issuing → Card designs). If unset, card issuance fails in real mode.
3. **Optional:** `STRIPE_WEBHOOK_SECRET=whsec_...` to receive Stripe webhooks at `POST /v1/webhooks/stripe/*`.

### Avoiding manual card approval (program setup)

Stripe Issuing can put new cardholders in review (`requirements.past_due`) so you had to approve the card in the Dashboard. To avoid that:

- **Backend:** The app sends the **individual** block when creating cardholders: `first_name`, `last_name`, and **`dob`** (required in the issue-card request, same as name — no default). That satisfies Stripe’s “Required before activating Cards” fields. For **Celtic-backed programs** (BIN sponsor Celtic), you must also collect and send **Authorized User Terms** acceptance: include `user_terms_accepted_at` (Unix timestamp when the user accepted terms in your UI). The backend sends that plus the request’s `ClientIP` and `User-Agent` to Stripe as `individual.card_issuing.user_terms_acceptance`.
- **API:** `POST /v1/cards/issue` body must include `dob: { day, month, year }`. For Celtic, also include `user_terms_accepted_at` (Unix seconds). The server uses the request’s IP and User-Agent for Stripe.
- **Dashboard:** There is no “skip cardholder review” switch. Sending full `individual` (name, DOB, and for Celtic, user terms acceptance) at cardholder creation is what keeps cards out of `past_due`.

**Restart the backend and verify real Stripe is active:**

```bash
cd backend
docker compose up -d --build
docker compose logs app 2>&1 | grep -i stripe
# Expect: "stripe real clients active" (or similar)
```

### Reference: curl / Postman commands

Use `BASE=http://localhost:8080`. For JIT, set `WEBHOOK_SECRET` to match `.env` and use the signature helper from section 8.

| Action | Method | URL | Body / Headers |
|--------|--------|-----|----------------|
| Create SetupIntent (get `client_secret`) | `POST` | `$BASE/v1/users/me/payment-method` | (no body) |
| Confirm bank (link pm to member) | `POST` | `$BASE/v1/users/me/payment-method/confirm` | `{"member_id":"<member_id>","payment_method_id":"pm_xxx"}` |
| Start KYC (get WebView URL) | `POST` | `$BASE/v1/users/me/kyc` | `{"member_id":"<member_id>"}` |
| Issue card | `POST` | `$BASE/v1/cards/issue` | `{"member_id":"<member_id>","first_name":"Test","last_name":"User","email":"test@example.com","dob":{"day":15,"month":1,"year":1990},"user_terms_accepted_at":<unix_ts>}` (Celtic: include user_terms_accepted_at) |
| JIT authorize | `POST` | `$BASE/v1/auth/jit` | Body: `{"idempotency_key":"...","card_token":"...","amount_cents":5000,"currency":"usd","merchant_name":"..."}`. Headers: `Content-Type: application/json`, `X-Tally-Signature: sha256=<HMAC of body>`, `Idempotency-Key: <same as in body>` |
| Trigger settlement (dev) | `POST` | `$BASE/v1/dev/settle/<TXN_ID>` | (no body) |
| Get transaction | `GET` | `$BASE/v1/groups/<GROUP_ID>/transactions/<TXN_ID>` | — |

**Copy-paste curl examples (real Stripe):**

```bash
BASE=http://localhost:8080

# 1) Create SetupIntent — use client_secret in Stripe.js or iOS to collect bank; then confirm with pm_xxx
curl -s -X POST $BASE/v1/users/me/payment-method -H "Content-Type: application/json" | jq .

# 2) Confirm payment method for a member (after completing SetupIntent; use real pm_xxx from Stripe)
curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d '{"member_id":"<MEMBER_ID>","payment_method_id":"pm_xxxx"}' | jq .

# 3) Start KYC — returns client_secret/URL for Stripe Identity WebView
curl -s -X POST $BASE/v1/users/me/kyc \
  -H "Content-Type: application/json" \
  -d '{"member_id":"<MEMBER_ID>"}' | jq .

# 4) Issue card (requires STRIPE_ISSUING_CARD_PRODUCT). dob required; user_terms_accepted_at required for Celtic programs.
curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d '{"member_id":"<MEMBER_ID>","first_name":"Test","last_name":"User","email":"test@example.com","dob":{"day":15,"month":1,"year":1990},"user_terms_accepted_at":'"$(date +%s)"'}' | jq .

# 5) JIT — sign body with WEBHOOK_SECRET (see section 8 for sign_body helper)
# BODY='{"idempotency_key":"jit-1","card_token":"<CARD_TOKEN>","amount_cents":5000,"currency":"usd","merchant_name":"Test"}'
# SIG=$(sign_body "$BODY")
# curl -s -X POST $BASE/v1/auth/jit -H "Content-Type: application/json" -H "X-Tally-Signature: $SIG" -H "Idempotency-Key: jit-1" -d "$BODY" | jq .

# 6) Trigger settlement (dev only) then check transaction
# curl -s -X POST $BASE/v1/dev/settle/<TXN_ID>
# curl -s $BASE/v1/groups/<GROUP_ID>/transactions/<TXN_ID> | jq .
```

**Postman:** Use the table above: same URLs, `Content-Type: application/json`, and for JIT compute `X-Tally-Signature` as `sha256=<HMAC-SHA256(body, WEBHOOK_SECRET)>` (hex).

### Full flow (real Stripe)

| Step | What to do |
|------|------------|
| 1 | **Create a User** (section 2) |
| 2 | **Create a Group** (section 3) — save `GROUP_ID`, `member_id` (creator) |
| 3 | **Add More Members** (section 4) if needed; save `MEMBER2_ID` |
| 4 | **ACH:** Run **1)** and **2)** above with a real bank (test: [Stripe test bank](https://docs.stripe.com/testing#ach-direct-debit)). Or shortcut: section 5 (psql `stripe_payment_method_id`, `kyc_status`). |
| 5 | **KYC:** Run **3)** and complete in WebView; webhook sets `kyc_status`. Or shortcut: section 5. |
| 6 | **Issue card:** Run **4)** (needs `STRIPE_ISSUING_CARD_PRODUCT`). |
| 7 | **JIT:** Run **5)** (sign body; see section 8). |
| 8 | Wait **35s** or run **6)**; then GET transaction — expect `status: "SETTLED"`, splits `"COMPLETED"`. Check Stripe Dashboard → Payments for ACH. |

**Quick one-shot with real Stripe:** Use **Full Happy-Path** (section 15) or **$400 dinner** (section 16); for real ACH in section 16, use a real `pm_xxx` from one completed SetupIntent in the psql `UPDATE`.

### Test ACH mandate + DOB/user terms (no Stripe dashboard)

These curls verify that **user agreement** (ACH mandate) and **DOB + user terms** (card issuing) are sent correctly so you don’t have to fix things in the Stripe Dashboard.

**Prereqs:** `STRIPE_SECRET_KEY=sk_test_...` in `.env`, backend running (`docker compose up -d`), `BASE=http://localhost:8080`.

**1. Create user and group**

```bash
BASE=http://localhost:8080

# Create user
curl -s -X POST $BASE/v1/users/me \
  -H "Content-Type: application/json" \
  -d '{"clerk_user_id":"dev-user-local","email":"test@example.com","first_name":"Test","last_name":"User"}' | jq .

# Create group (save member_id for next steps)
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name":"ach-test-'$(date +%s)'","display_name":"ACH Test"}')
echo "$GROUP" | jq .
MEMBER_ID=$(echo "$GROUP" | jq -r '.member_id')
echo "MEMBER_ID=$MEMBER_ID"
```

**2. ACH: SetupIntent + mandate (user agreement)**

The mandate is the “user agreement” for ACH. Confirm the SetupIntent with Stripe **including mandate_data**; then attach the resulting PaymentMethod to your member via the app.

```bash
# Create SetupIntent (our API creates/uses Stripe Customer)
SETI_RESP=$(curl -s -X POST $BASE/v1/users/me/payment-method -H "Content-Type: application/json")
echo "$SETI_RESP" | jq .
CLIENT_SECRET=$(echo "$SETI_RESP" | jq -r '.client_secret')
SETI_ID="${CLIENT_SECRET%_secret_*}"
if [ -z "$SETI_ID" ] || [ "$SETI_ID" = "null" ]; then echo "ERROR: no client_secret"; exit 1; fi

# Confirm with Stripe (mandate = customer acceptance; use test bank)
STRIPE_KEY=$(grep '^STRIPE_SECRET_KEY=' .env | cut -d= -f2)
CONFIRM=$(curl -s "https://api.stripe.com/v1/setup_intents/$SETI_ID/confirm" \
  -u "${STRIPE_KEY}:" \
  -d payment_method=pm_usBankAccount_success \
  -d "mandate_data[customer_acceptance][type]=online" \
  -d "mandate_data[customer_acceptance][online][ip_address]=127.0.0.1" \
  -d "mandate_data[customer_acceptance][online][user_agent]=curl")
echo "$CONFIRM" | jq .
PM_ID=$(echo "$CONFIRM" | jq -r '.payment_method')
if [ -z "$PM_ID" ] || [ "$PM_ID" = "null" ]; then echo "ERROR: confirm failed"; exit 1; fi
echo "PM_ID=$PM_ID"

# Attach PM to member (our API)
curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$MEMBER_ID\",\"payment_method_id\":\"$PM_ID\"}" | jq .
# → {"status":"payment_method_attached"}
```

**3. DOB + user terms (issue card)**

Card issuing requires KYC approved. Either complete KYC in the WebView (step 3 in “Copy-paste curl examples” above) or for a quick test set it in DB. Then issue the card **with `dob` and `user_terms_accepted_at`** so Stripe doesn’t put the cardholder in review.

```bash
# Optional: if you didn’t do KYC in browser, one-time DB shortcut for this member:
# docker compose exec -T postgres psql -U tally -d tally -c \
#   "UPDATE members SET kyc_status = 'approved' WHERE id = '$MEMBER_ID';"

# Issue card (dob required; user_terms_accepted_at required for Celtic)
curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d '{"member_id":"'$MEMBER_ID'","first_name":"Test","last_name":"User","email":"test@example.com","dob":{"day":15,"month":1,"year":1990},"user_terms_accepted_at":'$(date +%s)'}' | jq .
```

- **ACH:** Mandate is set when you confirm the SetupIntent with `mandate_data[customer_acceptance]`; the app then stores the returned `payment_method_id` on the member. No dashboard change needed.
- **Card:** Sending `dob` and `user_terms_accepted_at` (and the backend sending IP/User-Agent) satisfies Stripe so the cardholder isn’t stuck in `past_due`.

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
CREATOR_MEMBER_ID=$(echo $GROUP | jq -r '.member_id')
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

## 5. Set Up KYC and Bank Account (dev shortcut)

Stripe Identity KYC requires real document photos in production. For local dev, set `kyc_status` directly in Postgres. Similarly, `stripe_payment_method_id` is normally set via the SetupIntent flow (ACH bank account) — for testing, insert a mock value.

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
# Issue card to creator (dob required; user_terms_accepted_at for Celtic)
CARD1=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{
    \"member_id\": \"$CREATOR_MEMBER_ID\",
    \"first_name\": \"Test\",
    \"last_name\": \"User\",
    \"email\": \"test@example.com\",
    \"dob\": {\"day\": 15, \"month\": 1, \"year\": 1990},
    \"user_terms_accepted_at\": $(date +%s)
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
    \"email\": \"friend@example.com\",
    \"dob\": {\"day\": 20, \"month\": 6, \"year\": 1985},
    \"user_terms_accepted_at\": $(date +%s)
  }")

echo $CARD2 | jq .
CARD2_TOKEN=$(echo $CARD2 | jq -r '.card_token')
```

---

## 7. Inspect Group Statteste

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

CARD=$(curl -s -X POST $BASE/v1/cards/issue -H "Content-Type: application/json" -d "{\"member_id\":\"$MEMBER_ID\",\"first_name\":\"Test\",\"last_name\":\"User\",\"email\":\"test@example.com\",\"dob\":{\"day\":15,\"month\":1,\"year\":1990},\"user_terms_accepted_at\":$(date +%s)}")
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

When you use `POST /v1/auth/jit` (not the Stripe webhook), settlement is **not** triggered immediately. The background worker sweeps for `APPROVED` transactions older than 30 seconds and runs settlement then. To verify settlement (mock “pull” from the dummy bank account):

1. Run the full flow through JIT (user → group → bank account → KYC → issue card → JIT) so you have `TXN_ID` and `GROUP_ID`.
2. Wait **35 seconds** for the sweep to pick up the transaction.
3. Get the transaction detail; you should see `"status": "SETTLED"` and each split `"status": "COMPLETED"`.

```bash
# After JIT, wait for settlement sweep (30s interval)
sleep 35

curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq .
# Expect: status "SETTLED", splits[].status "COMPLETED"
```

With mock Stripe, the “bank account” is `pm_mock_primary` (from payment-method/confirm). The settlement worker calls the mock client, which returns success without a real charge. To test a **real** Stripe ACH charge (test mode), set `STRIPE_SECRET_KEY` in `.env`, complete the SetupIntent flow with a US bank account (e.g. via Stripe test mode or Financial Connections), then run the same flow; settlement will create a real PaymentIntent (ACH) against that bank account.

**Verifying settlement and correct amounts**

1. **Settlement ran** — `GET .../transactions/$TXN_ID` → `status` is `"SETTLED"` and every `splits[].status` is `"COMPLETED"`.
2. **Right amounts per member** — Splits follow each member's `split_weight`. Single member: `splits[0].amount_cents` should equal the transaction `amount_cents`. Multiple members: sum of `splits[].amount_cents` must equal the transaction total, and each split = total × that member's split_weight (e.g. equal 4-way → 25% each).
  ```bash
   curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq '{ total: .amount_cents, sum_splits: ([.splits[].amount_cents] | add), splits: [.splits[] | {display_name, amount_cents, status}] }'
  ```
   Check `sum_splits == total` and each split amount matches the expected share.
3. **Real Stripe (test mode)** — With `STRIPE_SECRET_KEY` set and a real linked bank account (ACH), after settlement check Stripe Dashboard → Payments (or `stripe payment_intents list`); the charged amount should match that member's split for that transaction.
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

IOUs are created automatically by the settlement worker when a member's payment methods (e.g. ACH) fail and leader cover activates. To inspect them:

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
> SetupIntent uses `us_bank_account` (ACH); the client completes bank account linking and sends the resulting PaymentMethod ID.

```bash
# Step 1: Create SetupIntent — returns client_secret for iOS app (ACH bank account)
curl -s -X POST $BASE/v1/users/me/payment-method | jq .

# Step 2: iOS app completes SetupIntent using client_secret (Stripe handles bank account collection)
# After completion, iOS gets the pm_id from Stripe and calls:

curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d '{"payment_method_id": "pm_xxxx"}' | jq .

# Same flow for backup bank account:
curl -s -X POST $BASE/v1/users/me/payment-method/backup | jq .
curl -s -X POST $BASE/v1/users/me/payment-method/backup/confirm \
  -H "Content-Type: application/json" \
  -d '{"payment_method_id": "pm_yyyy"}' | jq .
```

---

## 14. Setting up KYC (Stripe Identity)

KYC uses Stripe Identity. The backend already exposes `POST /v1/users/me/kyc` and `POST /v1/webhooks/stripe/identity`; you only need to configure Stripe and env.

### 14.1 Environment

- **`STRIPE_SECRET_KEY`** — Required for creating verification sessions. Same key as Issuing/Payments.
- **`STRIPE_WEBHOOK_SECRET`** — Required for the Identity webhook. If unset, the identity webhook returns 503 with a hint.

### 14.2 Local development (Stripe CLI)

1. Install Stripe CLI and log in: `brew install stripe/stripe-cli/stripe` then `stripe login`.
2. Start your backend (e.g. `docker compose up`).
3. In another terminal, run:
   ```bash
   cd backend && ./scripts/stripe_listen_identity.sh
   ```
4. Copy the **signing secret** (`whsec_...`) from the script output into `.env`:
   ```bash
   STRIPE_WEBHOOK_SECRET=whsec_...
   ```
5. Restart the backend so it picks up the new secret.
6. When a user completes verification in the browser, Stripe will send events to your local server and the backend will set `kyc_status` to `approved` or `rejected`.

### 14.3 Deployed / staging

1. Stripe Dashboard → **Developers** → **Webhooks** → **Add endpoint**.
2. **Endpoint URL:** `https://your-api-host/v1/webhooks/stripe/identity`.
3. **Events:** `identity.verification_session.verified`, `identity.verification_session.requires_input`.
4. Copy the **Signing secret** into your env as `STRIPE_WEBHOOK_SECRET`.

### 14.4 Client flow

1. **Start KYC:** `POST /v1/users/me/kyc` with `{"member_id": "<member_id>"}`. Response includes `session_id` and `url`.
2. **Open URL** in a WebView (or browser). The user completes Stripe’s document verification.
3. **Result:** Stripe sends a webhook to your backend; the backend updates `members.kyc_status` to `approved` or `rejected`. Your app can poll the member (e.g. `GET /v1/groups/:id/members`) or refresh state to see the new status.

### 14.5 curl + WebView test

```bash
BASE=http://localhost:8080
MEMBER_ID=<your_member_id>

# Create verification session (returns URL to open)
curl -s -X POST $BASE/v1/users/me/kyc \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$MEMBER_ID\"}" | jq .

# Open the "url" from the response in a browser; complete verification.
# Then Stripe sends identity.verification_session.verified to POST /v1/webhooks/stripe/identity
# and the backend sets kyc_status = 'approved' for that member.
```

### 14.6 Dev shortcut (skip real verification)

To test card issuance without running Identity, set KYC in the DB:

```bash
docker compose exec -T postgres psql -U tally -d tally -c \
  "UPDATE members SET kyc_status = 'approved' WHERE id = '<MEMBER_ID>';"
```

---

## 15. Full Happy-Path (End-to-End)

**Mock mode only.** Uses `pm_mock` and does not call real Stripe. With `STRIPE_SECRET_KEY` set, card issue would require `STRIPE_ISSUING_CARD_PRODUCT` and settlement would fail (Stripe rejects `pm_mock`). For real Stripe sandbox, use the flow in **Testing with real Stripe** (payment-method + confirm for a real `pm_xxx`, then issue + JIT + settle), or section 16 with a real `pm_xxx` in the psql step.

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
MEMBER_ID=$(echo $GROUP_RESP | jq -r '.member_id')

# 4. Set up member (kyc + payment method via psql shortcut)
docker compose exec postgres psql -U tally -d tally -c \
  "UPDATE members SET kyc_status='approved', stripe_payment_method_id='pm_mock', split_weight=1.0 WHERE id='$MEMBER_ID';"

# 5. Issue card
CARD_RESP=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$MEMBER_ID\",\"first_name\":\"Test\",\"last_name\":\"User\",\"email\":\"test@example.com\",\"dob\":{\"day\":15,\"month\":1,\"year\":1990},\"user_terms_accepted_at\":$(date +%s)}")
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

## 16. $400 dinner, 2 people, even ACH split

End-to-end test: one person pays $400 with the Tally card; 2 people in the group (including the payer) are charged from ACH evenly ($200 each). Use mock Stripe (leave `STRIPE_SECRET_KEY` unset) and run from repo root with backend stack up (`docker compose -f backend/docker-compose.yml up -d`).

```bash
BASE=http://localhost:8080
export WEBHOOK_SECRET=$(grep '^WEBHOOK_SECRET=' backend/.env | cut -d= -f2)
sign_body() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'; }
```

**1. Create user (dev auth)**

```bash
curl -s -X POST $BASE/v1/users/me \
  -H "Content-Type: application/json" \
  -d '{"clerk_user_id":"dev-user-local","email":"test@example.com","first_name":"Test","last_name":"User"}' | jq .
```

**2. Create group (creator = payer, first member)**

```bash
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name": "dinner-test", "display_name": "Dinner Test"}')
echo "$GROUP" | jq .
GROUP_ID=$(echo "$GROUP" | jq -r '.group_id')
PAYER_MEMBER_ID=$(echo "$GROUP" | jq -r '.member_id')
```

**3. Set creator split to 0.5 and add second member (50/50)**

Run in the same terminal as step 2 so `GROUP_ID` and `PAYER_MEMBER_ID` are set. The update uses `GROUP_ID` so it doesn’t depend on `PAYER_MEMBER_ID`.

```bash
docker compose -f backend/docker-compose.yml exec -T postgres psql -U tally -d tally -c \
  "UPDATE members SET split_weight = 0.5 WHERE group_id = '$GROUP_ID' AND is_leader = true;"

MEMBER2=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Friend", "split_weight": 0.5, "user_id": "dev-user-2"}')
echo "$MEMBER2" | jq .
MEMBER2_ID=$(echo "$MEMBER2" | jq -r '.member_id')
```

**4. KYC + ACH for both members (dev shortcut)**

```bash
docker compose -f backend/docker-compose.yml exec -T postgres psql -U tally -d tally -c "
  UPDATE members
  SET kyc_status = 'approved',
      stripe_payment_method_id = 'pm_mock_primary',
      stripe_backup_payment_method_id = 'pm_mock_backup'
  WHERE group_id = '$GROUP_ID';"
```

**5. Link payer’s payment method (so settlement can charge)**

```bash
curl -s -X POST $BASE/v1/users/me/payment-method -H "Content-Type: application/json" > /dev/null
curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$PAYER_MEMBER_ID\", \"payment_method_id\": \"pm_mock_primary\"}" | jq .
```

**6. Issue card to the payer (person who “pays” at the restaurant)**

```bash
CARD=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{
    \"member_id\": \"$PAYER_MEMBER_ID\",
    \"first_name\": \"Test\",
    \"last_name\": \"User\",
    \"email\": \"test@example.com\",
    \"dob\": {\"day\": 15, \"month\": 1, \"year\": 1990},
    \"user_terms_accepted_at\": $(date +%s)
  }")
echo "$CARD" | jq .
CARD_TOKEN=$(echo "$CARD" | jq -r '.card_token')
```

If you see `"error": "db write failed"`, the response includes `insert_error` and `fallback_error` in development; ensure all migrations have run and step 1 (create user) ran.

**7. JIT: authorize $400 dinner**

```bash
IDEM_KEY="dinner-400-$(date +%s)"
BODY="{\"idempotency_key\":\"$IDEM_KEY\",\"card_token\":\"$CARD_TOKEN\",\"amount_cents\":40000,\"currency\":\"usd\",\"merchant_name\":\"Dinner Spot\",\"merchant_category\":\"5812\"}"
SIG=$(sign_body "$BODY")

JIT=$(curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $SIG" \
  -H "Idempotency-Key: $IDEM_KEY" \
  -d "$BODY")
echo "$JIT" | jq .
TXN_ID=$(echo "$JIT" | jq -r '.transaction_id')
```

**8. Trigger settlement (dev-only; no 30s wait)**

If you get 404, the `/v1/dev/settle` route only exists when `ENV` is not `production`. Ensure `ENV=development` in `backend/.env` and restart the app. Alternatively, wait 35 seconds and the background settlement sweep will run; then run step 9.

```bash
curl -s -w "\nHTTP %{http_code}" -X POST "$BASE/v1/dev/settle/$TXN_ID"
# If you get JSON, pipe to jq. If you see "404" and HTTP 404, fix ENV and restart (see note above).
```

**9. Verify: transaction SETTLED, two $200 splits**

```bash
curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq .
curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq '{ status, amount_cents, splits: [.splits[] | { display_name, amount_cents, status }] }'
```

Expected: `status` `"SETTLED"`, `amount_cents` `40000`, two splits each `amount_cents` `20000` and `status` `"COMPLETED"`.

## 17. Receipt Session Flow (Itemized Splitting)

Receipt sessions let members claim specific line items before swiping, so each person is charged only for what they ordered.

### Setup

This section assumes you have completed steps 1–6 (user, group with two members, cards issued). You need `GROUP_ID`, `CREATOR_MEMBER_ID`, `MEMBER2_ID`, and `CARD_TOKEN` from those steps.

### Step 1 — Parse and Upload a Receipt

Use the existing receipt parser endpoint, then pass the parsed items to create a session:

```bash
# Parse receipt image (returns items array)
PARSE_RESP=$(curl -s -X POST $BASE/v1/receipts/parse \
  -H "Content-Type: application/json" \
  -d '{
    "image_base64": "<base64-encoded-receipt-image>"
  }')

echo $PARSE_RESP | jq .
```

Or skip parsing and POST a receipt manually with hardcoded items (e.g. a $100 dinner):

```bash
RECEIPT=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/receipts \
  -H "Content-Type: application/json" \
  -d '{
    "merchant_name": "The Steakhouse",
    "total_cents": 10000,
    "items": [
      { "name": "Ribeye",       "quantity": 1, "unit_price_cents": 5500 },
      { "name": "Salmon",       "quantity": 1, "unit_price_cents": 3200 },
      { "name": "Shared fries", "quantity": 1, "unit_price_cents": 1300 }
    ]
  }')

echo $RECEIPT | jq .
RECEIPT_ID=$(echo $RECEIPT | jq -r '.receipt_id')
```

Expected (201 Created):
```json
{
  "receipt_id": "<uuid>",
  "status": "draft"
}
```

### Step 2 — View Active Receipt

Any group member can poll for the current draft session including all items and existing assignments:

```bash
curl -s $BASE/v1/groups/$GROUP_ID/receipts/active | jq .
```

Expected:
```json
{
  "receipt_id": "<uuid>",
  "merchant_name": "The Steakhouse",
  "total_cents": 10000,
  "status": "draft",
  "items": [
    { "item_id": "<uuid>", "name": "Ribeye",       "total_cents": 5500, "assignments": [] },
    { "item_id": "<uuid>", "name": "Salmon",       "total_cents": 3200, "assignments": [] },
    { "item_id": "<uuid>", "name": "Shared fries", "total_cents": 1300, "assignments": [] }
  ]
}
```

Note the item IDs — you'll need them for assignments.

```bash
RIBEYE_ID=$(curl -s $BASE/v1/groups/$GROUP_ID/receipts/active | jq -r '.items[0].item_id')
SALMON_ID=$(curl -s $BASE/v1/groups/$GROUP_ID/receipts/active | jq -r '.items[1].item_id')
FRIES_ID=$(curl -s  $BASE/v1/groups/$GROUP_ID/receipts/active | jq -r '.items[2].item_id')
```

### Step 3 — Members Claim Their Items

Each member PUTs their full assignment list (replaces any previous assignments for that member):

```bash
# Creator claims the Ribeye ($55) and half the fries ($6.50 → 650 cents)
curl -s -X PUT $BASE/v1/groups/$GROUP_ID/receipts/$RECEIPT_ID/assignments \
  -H "Content-Type: application/json" \
  -d "{
    \"assignments\": [
      { \"item_id\": \"$RIBEYE_ID\", \"amount_cents\": 5500 },
      { \"item_id\": \"$FRIES_ID\",  \"amount_cents\": 650 }
    ]
  }" | jq .

# Member 2 claims the Salmon ($32) and the other half of fries ($6.50 → 650 cents)
# (In dev, both users share DEV_USER_ID — use psql to insert the second assignment directly)
curl -s -X PUT $BASE/v1/groups/$GROUP_ID/receipts/$RECEIPT_ID/assignments \
  -H "Content-Type: application/json" \
  -d "{
    \"assignments\": [
      { \"item_id\": \"$SALMON_ID\", \"amount_cents\": 3200 },
      { \"item_id\": \"$FRIES_ID\",  \"amount_cents\": 650 }
    ]
  }" | jq .
```

Expected (200 OK):
```json
{ "status": "ok" }
```

**Amount validation** — the server rejects amounts outside the floor/ceil for each item's proportional share. For example, claiming $0 for the Ribeye returns:
```json
{ "error": "amount_cents out of range for item", "min_allowed": 5500, "max_allowed": 5500, "got": 0 }
```

### Step 4 — Leader Finalizes the Receipt

Only the group leader can finalize (caller must have `is_leader = true`):

```bash
# Make the creator the leader first if not already
docker compose exec postgres psql -U tally -d tally -c \
  "UPDATE members SET is_leader = true WHERE id = '$CREATOR_MEMBER_ID';"

# Finalize
curl -s -X POST $BASE/v1/groups/$GROUP_ID/receipts/$RECEIPT_ID/finalize | jq .
```

Expected (200 OK):
```json
{ "status": "finalized" }
```

A non-leader gets 403:
```json
{ "error": "leader access required" }
```

### Step 5 — JIT with Receipt (card swipe)

Now trigger a JIT authorization. The handler will detect the finalized receipt and use item-based amounts:

```bash
WEBHOOK_SECRET="localtestingsecret"

BODY=$(cat <<EOF
{
  "idempotency_key": "txn-receipt-001",
  "card_token": "$CARD_TOKEN",
  "amount_cents": 10000,
  "currency": "usd",
  "merchant_name": "The Steakhouse",
  "merchant_category": "5812"
}
EOF
)

SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}')

curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $SIG" \
  -H "Idempotency-Key: txn-receipt-001" \
  -d "$BODY" | jq .
```

Expected (200 OK):
```json
{
  "decision": "APPROVE",
  "transaction_id": "<uuid>"
}
```

The receipt is now consumed. Confirm by checking `receipts.transaction_id`:

```bash
docker compose exec postgres psql -U tally -d tally -c \
  "SELECT id, status, transaction_id FROM receipts WHERE id = '$RECEIPT_ID';"
```

You should see `transaction_id` set to the transaction UUID.

### Step 6 — Cancel a Receipt (Optional)

Any member who created a receipt (or the leader) can cancel a draft before it is finalized:

```bash
curl -s -X DELETE $BASE/v1/groups/$GROUP_ID/receipts/$RECEIPT_ID | jq .
```

Expected (200 OK):
```json
{ "status": "deleted" }
```

Cancellation fails on a finalized or already-deleted receipt:
```json
{ "error": "receipt not found or already finalized" }
```

---

## 17. Real Stripe full flow (Customer + ACH settlement)

End-to-end test with **real Stripe**: SetupIntent uses a Stripe Customer (so the PaymentMethod can be charged at settlement). Run from **backend** directory with stack up (`docker compose up -d`), `STRIPE_SECRET_KEY` and `STRIPE_ISSUING_CARD_PRODUCT` set in `.env`. Use a **new** bank link (old `pm_xxx` from before the Customer change are not attached to a Customer and will fail at settlement).

**0. Env and helpers (run once, same shell for all steps)**

```bash
cd backend
BASE=http://localhost:8080
export WEBHOOK_SECRET=$(grep '^WEBHOOK_SECRET=' .env | cut -d= -f2)
sign_body() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'; }
```

**1. Create user**

```bash
curl -s -X POST $BASE/v1/users/me \
  -H "Content-Type: application/json" \
  -d '{"clerk_user_id":"dev-user-local","email":"test@example.com","first_name":"Test","last_name":"User"}' | jq .
```

**2. Create group**

```bash
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name": "dinner-test", "display_name": "Dinner Test"}')
echo "$GROUP" | jq .
GROUP_ID=$(echo "$GROUP" | jq -r '.group_id')
PAYER_MEMBER_ID=$(echo "$GROUP" | jq -r '.member_id')
```

**3. Add second member (50/50)**

```bash
docker compose exec -T postgres psql -U tally -d tally -c \
  "UPDATE members SET split_weight = 0.5 WHERE group_id = '$GROUP_ID' AND is_leader = true;"

MEMBER2=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Friend", "split_weight": 0.5, "user_id": "dev-user-2"}')
echo "$MEMBER2" | jq .
```

**4. Create SetupIntent (creates/uses Stripe Customer) and get client_secret**

```bash
SETI_RESP=$(curl -s -X POST $BASE/v1/users/me/payment-method -H "Content-Type: application/json")
echo "$SETI_RESP" | jq .
CLIENT_SECRET=$(echo "$SETI_RESP" | jq -r '.client_secret')
# Extract SetupIntent ID (part before _secret_)
SETI_ID="${CLIENT_SECRET%_secret_*}"
echo "SETI_ID=$SETI_ID"
```

**5. Confirm SetupIntent with Stripe (test ACH + mandate)**

```bash
STRIPE_KEY=$(grep '^STRIPE_SECRET_KEY=' .env | cut -d= -f2)
CONFIRM=$(curl -s "https://api.stripe.com/v1/setup_intents/$SETI_ID/confirm" \
  -u "${STRIPE_KEY}:" \
  -d payment_method=pm_usBankAccount_success \
  -d "mandate_data[customer_acceptance][type]=online" \
  -d "mandate_data[customer_acceptance][online][ip_address]=127.0.0.1" \
  -d "mandate_data[customer_acceptance][online][user_agent]=curl")
echo "$CONFIRM" | jq .
PM_ID=$(echo "$CONFIRM" | jq -r '.payment_method')
echo "PM_ID=$PM_ID"
```

If `PM_ID` is null, the confirm failed; check the response for `error.message`.

**6. Confirm payment method for payer and set KYC + ACH for both members**

```bash
curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$PAYER_MEMBER_ID\", \"payment_method_id\": \"$PM_ID\"}" | jq .

docker compose exec -T postgres psql -U tally -d tally -c "
  UPDATE members
  SET kyc_status = 'approved',
      stripe_payment_method_id = '$PM_ID',
      stripe_backup_payment_method_id = '$PM_ID'
  WHERE group_id = '$GROUP_ID';"
```

**7. Issue card**

```bash
CARD=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$PAYER_MEMBER_ID\", \"first_name\": \"Test\", \"last_name\": \"User\", \"email\": \"test@example.com\", \"dob\": {\"day\": 15, \"month\": 1, \"year\": 1990}, \"user_terms_accepted_at\": $(date +%s)}")
echo "$CARD" | jq .
CARD_TOKEN=$(echo "$CARD" | jq -r '.card_token')
```

If you get "card issuer unavailable", check `docker compose logs app` for Stripe errors; you may need to fix cardholder requirements in Stripe Dashboard and retry (or use a new group so a new cardholder is created after fixing program requirements). For Celtic programs, `user_terms_accepted_at` (Unix timestamp when user accepted terms) is required.

**8. JIT (authorize $400)**

```bash
IDEM_KEY="dinner-400-$(date +%s)"
BODY="{\"idempotency_key\":\"$IDEM_KEY\",\"card_token\":\"$CARD_TOKEN\",\"amount_cents\":40000,\"currency\":\"usd\",\"merchant_name\":\"Dinner Spot\",\"merchant_category\":\"5812\"}"
SIG=$(sign_body "$BODY")
JIT=$(curl -s -X POST $BASE/v1/auth/jit \
  -H "Content-Type: application/json" \
  -H "X-Tally-Signature: $SIG" \
  -H "Idempotency-Key: $IDEM_KEY" \
  -d "$BODY")
echo "$JIT" | jq .
TXN_ID=$(echo "$JIT" | jq -r '.transaction_id')
```

**9. Settle and verify**

```bash
curl -s -w "\nHTTP %{http_code}" -X POST "$BASE/v1/dev/settle/$TXN_ID"
curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq '{ status, amount_cents, splits: [.splits[] | { display_name, amount_cents, status }] }'
```

Expected: `status` `"SETTLED"`, two splits each `20000` and `status` `"COMPLETED"`. In Stripe Dashboard → Payments you should see two ACH charges of $200.

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
| `POST /v1/groups/:id/receipts/:id/finalize` caller not leader | 403 | `leader access required` |
| `DELETE /v1/groups/:id/receipts/:id` caller is non-leader non-creator | 403 | `not authorized to cancel this receipt` |
| `PUT /v1/groups/:id/receipts/:id/assignments` amount out of floor/ceil range | 400 | `amount_cents out of range for item` |
| `POST /v1/groups/:id/receipts` when a draft already exists | 200 | Existing draft auto-cancelled; new session created |
| JIT swipe when receipt finalized but all assignments are 0 | APPROVE | Falls back to `split_weight` allocation |
| JIT swipe with no finalized receipt | APPROVE | Standard `split_weight` allocation |

---

## Swagger UI

Interactive API documentation with all endpoints and schemas:

```
http://localhost:8080/swagger/index.html
```

