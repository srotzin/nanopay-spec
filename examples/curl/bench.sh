#!/usr/bin/env bash
# bench.sh — Fetch live counters, tier table, and rail list from Hive Nanopay bench endpoint.
# No authentication required.

curl -s https://hivemorph.onrender.com/v1/nanopay/bench | jq
