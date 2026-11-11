# Quote Fuse — Stage 3 live pool-driven quote invalidation

**Date:** 11 November 2026 (Africa/Lagos)
**Verdict: PASS.** A real swap in the controlled Unichain Sepolia pool changed its stored reserves and emitted `Sync`. The matching Lasna reaction requested version 1, and the authenticated Base callback advanced the protected settlement from version 0 to 1. The control quote filled; the old protected quote reverted with `StaleQuoteVersion(0,1)` before expiry; a newly signed version-1 protected quote reflecting the new pool price filled. No second qualifying source swap was sent.

## Networks, source pool, and contracts

The deployer was the encrypted Foundry keystore account `0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf`. The user entered its password only in their terminal. Broadcasts used only Unichain Sepolia (1301), Reactive Lasna (5318007), and Base Sepolia (84532). The earlier [Stage 1 live report](stage-1-live-callback-report.md) remains the reference for the original smoke-test deployments; this stage used new contracts.

| Network | Component | Address |
| --- | --- | --- |
| Unichain | Token 0, `QFA`, 18 decimals | `0x8D32Fdd31fBAB4F6C484b0F5358d9Ae61d3DEc44` |
| Unichain | Token 1, `QFB`, 18 decimals | `0x92aFcaAF8932062797c94ec8A1E57E40C93E7F26` |
| Unichain | Controlled constant-product pool | `0x51e7249e7A5a08CAcB388372947b34eE5BbD03ec` |
| Lasna | Pool price subscriber | `0xF4661247F45BC36BdBFdF355De965dE03DB5D467` |
| Base | Maker token `QSA`, 18 decimals | `0xD498FfB35de781dFF2EfDC310cf701B57aCb6aD8` |
| Base | Taker token `QSB`, 18 decimals | `0x54aA3F15ddF203dC17766941405ef9F801BA0ADC` |
| Base | Control settlement | `0x571d89770382C0697bF94523eB7dc56288fA6346` |
| Base | Protected settlement | `0x216e52c338C6CE0197d5e3bCC4E99C94c12e359e` |
| Base | Demo taker, owned by deployer | `0x2886842113B6aFAf4603b853c43ff9e49C3585e4` |
| Base | Authenticated version receiver | `0x1f111Ad6583FC4dFACf260821de593029d7e7915` |

The deployed addresses have bytecode. The pool sorts token addresses numerically, uses `reserve0` and `reserve1` after actual transfers, and emits `Sync(uint112 reserve0,uint112 reserve1)` as a LOG1 with topic `keccak256("Sync(uint112,uint112)")`, `0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1`. A [1-token rehearsal swap](https://sepolia.uniscan.xyz/tx/0x92a225044436d966320b20b58293d833346eb53057e47ac563df66f22d49c37d) succeeded before the subscriber was deployed; its single `Sync` data matched the pool's read-back reserves. The [seed](https://sepolia.uniscan.xyz/tx/0x67f03c176e281a7fcdaf6b61861e5af626b8eb49f1b31feae5e32959cf28c031) was 1,000 of each 18-decimal token.

The price is **token 1 per token 0**, in 18-decimal fixed point: `floor(reserve1 * 10^18 / reserve0)`. Starting after rehearsal, `reserve0 = 1001000000000000000000`, `reserve1 = 999000999000999001000`, and accepted reference `998002996004994006`. The qualifying 20-token token-0-for-token-1 swap left `reserve0 = 1021000000000000000000`, `reserve1 = 979431929480901077377`; the emitted `Sync` data matched these reserves. Its new price was `959286904486680780`, a downward move of approximately **387.93 bps** from the accepted reference, above the configured **300 bps** threshold.

`PoolPriceSubscriber.react` accepts only Lasna system delivery for chain 1301, this pool, the `Sync` topic, LOG1 shape and 64-byte data. It ignores zero/oversize reserves, zero rounded price, duplicate and older origin positions. It compares each price with the **last accepted** reference, so small movements accumulate. Division rounds down; a move at exactly 300 bps qualifies (`move * 10000 >= reference * 300`). A qualifying move increments `latestVersionRequested` monotonically and requests Omni `requestCallbackV_1_0` for Base chain 84532, the receiver, 300,000 callback gas, and typed `onVersion(address,uint256)` payload. Base `QuoteVersionReceiver` authenticates both the official proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585` and designated Lasna subscriber via `onlyServiceProvider` and `onlyCallbackSender`, then calls `QuoteSettlement.advanceVersion`. Duplicate or older versions are no-ops. Requested and applied versions were observed separately at **1** and **1**.

## Linked three-chain run

| Step | Receipt and evidence | Gas used |
| --- | --- | ---: |
| Unichain qualifying swap | [Transaction `0xde5c…4e68`](https://sepolia.uniscan.xyz/tx/0xde5cf4eba5b9226c9a5a26b1d3cd6c9e0dec70fcf996020b69e6080ba3194e68), status `0x1`, block 67,574,196; pool `Sync` has the reserve pair above | 80,593 |
| Lasna reaction | [Transaction `0xa969…f75a`](https://lasna.reactscan.net/tx/0xa969f4e724be36142bd8a7fb48adf0e6f4f28a16127e09d948e18dc64e9bf75a), status `0x1`, block `0x7bb7b2`; `ReferenceAccepted` contains old/new price, version 1, origin block 67,574,196, log index 0; same receipt has system `CallbackRequest` for Base 84532 and the designated receiver | 134,337 |
| Base callback | [Transaction `0x9050…271`](https://sepolia.basescan.org/tx/0x90503742545a0928b9d4fb65a40338341f4f551cc76eeab829933da929d58271), status `0x1`, block 57,523,785; target is official callback proxy, and the protected settlement emitted `VersionAdvanced(0,1)` | 91,130 |

One observer recorded first-seen receipt times at **19:50:23.6512508 UTC** (source), **19:50:31.7035758 UTC** (Lasna), and **19:50:34.0816888 UTC** (Base), polling at **1,000 ms**. The observed source-to-Base interval was **10.430438 seconds** for this run. This measures observer receipt visibility, including RPC response and polling delay; it does not subtract timestamps from different chains.

## Signed quote proof

The maker is the deployer, and the taker is the `DemoTaker` contract controlled by that deployer. This lets the encrypted keystore sign maker quotes and submit taker transactions without exposing a second key. Both old quotes signed the same maker, taker, Base token pair, maker amount **100 QSA**, taker amount **99.8002996004994006 QSB**, expiry **2026-11-18 19:46:35 UTC** (`1795031195`), nonce **1**, and version **0**. Each was signed under the EIP-712 domain bound to its own settlement address and Base chain ID. Before the source swap, `eth_call` confirmed that both fills would succeed.

After the callback:

1. The [control fill](https://sepolia.basescan.org/tx/0xe0986ce84d9d4f87b2d8d48ab4169526908d5432a408d71f11a1207591860283) succeeded (`status 0x1`, 153,254 gas); its nonce 1 is used.
2. An `eth_call` from the signed taker owner through `DemoTaker.fill` against the **old protected quote** returned custom error selector `0x29a199d7` = `StaleQuoteVersion(uint256,uint256)`, decoded arguments **(0, 1)**. The Base block timestamp read for this call was `1794427069` (**2026-11-11 19:57:49 UTC**), which was before signed expiry `1795031195`. Revert data: `0x29a199d700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001`. Protected nonce 1 remains unused.
3. A fresh protected quote used nonce **2**, version **1**, the same maker amount **100 QSA**, and a new taker amount **95.928690448668078 QSB** from the post-swap pool reference. The [fresh fill](https://sepolia.basescan.org/tx/0x63b51f771fc8e213be8cbf1b5ed1a0953c53d38bcd12360292d71eed663b9486) succeeded (`status 0x1`, 121,189 gas); protected nonce 2 is used.

The Base token balances after the two fills were maker **100 QSA / 195.7289900491674786 QSB** and taker **200 QSA / 404.2710099508325214 QSB**, matching both signed exchanges from initial maker 300 QSA and taker 600 QSB. The stale `eth_call` changed neither balance.

## Build, tests, execution reserves, and gas

`forge build --quiet` exited 0. `forge test --summary` passed **18/18 tests**: 3 pool-price tests, 8 quote-settlement tests, and all 7 Stage 1 smoke tests. The local suite covers moves below, exactly at, and above threshold; both directions and cumulative moves; bad pool data and origin log deduplication; the complete local pool-event-to-settlement path; callback authentication, stale-version behavior, and ERC-20 transfer rollback. Solidity is pinned to **0.8.29** and `reactive-lib-omni` to **v0.1.0**, commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`.

Pre-deployment `cast estimate` reads included approximately **792,883 gas** per test-token deployment, **1,326,163 gas** for the Lasna subscriber, **1,364,138 gas** for a Base settlement, **488,782 gas** for the demo taker, and **511,386 gas** for the Base receiver. These are estimates, not transaction receipts. The [pool deployment](https://sepolia.uniscan.xyz/tx/0xc04f31176d54f94b0e3c74e007ff4309d906c874b3a33a4d9577d3546ad5408b) actually used **966,855 gas**, seed **131,547 gas**, rehearsal swap **80,581 gas**, and live qualifying swap **80,593 gas**. The callback requested **300,000 destination gas**, allowing for proxy overhead; the live Base proxy transaction used **91,130 gas**. Positive wallet balances were checked before deployment, and the actual deployments and setup transactions succeeded.

| Provider / beneficiary | Initial funded reserve | After callback | Debt after callback |
| --- | ---: | ---: | ---: |
| Lasna system / new subscriber | 1 lREACT | `981551500000000000` wei (0.9815515 lREACT) | 0 |
| Base proxy / new receiver | 0.01 test ETH | `9999251117800000` wei (0.0099992511178 ETH) | 0 |

The funded reserves belong to the contracts' execution accounts, distinct from the deployer's wallet balances. No top-up was needed for this one callback. `deployments/stage-3.json` is the machine-readable deployment and run manifest.

## Commands and limits

The user ran `Stage3-SourceSetup.ps1`, `Stage3-SettlementSetup.ps1`, `Stage3-SignAndRehearse.ps1`, `Stage3-TriggerAndObserve.ps1`, and `Stage3-FillAndVerify.ps1` with `-Account quote-fuse-testnet` from their own PowerShell terminal. The scripts checked the keystore's public address and chain IDs, saved verified deployments, and prompted interactively for the password. Read-only verification used `cast receipt`, `cast call`, `cast estimate`, and JSON-RPC `eth_call`/`eth_getTransactionReceipt`. RPC DNS/timeouts occurred transiently during setup; the scripts resumed from the recorded state, and all acceptance receipts and final state were verified. No credentials are in this report or manifest.

This is a controlled test-token AMM and a single observed run. The mock tokens have public `mint`, and the pool is intentionally minimal for the hackathon demonstration; neither is production-ready liquidity infrastructure. The 10.43-second observation is not a latency distribution.

**Exact next action:** hand the stable ABIs, `deployments/stage-3.json`, and these five reproducible scripts to Antigravity for the frontend; then repeat live runs to collect a latency distribution. Both activities are after Stage 3.
