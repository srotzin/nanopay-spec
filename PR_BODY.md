Adds a new extension doc proposing Hive Nanopay as an x402-compatible nanopayment extension.

- PQ envelope: Ed25519 + ML-DSA-65 (FIPS 204) + SLH-DSA-PURE-SHAKE-256F (FIPS 205) under all-of-three EUF-CMA combiner, $0.0003 floor
- Lite tier: EIP-3009 + Ed25519 + Merkle batch root, $0.000001 floor, opt-in via X-Hive-Nanopay-Tier: lite header
- Cross-rail receipts: single x402-compatible envelope verifiable across Base, Solana, and Ethereum

Reference impl live at hivemorph.onrender.com. Full spec at github.com/srotzin/nanopay-spec. PR is draft per CONTRIBUTING.md AI-assisted rules — will mark ready after maintainer review of doc scope.
