#!/usr/bin/env bash
# Forward Stripe Identity webhooks to local backend for KYC testing.
# Requires: Stripe CLI installed (brew install stripe/stripe-cli/stripe) and logged in (stripe login).
#
# Usage:
#   1. Start your backend: docker compose up (or go run .)
#   2. Run this script: ./scripts/stripe_listen_identity.sh
#   3. Copy the "whsec_..." signing secret from the script output into .env as STRIPE_WEBHOOK_SECRET
#   4. Restart the backend so it picks up the new secret
#   5. Trigger KYC from the app; complete verification in the browser; webhook will hit localhost

set -e
cd "$(dirname "$0")/.."
PORT="${PORT:-8080}"
echo "Forwarding Stripe Identity events to http://localhost:${PORT}/v1/webhooks/stripe/identity"
echo "Add the signing secret (whsec_...) printed below to .env as STRIPE_WEBHOOK_SECRET, then restart the backend."
echo ""
stripe listen --forward-to "localhost:${PORT}/v1/webhooks/stripe/identity" \
  --events identity.verification_session.verified,identity.verification_session.requires_input
