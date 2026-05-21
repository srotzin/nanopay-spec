#!/usr/bin/env bash
# lite-tier.sh — Send X-Hive-Nanopay-Tier: lite header to trigger lite-tier 402 negotiation.
# Expected: HTTP 402 with Payment-Required response indicating lite-tier floor ($0.000001).

curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -H "X-Hive-Nanopay-Tier: lite" \
  https://hivemorph.onrender.com/v1/evaluator/economics

# To see full response headers and body:
curl -si \
  -H "X-Hive-Nanopay-Tier: lite" \
  https://hivemorph.onrender.com/v1/evaluator/economics
