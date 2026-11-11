# Quote Fuse — Stage 2 signed quote settlement

**Date:** 11 November 2026 (Africa/Lagos)
**Verdict: PASS for the local settlement milestone.** No Stage 2 contracts were deployed, and no on-chain transactions were made. The Stage 1 deployments remain available as the live callback reference.

## Contracts and interfaces

| File | Purpose |
| --- | --- |
| [`src/QuoteSettlement.sol`](../src/QuoteSettlement.sol) | One settlement implementation deployed in immutable control or protected mode. Fixed maker and fixed ERC-20 pair are constructor parameters. `fill(Quote, bytes signature)` performs full atomic token exchange. `advanceVersion(uint256)` is callable only by the configured version receiver in protected mode. |
| [`src/QuoteVersionReceiver.sol`](../src/QuoteVersionReceiver.sol) | Base callback receiver. `onVersion(address reactive_, uint256 newVersion)` uses Omni `onlyServiceProvider` to authenticate the callback proxy and `onlyCallbackSender(reactive_)` to authenticate the designated Lasna sender, then forwards to settlement. |
| [`src/MockERC20.sol`](../src/MockERC20.sol) | Local test token with mint, approval, balances, and configurable transfer failure. |
| [`test/QuoteSettlement.t.sol`](../test/QuoteSettlement.t.sol) | Local EIP-712 signing, mock proxy fixture, acceptance and failure tests. |

`Quote` signs **maker, taker, makerToken, takerToken, makerAmount, takerAmount, expiry, nonce, and version**. The EIP-712 domain is `Quote Fuse` / `1`, `block.chainid`, and the settlement contract address. `hashQuote(Quote)` exposes the digest for signing. Only the signed taker may call `fill`. Each settlement instance verifies its fixed maker and token pair, positive amounts, expiry, one-use nonce, and maker signature. Protected mode additionally requires `q.version == quoteVersion`; control mode does not enforce version. Both modes still sign the version and all other fields. An invalid protected version reverts with the distinct `StaleQuoteVersion(signedVersion, currentVersion)` error.

On fill, the signed taker amount moves from taker to maker and the signed maker amount moves from maker to taker. A failed token call reverts the whole transaction, including any preceding transfer and nonce mark. A reentrancy lock covers the external token calls. `QuoteFilled` emits quote digest, nonce, taker, and version. `VersionAdvanced` emits old and new version. `setVersionReceiver` is owner-only and one-time for protected mode, and emits `VersionReceiverConfigured`. Duplicate or older updates return without changing state. The receiver's proxy and Lasna sender are immutable Omni base-constructor values.

## Acceptance and test results

`forge build` compiled successfully with Solidity **0.8.29** and the existing pinned `reactive-lib-omni` `v0.1.0` dependency. `forge test --summary` finished **14 passed, 0 failed**: **7 Stage 2 tests** and **7 existing Stage 1 tests**.

`testSideBySideVersionInvalidation` creates control and protected quotes with the same maker, taker, token pair, amounts, expiry, nonce, and starting version. Each is signed for its own settlement address. A local proxy fixture delivers an authenticated update to version 1. The control quote fills; the old protected quote reverts specifically with `StaleQuoteVersion(0,1)` and leaves both token balances and its nonce unchanged. A new protected quote signed for version 1 with a fresh nonce fills, and both token balances move by the signed amounts. `testProtectedQuoteFillsBeforeAdvance` separately confirms that the protected version-0 quote fills before invalidation.

Additional tests cover expiry at the boundary, nonce reuse, tampered amount and pair, wrong caller/taker, cross-instance signature replay, chain-ID domain replay, failed first and second ERC-20 transfers with atomic rollback, direct callback bypassing the proxy, an unapproved Lasna sender through the proxy, direct version mutation, and duplicate/older version updates. The Stage 1 smoke tests run unchanged.

```text
forge build: Compiler run successful!
forge test --summary:
  QuoteSettlementTest  7 passed, 0 failed
  SmokeTest            7 passed, 0 failed
  Total               14 passed, 0 failed
```

The build emits Foundry lint warnings around low-level token calls, reentrancy/event ordering, and timestamp use. The implementation sets the reentrancy lock before either token call, and the tests verify atomic rollback when either leg fails. Expiry follows `block.timestamp`, as required for on-chain quotes; a block producer can affect boundary timing. No live settlement gas or token behavior has been measured in Stage 2.

## Exact Stage 3 next action

Choose and verify a real Unichain Sepolia reference pool and event ABI, then implement a Lasna subscriber that decodes that pool's price signal and requests the same authenticated Base version callback when the configured threshold is crossed. Build and test the pool-event filter and threshold logic locally; then deploy the two Base settlement instances, receiver, and new Lasna subscriber on the specified testnets, fund execution reserves, and run the signed-quote side-by-side demo. Estimate gas against those compiled deployment contracts before broadcasting. The current Stage 1 contracts and receipts remain the proven live callback reference.
