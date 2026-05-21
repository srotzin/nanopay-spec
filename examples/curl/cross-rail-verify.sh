#!/usr/bin/env bash
# cross-rail-verify.sh — Issue a receipt then verify it against the cross-rail verify endpoint.
# The verify endpoint checks: canonical hash match, envelope presence, rail membership.

RECEIPT=$(curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail \
  -H "Content-Type: application/json" \
  -d '{"rails":["base-usdc","solana-usdc"],"amount_usd":0.0003}')

echo "--- Receipt issued ---"
echo "$RECEIPT" | jq

echo ""
echo "--- Verification result ---"
echo "$RECEIPT" | curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail/verify \
  -H "Content-Type: application/json" \
  -d @- | jq
