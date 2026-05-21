# nanopay-spec

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Spec: v1](https://img.shields.io/badge/spec-v1-blue.svg)](./nanopay-v1.md)
[![x402: extension](https://img.shields.io/badge/x402-extension-green.svg)](https://github.com/x402-foundation/x402)

Hive Nanopay is a two-tier post-quantum nanopayment standard for agentic commerce. It defines a signed receipt envelope, a tiered pricing model, and an HTTP surface compatible with the x402 payment protocol.

## Specification

[nanopay-v1.md](./nanopay-v1.md) — the full v1.0.0 specification.

Sections: Abstract, Motivation, Terminology, Pricing Model, PQ Receipt Envelope, Lite Receipt Envelope, Cross-Rail Receipts, HTTP Surface, Compliance Mapping, Security Considerations, x402 Compatibility, Reference Implementation.

## Tiers

| Tier | Floor | Envelope | Opt-In |
|------|-------|----------|--------|
| pq (default) | $0.0003 | Ed25519 + ML-DSA-65 + SLH-DSA | (absent) |
| lite | $0.000001 | EIP-3009 + Ed25519 + Merkle batch root | `X-Hive-Nanopay-Tier: lite` |

## x402 Extension PR

[x402-foundation/x402 PR #2401 — Hive Nanopay extension](https://github.com/x402-foundation/x402/pull/2401)

The extension doc proposes Hive Nanopay as an officially recognized x402 extension. PR is filed as draft per CONTRIBUTING.md AI-assisted rules.

## Reference Implementation

Live at: https://hivemorph.onrender.com

Key endpoints:

- `GET /v1/nanopay/bench` — live counters, tier table, rails, PQ coverage
- `POST /v1/nanopay/cross-rail` — issue a cross-rail PQ receipt
- `POST /v1/nanopay/cross-rail/verify` — verify a receipt
- `GET /v1/nanopay/standard` — spec metadata JSON

4,120+ receipts shipped. 5 active rails (Base USDC/USDT, Solana USDC/USDT, Ethereum USDT). 100% PQ coverage.

## Curl Quick-Start

```bash
# Bench
curl -s https://hivemorph.onrender.com/v1/nanopay/bench | jq

# Issue cross-rail receipt
curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail \
  -H "Content-Type: application/json" \
  -d '{"rails":["base-usdc","solana-usdc"],"amount_usd":0.0003}' | jq

# Spec metadata
curl -s https://hivemorph.onrender.com/v1/nanopay/standard | jq
```

See [examples/curl/](./examples/curl/) for full curl scripts.

## License

MIT — Copyright (c) 2026 Steve Rotzin / HiveryIQ
