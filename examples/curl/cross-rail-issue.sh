#!/usr/bin/env bash
# cross-rail-issue.sh — Issue a cross-rail PQ nanopay receipt across Base USDC and Solana USDC.
# The returned receipt is a full Tier 1 (PQ) envelope: Ed25519 + ML-DSA-65 + SLH-DSA.

curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail \
  -H "Content-Type: application/json" \
  -d '{
    "rails": ["base-usdc", "solana-usdc"],
    "amount_usd": 0.0003
  }' | jq
