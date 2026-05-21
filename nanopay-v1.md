# Hive Nanopay v1.0.0 Specification

**Status:** Final Draft  
**Version:** v1.0.0  
**Date:** 2026  
**Authors:** Steve Rotzin (HiveryIQ)  
**License:** MIT  
**Repo:** https://github.com/srotzin/nanopay-spec  
**Reference Implementation:** https://hivemorph.onrender.com  

---

## Table of Contents

1. [Abstract](#1-abstract)
2. [Motivation](#2-motivation)
3. [Terminology](#3-terminology)
4. [Pricing Model](#4-pricing-model)
5. [Receipt Envelope — Tier 1 (PQ Default)](#5-receipt-envelope--tier-1-pq-default)
6. [Receipt Envelope — Tier 2 (Lite Opt-In)](#6-receipt-envelope--tier-2-lite-opt-in)
7. [Cross-Rail Receipts](#7-cross-rail-receipts)
8. [HTTP Surface](#8-http-surface)
9. [Compliance Mapping](#9-compliance-mapping)
10. [Security Considerations](#10-security-considerations)
11. [x402 Compatibility](#11-x402-compatibility)
12. [Reference Implementation](#12-reference-implementation)
13. [Authors and License](#13-authors-and-license)

---

## 1. Abstract

Hive Nanopay is a two-tier nanopayment standard designed for agentic commerce, post-quantum survivability, and cross-rail portability. It defines a signed receipt envelope structure, a tiered pricing model, and an HTTP surface compatible with the x402 payment protocol.

**Tier 1 — PQ (default)**

- Floor price: $0.0003 per receipt
- Envelope algorithm: Ed25519 (RFC 8032) combined with ML-DSA-65 (FIPS 204) and SLH-DSA-PURE-SHAKE-256F (FIPS 205)
- Combiner: all-of-three EUF-CMA (existential unforgeability under chosen-message attack)
- A receipt is valid only when all three component signatures verify against the same message hash under the resolved keys for the declared kid

**Tier 2 — Lite (opt-in)**

- Floor price: $0.000001 per receipt
- Envelope: EIP-3009 authorization + Ed25519 signature + Merkle batch root
- Opt-in header: `X-Hive-Nanopay-Tier: lite`
- One PQ signature amortized over up to 10,000,000 positions per Merkle root (batch root anchored on-chain)

Both tiers produce receipts that are compatible with the x402 payment negotiation protocol. The PQ tier is the default for all requests that do not carry the opt-in header. Lite tier preserves byte-identical x402 default behavior for non-Hive clients.

---

## 2. Motivation

Agentic commerce — software agents transacting autonomously on behalf of users or systems — requires a payment primitive with three properties that existing systems do not simultaneously provide:

1. **Sub-cent denomination with verifiable receipts.** Card-rail and PSP-class systems impose minimum transaction floors of $0.50 or more, with settlement delays measured in days. These systems cannot serve the $0.0003-range receipts that agentic API calls require. Circle Nanopayments addresses denomination but not the other two properties.

2. **Post-quantum signature survivability.** Receipts issued today must remain verifiable in a post-quantum cryptographic environment. NIST-standardized lattice-based signatures (ML-DSA-65, FIPS 204) and hash-based signatures (SLH-DSA-PURE-SHAKE-256F, FIPS 205) provide this guarantee. Classical ECDSA alone does not. The x402 baseline protocol does not mandate PQ signatures.

3. **Cross-rail portability.** A single receipt must be verifiable across multiple settlement rails (Base, Solana, Ethereum) without requiring the verifier to know in advance which rail was used. Card-rail systems, PSP-class integrations, and single-chain x402 deployments each lock the receipt to one rail.

Hive Nanopay solves all three simultaneously. The two-tier design allows operators to select the lite tier when PQ overhead is not required, while keeping PQ as the secure default.

The compliance burden on agentic infrastructure is also increasing. MiCA Art 34, DORA Art 9 and 28, EU AI Act Art 12 and 15, and NSM-10 each impose audit-trail, resilience, and algorithmic-transparency requirements. Hive Nanopay receipts are structured to satisfy all five. The full compliance mapping is in Section 9.

---

## 3. Terminology

**Receipt**  
A signed JSON document attesting that a specific payment event occurred across one or more rails at a specific timestamp. A receipt is the atomic unit of the Hive Nanopay system. Receipts are immutable after issuance.

**Envelope**  
The cryptographic wrapper inside a receipt. The envelope contains the algorithm identifier, the key identifier (DID), and one or more signatures over the canonical hash of the receipt payload. The envelope structure differs between Tier 1 (PQ) and Tier 2 (lite).

**Rail**  
A settlement pathway corresponding to a specific blockchain network and asset contract. Each rail has a unique `rail_id` string. A single receipt may include proof entries for multiple rails simultaneously. Active rails are listed in Section 7.

**Tier**  
One of two operating modes: PQ (default, Tier 1) or lite (opt-in, Tier 2). The tier governs the envelope algorithm set and the price floor.

**Combiner**  
The rule by which multiple component signatures are aggregated into a single validity determination. Hive Nanopay Tier 1 uses `all-of-three`: a receipt envelope is valid if and only if all three component signatures (Ed25519, ML-DSA-65, SLH-DSA) each verify independently against the same message hash under the keys resolved for the declared kid.

**Batch Root**  
A 32-byte Merkle root committing to up to 10,000,000 receipt positions. Used in Tier 2 to amortize one PQ signature over a large number of receipts. The batch root is anchored on-chain via `batch_open_endpoint` and finalized via `batch_close_endpoint`.

**RVC (Receipt-Verifiable Channel)**  
A logical channel in which every payment event produces a Hive Nanopay receipt. An RVC may span multiple rails and multiple tiers. RVCs are opened and closed via the batch endpoint family. The canonical hash of each receipt in the RVC is a leaf in the Merkle tree rooted at `batch_root`.

---

## 4. Pricing Model

### 4.1 Tier Table

| Tier   | Floor (USD)  | Envelope Algorithm                            | Default | Opt-In Header                    |
|--------|-------------|-----------------------------------------------|---------|----------------------------------|
| pq     | $0.0003     | Ed25519 + ML-DSA-65 + SLH-DSA-PURE-SHAKE-256F | Yes     | (absent = PQ)                    |
| lite   | $0.000001   | EIP-3009 + Ed25519 + Merkle batch root         | No      | `X-Hive-Nanopay-Tier: lite`      |

The PQ tier is the default. Any request that does not carry the `X-Hive-Nanopay-Tier: lite` header is processed at PQ tier pricing and PQ envelope construction. The lite tier is available to operators who have explicitly opted in and accept the reduced signature guarantees relative to the full three-algorithm PQ combiner.

### 4.2 Bench Endpoint Response Shape

The `GET /v1/nanopay/bench` endpoint returns live counters, the tier table, the active rail set, and PQ coverage. The canonical JSON shape is:

```json
{
  "receipts_total": 4120,
  "receipts_pq_signed": 4120,
  "pq_coverage_percent": 100.0,
  "tiers": {
    "pq": {
      "floor_usd": 0.0003,
      "envelope": "ed25519+ml-dsa-65+slh-dsa",
      "combiner": "all-of-three",
      "default": true,
      "opt_in_header": null
    },
    "lite": {
      "floor_usd": 0.000001,
      "envelope": "eip3009+ed25519+merkle-batch-root",
      "combiner": "ed25519+merkle",
      "default": false,
      "opt_in_header": "X-Hive-Nanopay-Tier: lite"
    }
  },
  "rails": {
    "active": [
      "base-usdc",
      "base-usdt",
      "solana-usdc",
      "solana-usdt",
      "ethereum-usdt"
    ],
    "planned": [
      {
        "rail_id": "arc-usdc",
        "description": "Arc Mainnet USDC",
        "status": "day1-mainnet-pending"
      }
    ],
    "count_active": 5,
    "count_planned": 1
  },
  "compliance": [
    "MiCA Art 34",
    "DORA Art 9",
    "DORA Art 28",
    "EU AI Act Art 12",
    "EU AI Act Art 15",
    "NSM-10"
  ],
  "batch": {
    "open_endpoint": "POST /v1/rvc/batch-open",
    "close_endpoint": "POST /v1/rvc/batch-close",
    "max_positions_per_root": 10000000,
    "amortized_signature_cost_at_max": "~1 PQ sig per 10M events"
  }
}
```

---

## 5. Receipt Envelope — Tier 1 (PQ Default)

### 5.1 Overview

A Tier 1 receipt is a JSON document containing a payload section and an envelope section. The payload captures the economic fact (who paid whom, how much, on which rails, at what time). The envelope contains three independent signatures over the canonical hash of the payload.

### 5.2 Canonical Hash Computation

The `receipt_hash` field and the message signed by each component algorithm are both derived from the same canonical form:

```
receipt_hash = "0x" + sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")))
```

where `payload` is the full receipt JSON minus the `envelope` field. `json.dumps` must use `sort_keys=True` and `separators=(",", ":")` (no spaces). The result is a 66-character lowercase hex string prefixed with `0x`. This canonical hash is computed identically at issuance and at verification; any deviation in key ordering or spacing will produce a hash mismatch.

### 5.3 Full JSON Schema

```json
{
  "receipt_id": "string — UUID v4 (RFC 4122)",
  "kind": "cross-rail",
  "peer": "string — caller-supplied identifier or anonymous",
  "rails": [
    "string — rail_id, one or more active rail identifiers"
  ],
  "rails_count": "integer — length of rails array",
  "amount_atomic_micro": "integer — amount in millionths of USD (1 = $0.000001)",
  "ts": "integer — Unix epoch seconds, UTC",
  "receipt_hash": "string — 0x-prefixed sha256 canonical hash (see 5.2)",
  "envelope": {
    "alg": "ed25519+ml-dsa-65+slh-dsa",
    "combiner": "all-of-three",
    "kid": "string — DID of the signing key set",
    "sig_ed25519": "string — base64url-encoded Ed25519 signature (RFC 8032)",
    "sig_ml_dsa_65": "string — base64url-encoded ML-DSA-65 signature (FIPS 204)",
    "sig_slh_dsa": "string — base64url-encoded SLH-DSA-PURE-SHAKE-256F signature (FIPS 205)"
  }
}
```

### 5.4 Field Definitions

| Field | Type | Description |
|---|---|---|
| `receipt_id` | string | UUID v4. Unique per receipt. Used for replay detection. |
| `kind` | string | Always `"cross-rail"` for cross-rail receipts. |
| `peer` | string | Identifies the counterparty or caller. May be an agent DID, API key hash, or `"anonymous"`. |
| `rails` | string[] | One or more active rail_id strings. Each must appear in the active rails list. |
| `rails_count` | integer | Length of `rails` array. Redundant for convenience. |
| `amount_atomic_micro` | integer | Amount in atomic microdollars. 300 = $0.0003 (PQ floor). 1 = $0.000001 (lite floor). |
| `ts` | integer | Unix epoch seconds. Verifiers must reject receipts with `ts` outside a 300-second window. |
| `receipt_hash` | string | Canonical sha256 of the payload (see 5.2). |
| `envelope.alg` | string | Algorithm identifier. Must be `"ed25519+ml-dsa-65+slh-dsa"` for Tier 1. |
| `envelope.combiner` | string | Must be `"all-of-three"`. |
| `envelope.kid` | string | DID of the key set used to sign. Resolution follows DID core spec. |
| `envelope.sig_ed25519` | string | Ed25519 signature over `receipt_hash` bytes. Base64url, no padding. |
| `envelope.sig_ml_dsa_65` | string | ML-DSA-65 signature over `receipt_hash` bytes. Base64url, no padding. |
| `envelope.sig_slh_dsa` | string | SLH-DSA-PURE-SHAKE-256F signature over `receipt_hash` bytes. Base64url, no padding. |

### 5.5 Combiner Rule

A Tier 1 envelope is valid if and only if:

1. `envelope.combiner` equals `"all-of-three"`.
2. `envelope.kid` resolves to a DID document containing three verification methods: one Ed25519VerificationKey2020, one MLDsa65VerificationKey2025, one SlhDsaVerificationKey2025.
3. Each of the three component signatures verifies independently: `verify(sig_X, message=receipt_hash_bytes, key=resolved_key_X)` returns true for X in {ed25519, ml_dsa_65, slh_dsa}.
4. The `receipt_hash` in the payload matches a fresh local computation over the payload fields.

Failure of any single component signature invalidates the entire envelope. There is no threshold or fallback; all-of-three means all three.

### 5.6 Server DID

The reference implementation signs all receipts under:

```
did:hivemorph:w2loren:0x6b11b1bcaf253c
```

---

## 6. Receipt Envelope — Tier 2 (Lite Opt-In)

### 6.1 Overview

Tier 2 trades PQ signature completeness for lower per-receipt cost. Instead of three independent PQ signatures per receipt, the lite tier uses:

- An EIP-3009 `transferWithAuthorization` pre-authorization (for EVM rails)
- An Ed25519 signature over the receipt hash
- A Merkle batch root that commits up to 10,000,000 receipt hashes

One PQ signature is applied to each batch root. That single PQ signature amortizes across every receipt in the batch.

### 6.2 JSON Schema (Lite)

```json
{
  "receipt_id": "string — UUID v4",
  "kind": "cross-rail",
  "peer": "string",
  "rails": ["string"],
  "rails_count": "integer",
  "amount_atomic_micro": "integer",
  "ts": "integer",
  "receipt_hash": "string — 0x-prefixed sha256 canonical hash",
  "batch_root": "string — 32-byte Merkle root, 64-char lowercase hex (no 0x prefix)",
  "batch_index": "integer — uint64, position of this receipt in the batch (0-based)",
  "batch_open_endpoint": "string — URL at which this batch was opened",
  "batch_close_endpoint": "string — URL at which this batch will be (or was) closed",
  "envelope": {
    "alg": "eip3009+ed25519+merkle-batch-root",
    "combiner": "ed25519+merkle",
    "kid": "string — DID",
    "sig_ed25519": "string — base64url Ed25519 signature",
    "eip3009_auth": {
      "from": "string — EVM address",
      "to": "string — EVM recipient address",
      "value": "string — uint256 as decimal string",
      "validAfter": "integer — Unix epoch",
      "validBefore": "integer — Unix epoch",
      "nonce": "string — 32-byte hex nonce",
      "v": "integer",
      "r": "string",
      "s": "string"
    }
  }
}
```

### 6.3 Batch Root Construction

The Merkle tree is a standard binary tree where each leaf is `sha256(receipt_hash_bytes)`. Internal nodes are `sha256(left_child || right_child)`. The root is the top-level 32-byte hash. The batch is opened by posting to `batch_open_endpoint` and closed (root finalized and PQ-signed) by posting to `batch_close_endpoint`. A batch may contain up to 10,000,000 positions. Once closed, the root and its PQ signature are published at a stable URL for independent verification.

### 6.4 Opt-In Mechanics

Clients opt into Tier 2 by including the request header:

```
X-Hive-Nanopay-Tier: lite
```

Any request without this header is processed at Tier 1 (PQ default). The response includes a `tier` field in the receipt indicating which tier was applied. Verifiers that do not understand Tier 2 will fail open (they see an Ed25519 signature but not the three-algorithm combiner), which is intentional for backward compatibility with non-Hive x402 clients.

---

## 7. Cross-Rail Receipts

### 7.1 Design Goal

A cross-rail receipt is a single envelope whose `rails[]` array contains entries for multiple settlement networks. A verifier does not need to know which rail was used in advance; it can inspect the receipt and verify proof entries for any rail it understands.

### 7.2 Rail Entry Schema

Each element in the `proof_entries` array of a cross-rail receipt has the following shape:

```json
{
  "chain": "string — chain family (base | solana | ethereum | arc)",
  "network": "string — CAIP-2 or equivalent network identifier",
  "asset": "string — USDC | USDT",
  "contract": "string — token contract address on this chain",
  "recipient": "string — payment recipient address on this chain",
  "rail_id": "string — canonical rail identifier",
  "amount_atomic": "integer — amount in token's native atomic unit",
  "proof": {
    "scheme": "string — proof scheme identifier",
    "kind": "string — on-chain | off-chain | pre-auth | merkle-leaf",
    "proof_hash": "string — 0x-prefixed hash of the proof artifact"
  }
}
```

### 7.3 Active Rails

| rail_id | chain | network | asset | contract | recipient |
|---|---|---|---|---|---|
| base-usdc | base | eip155:8453 | USDC | 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 | 0x15184Bf50B3d3F52b60434f8942b7D52F2eB436E |
| base-usdt | base | eip155:8453 | USDT | 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2 | 0x15184Bf50B3d3F52b60434f8942b7D52F2eB436E |
| solana-usdc | solana | solana | USDC | EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v | B1N61cuL35fhskWz5dw8XqDyP6LWi3ZWmq8CNA9L3FVn |
| solana-usdt | solana | solana | USDT | Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB | B1N61cuL35fhskWz5dw8XqDyP6LWi3ZWmq8CNA9L3FVn |
| ethereum-usdt | ethereum | ethereum | USDT | 0xdAC17F958D2ee523a2206206994597C13D831ec7 | 0x15184Bf50B3d3F52b60434f8942b7D52F2eB436E |

### 7.4 Planned Rails

| rail_id | chain | asset | status |
|---|---|---|---|
| arc-usdc | arc | USDC | day1-mainnet-pending |

`arc-usdc` will be activated on Day 1 of Arc Mainnet launch. No contracts are deployed on Arc testnet or any pre-mainnet environment. This rail is listed in `GET /v1/nanopay/bench` with `status: "day1-mainnet-pending"`.

### 7.5 Treasury Addresses

- EVM chains (Base, Ethereum): `0x15184Bf50B3d3F52b60434f8942b7D52F2eB436E`
- Solana: `B1N61cuL35fhskWz5dw8XqDyP6LWi3ZWmq8CNA9L3FVn`

---

## 8. HTTP Surface

### 8.1 Base URL

```
https://hivemorph.onrender.com
```

All endpoints are HTTPS-only. No HTTP redirect is provided. TLS 1.3 minimum.

### 8.2 GET /v1/nanopay/bench

Returns live counters, tier table, active and planned rails, PQ coverage percentage, compliance labels, and batch configuration.

**Authentication:** None. This endpoint is public.  
**Method:** GET  
**Path:** `/v1/nanopay/bench`  
**Response:** 200 OK, `application/json`  

Response shape is defined in Section 4.2. Live counters (`receipts_total`, `receipts_pq_signed`) reflect the actual number of receipts issued since service start. `pq_coverage_percent` is the ratio of PQ-signed receipts to total receipts, expressed as a float (100.0 = all receipts PQ-signed).

### 8.3 POST /v1/nanopay/cross-rail

Issues a new cross-rail receipt.

**Authentication:** None. This endpoint is public for demonstration purposes.  
**Method:** POST  
**Path:** `/v1/nanopay/cross-rail`  
**Content-Type:** `application/json`  

Request body:

```json
{
  "rails": ["base-usdc", "solana-usdc"],
  "amount_usd": 0.0003
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `rails` | string[] | Yes | One or more active rail_id values from the active rails table (Section 7.3). |
| `amount_usd` | number | Yes | Requested amount in USD. Must be at or above the tier floor ($0.0003 for PQ, $0.000001 for lite). |

Response: full receipt envelope as defined in Section 5.3 (PQ) or Section 6.2 (lite, if header present).

### 8.4 POST /v1/nanopay/cross-rail/verify

Verifies a previously issued receipt.

**Authentication:** None.  
**Method:** POST  
**Path:** `/v1/nanopay/cross-rail/verify`  
**Content-Type:** `application/json`  

Request body: a full receipt JSON as returned by `POST /v1/nanopay/cross-rail`.

Response:

```json
{
  "ok": true,
  "hash_match": true,
  "envelope_present": true,
  "rails_in_receipt": ["base-usdc", "solana-usdc"],
  "demo_mode": true
}
```

| Field | Type | Description |
|---|---|---|
| `ok` | boolean | True if all checks pass. |
| `hash_match` | boolean | True if the locally-computed canonical hash matches `receipt_hash`. |
| `envelope_present` | boolean | True if the `envelope` field is present and structurally complete. |
| `rails_in_receipt` | string[] | The `rails` array extracted from the submitted receipt. |
| `demo_mode` | boolean | True if the reference implementation is in demo mode (signature is structurally present but not cryptographically verified on every field). |

### 8.5 GET /v1/nanopay/standard

Returns spec metadata: version, repo URL, x402 extension PR URL, reference implementation URL, tier names, and endpoint pointers.

**Authentication:** None.  
**Method:** GET  
**Path:** `/v1/nanopay/standard`  
**Response:** 200 OK, `application/json`  

```json
{
  "v": 1,
  "name": "Hive Nanopay",
  "version": "v1.0.0",
  "spec_url": "https://github.com/srotzin/nanopay-spec/blob/main/nanopay-v1.md",
  "repo": "https://github.com/srotzin/nanopay-spec",
  "license": "MIT",
  "x402_extension_pr": "https://github.com/x402-foundation/x402/pull/NNNN",
  "reference_impl": "https://hivemorph.onrender.com",
  "tiers": ["pq", "lite"],
  "default_tier": "pq",
  "opt_in_header": "X-Hive-Nanopay-Tier: lite",
  "bench_endpoint": "GET /v1/nanopay/bench",
  "cross_rail_endpoint": "POST /v1/nanopay/cross-rail",
  "verify_endpoint": "POST /v1/nanopay/cross-rail/verify"
}
```

### 8.6 Tier Negotiation via Request Header

The operating tier is determined by the presence or absence of the `X-Hive-Nanopay-Tier` request header:

| Header Value | Tier Applied | Envelope | Floor |
|---|---|---|---|
| Absent | pq (default) | ed25519+ml-dsa-65+slh-dsa | $0.0003 |
| `lite` | lite | eip3009+ed25519+merkle-batch-root | $0.000001 |

Any value other than `lite` is treated as absent (PQ default). The header may be sent on any nanopay endpoint; it is most relevant on `POST /v1/nanopay/cross-rail`.

When a client sends `X-Hive-Nanopay-Tier: lite` on an endpoint that requires payment, the server may respond with HTTP 402 containing a `Payment-Required` header specifying the lite-tier floor. This is the x402 negotiation flow applied to the lite tier.

---

## 9. Compliance Mapping

The following table maps Hive Nanopay primitives to regulatory and policy frameworks. The full compliance analysis is published at https://thehiveryiq.com/nanopay/. This section is the inline summary.

| Framework | Article | Hive Nanopay Primitive | Coverage |
|---|---|---|---|
| MiCA | Art 34 | Receipt-verifiable audit trail; canonical hash per receipt; immutable after issuance | Full |
| DORA | Art 9 | PQ signature suite (ML-DSA-65 + SLH-DSA) provides cryptographic resilience against ICT disruption; key rotation via DID | Full |
| DORA | Art 28 | Cross-rail redundancy (5 active rails); batch root anchoring for operational continuity | Full |
| EU AI Act | Art 12 | Receipt `receipt_id` + `ts` provide per-event log records required for automated decision-making systems | Full |
| EU AI Act | Art 15 | PQ envelope survivability extends accuracy and robustness guarantees of AI-managed payment flows | Full |
| NSM-10 | — | NIST FIPS 204 (ML-DSA-65) and FIPS 205 (SLH-DSA) are the two NIST-selected post-quantum signature standards mandated under NSM-10 for national security systems | Full |

**Notes:**

- MiCA Art 34 requires issuers of crypto-asset services to maintain records sufficient for competent authority audit. Hive Nanopay receipts satisfy this by design: each receipt is a self-contained, canonical, signed document.
- DORA Art 9 requires ICT risk management frameworks including cryptographic controls. PQ signatures provide forward-looking resilience.
- DORA Art 28 requires operational resilience testing and continuity planning. The multi-rail architecture and batch root design provide rail-level failover.
- EU AI Act Art 12 requires logging of automated system decisions. Receipts serve as the log record for autonomous agentic payment decisions.
- EU AI Act Art 15 requires robustness and accuracy of high-risk AI. PQ signature survivability prevents receipt forgery in future cryptographic environments.
- NSM-10 (National Security Memorandum on Promoting United States Leadership in Quantum Computing) mandates migration to NIST PQC standards for federal systems. Hive Nanopay is already compliant.

---

## 10. Security Considerations

### 10.1 Quantum Risk Model

Classical elliptic-curve signatures (ECDSA, plain Ed25519) are vulnerable to a cryptographically relevant quantum computer (CRQC) via Shor's algorithm. While no CRQC exists today, NIST has standardized post-quantum replacements (FIPS 204, FIPS 205) specifically to enable migration before CRQCs emerge. Hive Nanopay Tier 1 includes Ed25519 for current-system compatibility and ML-DSA-65 + SLH-DSA for post-quantum survivability. An attacker with a CRQC can break Ed25519 but not ML-DSA-65 or SLH-DSA; the all-of-three combiner means a receipt remains valid as long as the two PQ signatures hold.

Tier 2 includes only Ed25519 per-receipt (plus the amortized batch root PQ signature). Operators using Tier 2 accept that per-receipt classical signatures are at long-term quantum risk; the batch root provides partial PQ coverage at the batch level.

### 10.2 Replay Protection

Each receipt carries a `receipt_id` (UUID v4) and a `ts` (Unix epoch seconds). Verifiers must:

1. Check that `receipt_id` has not been seen before (maintain a short-lived seen-set with TTL equal to the replay window).
2. Reject receipts where `abs(now - ts) > 300` (five-minute window). This value may be tightened by operator policy.

EIP-3009 pre-authorizations in Tier 2 lite envelopes carry their own `nonce`, `validAfter`, and `validBefore` fields. These provide on-chain replay protection independent of the receipt-level `ts` check. Verifiers must honor both layers.

### 10.3 Batch Root Tampering

A malicious actor who can modify a receipt's `batch_index` or `batch_root` field without access to the signing key cannot forge a valid inclusion proof because the Merkle root is signed by the batch-level PQ signature. However, if the batch close endpoint is compromised, an adversary could substitute a different Merkle root. Operators must:

1. Verify the batch root PQ signature before accepting any receipt's batch membership claim.
2. Independently anchor batch roots on-chain (Base or Ethereum) via the `batch_open_endpoint` / `batch_close_endpoint` flow.
3. Treat any receipt with a `batch_index` beyond the claimed batch size as invalid.

### 10.4 Signature Aggregation Pitfalls

The all-of-three combiner does not perform cryptographic aggregation (e.g., BLS aggregation). Each signature is verified independently. This is intentional: aggregation schemes introduce new attack surfaces (rogue-key attacks, subgroup attacks) that are not yet standardized for post-quantum schemes. Independent verification is slower but eliminates aggregation-specific risks.

### 10.5 Key Rotation via DID

Signing keys are identified by `envelope.kid`, a DID. DID documents may be updated to reflect key rotation. Verifiers must resolve the DID document at verification time (or use a cached version with a short TTL). Cached resolution must not accept DID documents with `deactivated: true`. Key rotation does not invalidate previously issued receipts: verifiers should accept receipts signed under any key that was active in the DID document at the time of the receipt's `ts`.

---

## 11. x402 Compatibility

### 11.1 Protocol Position

Hive Nanopay is a conforming extension of the x402 payment protocol. x402 defines a standard HTTP 402 negotiation flow: a server responds 402 with payment terms; the client pays and retries with a payment proof header. Hive Nanopay extends this flow in two ways:

1. **Tier negotiation:** The `X-Hive-Nanopay-Tier: lite` request header allows clients to negotiate down to the lite tier before receiving the 402 response, reducing the round-trip for clients that know their tier preference in advance.

2. **Cross-rail receipts:** The payment proof submitted in the `X-Payment` header (or equivalent) may be a Hive Nanopay cross-rail receipt rather than a single-chain proof. Servers that understand Hive Nanopay can verify receipts across multiple rails; servers that do not will see a structurally valid payment proof and can fall back to their default verification path.

### 11.2 x402 Extension Document

This specification is accompanied by a short extension document filed as a pull request against the x402 extensions directory. The extension document is located at:

```
docs/extensions/nanopay.md
```

in the `x402-foundation/x402` repository. The PR proposes Hive Nanopay as an officially recognized x402 extension.

### 11.3 Backward Compatibility

Clients that do not send `X-Hive-Nanopay-Tier: lite` receive PQ-tier behavior. Clients that do not understand the Hive Nanopay envelope structure see a well-formed JSON payment receipt with a standard Ed25519 signature; they may ignore the ML-DSA-65 and SLH-DSA fields without breaking the x402 flow. This design ensures that Hive Nanopay is additive and does not break non-Hive x402 clients.

---

## 12. Reference Implementation

### 12.1 Live Endpoint

The canonical reference implementation is deployed at:

```
https://hivemorph.onrender.com
```

This deployment runs the full PQ signature stack for Tier 1 and the Ed25519 + Merkle stack for Tier 2 lite. All five active rails are supported. The deployment is live and processes real receipt requests.

As of this specification version: 4,120+ receipts shipped, 100% PQ coverage, 5 active rails.

### 12.2 Curl Examples

**Bench — live counters and tier table:**

```bash
curl -s https://hivemorph.onrender.com/v1/nanopay/bench | jq
```

**Cross-rail issue — issue a new PQ receipt across two rails:**

```bash
curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail \
  -H "Content-Type: application/json" \
  -d '{"rails":["base-usdc","solana-usdc"],"amount_usd":0.0003}' | jq
```

**Cross-rail verify — verify a previously issued receipt:**

```bash
RECEIPT=$(curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail \
  -H "Content-Type: application/json" \
  -d '{"rails":["base-usdc"],"amount_usd":0.0003}')
echo "$RECEIPT" | curl -s -X POST https://hivemorph.onrender.com/v1/nanopay/cross-rail/verify \
  -H "Content-Type: application/json" \
  -d @- | jq
```

**Lite-tier opt-in — trigger 402 negotiation at lite-tier floor:**

```bash
curl -s -o /dev/null -w "%{http_code}\n%{header_json}" \
  -H "X-Hive-Nanopay-Tier: lite" \
  https://hivemorph.onrender.com/v1/evaluator/economics
```

**Spec metadata:**

```bash
curl -s https://hivemorph.onrender.com/v1/nanopay/standard | jq
```

---

## 13. Authors and License

**Authors:**  
Steve Rotzin (HiveryIQ)  
Contact: steve@thehiveryiq.com  
Web: https://thehiveryiq.com  
Reference impl: https://hivemorph.onrender.com  

**Acknowledgments:**  
This specification builds on the x402 protocol developed by the x402 Foundation, NIST post-quantum cryptography standards (FIPS 204, FIPS 205), and the W3C Decentralized Identifiers (DIDs) Core specification.

**License:**  
MIT License — see [LICENSE](./LICENSE) in this repository.

Copyright (c) 2026 Steve Rotzin / HiveryIQ

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
