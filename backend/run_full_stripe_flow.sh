#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
BASE=http://localhost:8080
export WEBHOOK_SECRET=$(grep '^WEBHOOK_SECRET=' .env | cut -d= -f2)
sign_body() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print "sha256="$2}'; }

echo "=== 1. Create user ==="
curl -s -X POST $BASE/v1/users/me \
  -H "Content-Type: application/json" \
  -d '{"clerk_user_id":"dev-user-local","email":"test@example.com","first_name":"Test","last_name":"User"}' | jq .

echo "=== 2. Create group ==="
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Content-Type: application/json" \
  -d '{"name": "dinner-test-'$(date +%s)'", "display_name": "Dinner Test"}')
echo "$GROUP" | jq .
GROUP_ID=$(echo "$GROUP" | jq -r '.group_id')
PAYER_MEMBER_ID=$(echo "$GROUP" | jq -r '.member_id')
echo "GROUP_ID=$GROUP_ID PAYER_MEMBER_ID=$PAYER_MEMBER_ID"

echo "=== 3. Add second member (50/50) ==="
docker compose exec -T postgres psql -U tally -d tally -c \
  "UPDATE members SET split_weight = 0.5 WHERE group_id = '$GROUP_ID' AND is_leader = true;"
MEMBER2=$(curl -s -X POST $BASE/v1/groups/$GROUP_ID/members \
  -H "Content-Type: application/json" \
  -d '{"display_name": "Friend", "split_weight": 0.5, "user_id": "dev-user-2"}')
echo "$MEMBER2" | jq .
MEMBER2_ID=$(echo "$MEMBER2" | jq -r '.member_id')
echo "MEMBER2_ID=$MEMBER2_ID"

echo "=== 4. Create SetupIntent (payer) ==="
SETI_RESP=$(curl -s -X POST $BASE/v1/users/me/payment-method -H "Content-Type: application/json")
echo "$SETI_RESP" | jq .
CLIENT_SECRET=$(echo "$SETI_RESP" | jq -r '.client_secret')
SETI_ID="${CLIENT_SECRET%_secret_*}"
if [ -z "$SETI_ID" ] || [ "$SETI_ID" = "null" ]; then echo "ERROR: no client_secret"; exit 1; fi
echo "SETI_ID=$SETI_ID"

echo "=== 5. Confirm SetupIntent with Stripe ==="
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

echo "=== 5b. Second user (Friend): create Customer + SetupIntent + confirm (Stripe API) ==="
docker compose exec -T postgres psql -U tally -d tally -c \
  "INSERT INTO users (id) VALUES ('dev-user-2') ON CONFLICT (id) DO NOTHING;"
CUST2=$(curl -s "https://api.stripe.com/v1/customers" -u "${STRIPE_KEY}:" \
  -d "metadata[tally_user_id]=dev-user-2")
CUST2_ID=$(echo "$CUST2" | jq -r '.id')
if [ -z "$CUST2_ID" ] || [ "$CUST2_ID" = "null" ]; then echo "ERROR: create customer 2 failed"; echo "$CUST2" | jq .; exit 1; fi
echo "CUST2_ID=$CUST2_ID"
SETI2=$(curl -s "https://api.stripe.com/v1/setup_intents" -u "${STRIPE_KEY}:" \
  -d customer="$CUST2_ID" \
  -d "payment_method_types[]=us_bank_account" \
  -d usage=off_session)
SETI2_ID=$(echo "$SETI2" | jq -r '.id')
CONFIRM2=$(curl -s "https://api.stripe.com/v1/setup_intents/$SETI2_ID/confirm" -u "${STRIPE_KEY}:" \
  -d payment_method=pm_usBankAccount_success \
  -d "mandate_data[customer_acceptance][type]=online" \
  -d "mandate_data[customer_acceptance][online][ip_address]=127.0.0.1" \
  -d "mandate_data[customer_acceptance][online][user_agent]=curl")
PM_ID_2=$(echo "$CONFIRM2" | jq -r '.payment_method')
if [ -z "$PM_ID_2" ] || [ "$PM_ID_2" = "null" ]; then echo "ERROR: confirm setup 2 failed"; echo "$CONFIRM2" | jq .; exit 1; fi
echo "PM_ID_2=$PM_ID_2"
docker compose exec -T postgres psql -U tally -d tally -c \
  "UPDATE users SET stripe_customer_id = '$CUST2_ID', updated_at = NOW() WHERE id = 'dev-user-2';"

echo "=== 6. Confirm payment method (payer) + set KYC/ACH for both members ==="
curl -s -X POST $BASE/v1/users/me/payment-method/confirm \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$PAYER_MEMBER_ID\", \"payment_method_id\": \"$PM_ID\"}" | jq .
docker compose exec -T postgres psql -U tally -d tally -c "
  UPDATE members SET kyc_status = 'approved',
    stripe_payment_method_id = '$PM_ID',
    stripe_backup_payment_method_id = '$PM_ID'
  WHERE id = '$PAYER_MEMBER_ID';
  UPDATE members SET kyc_status = 'approved',
    stripe_payment_method_id = '$PM_ID_2',
    stripe_backup_payment_method_id = '$PM_ID_2'
  WHERE id = '$MEMBER2_ID';"

echo "=== 7. Issue card ==="
# DOB required; user_terms_accepted_at required for Celtic programs (Unix timestamp when user accepted terms).
USER_TERMS_AT=$(date +%s)
CARD=$(curl -s -X POST $BASE/v1/cards/issue \
  -H "Content-Type: application/json" \
  -d "{\"member_id\": \"$PAYER_MEMBER_ID\", \"first_name\": \"Test\", \"last_name\": \"User\", \"email\": \"test@example.com\", \"dob\": {\"day\": 15, \"month\": 1, \"year\": 1990}, \"user_terms_accepted_at\": $USER_TERMS_AT}")
echo "$CARD" | jq .
CARD_TOKEN=$(echo "$CARD" | jq -r '.card_token')
if [ -z "$CARD_TOKEN" ] || [ "$CARD_TOKEN" = "null" ]; then echo "ERROR: no card_token"; exit 1; fi

echo "=== 8. JIT (authorize \$400) ==="
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
echo "TXN_ID=$TXN_ID"

echo "=== 9. Settle and verify ==="
curl -s -w "\nHTTP %{http_code}\n" -X POST "$BASE/v1/dev/settle/$TXN_ID"
echo "--- Transaction ---"
curl -s $BASE/v1/groups/$GROUP_ID/transactions/$TXN_ID | jq '{ status, amount_cents, splits: [.splits[] | { display_name, amount_cents, status }] }'
echo "=== Done ==="
