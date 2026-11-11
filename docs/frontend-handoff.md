# Quote Fuse — Stage 4A Frontend Handoff

This document defines the contract interfaces, deployment manifest, replay fixture, live RPC read specifications, and execution boundaries for building the Quote Fuse frontend against the verified Stage 3 deployment.

## 1. Source-of-Truth Files

| Artifact | Path | Purpose |
| --- | --- | --- |
| Deployment & run manifest | [`deployments/stage-3.json`](../deployments/stage-3.json) | Canonical deployed contract addresses, token addresses, signatures, and recorded Stage 3 run values |
| Replay fixture | [`deployments/stage-3-replay.json`](../deployments/stage-3-replay.json) | Machine-readable replay bundle containing quote terms/expiry, price move and threshold, requested/applied versions, all three linked tx hashes, both fill receipts, and the decoded stale-quote `eth_call` |
| Stage 3 live report | [`docs/stage-3-live-invalidation-report.md`](stage-3-live-invalidation-report.md) | Full narrative verification report for the Stage 3 run |
| Unichain pool ABI | [`abi/ControlledPool.json`](../abi/ControlledPool.json) | ABI for `ControlledPool` on Unichain Sepolia |
| Lasna subscriber ABI | [`abi/PoolPriceSubscriber.json`](../abi/PoolPriceSubscriber.json) | ABI for `PoolPriceSubscriber` on Reactive Lasna |
| Base settlement ABI | [`abi/QuoteSettlement.json`](../abi/QuoteSettlement.json) | Shared ABI for **both** the control and protected `QuoteSettlement` instances on Base Sepolia |
| Base version receiver ABI | [`abi/QuoteVersionReceiver.json`](../abi/QuoteVersionReceiver.json) | ABI for `QuoteVersionReceiver` on Base Sepolia |
| Base demo taker ABI | [`abi/DemoTaker.json`](../abi/DemoTaker.json) | ABI for the deployer-owned `DemoTaker` helper on Base Sepolia |

---

## 2. Networks, Chain IDs, and Deployed Addresses

All addresses below come from [`deployments/stage-3.json`](../deployments/stage-3.json).

### Unichain Sepolia — Origin Pool (`chainId: 1301`)

- **RPC URL:** `https://sepolia.unichain.org`
- **Block Explorer:** `https://sepolia.uniscan.xyz`

| Manifest Key | Role | Address | ABI / Decimals |
| --- | --- | --- | --- |
| `source.pool` | `ControlledPool` | `0x51e7249e7A5a08CAcB388372947b34eE5BbD03ec` | [`abi/ControlledPool.json`](../abi/ControlledPool.json) |
| `source.token0` (`source.tokenA`) | Token 0 (`QFA`) | `0x8D32Fdd31fBAB4F6C484b0F5358d9Ae61d3DEc44` | 18 decimals |
| `source.token1` (`source.tokenB`) | Token 1 (`QFB`) | `0x92aFcaAF8932062797c94ec8A1E57E40C93E7F26` | 18 decimals |

### Reactive Lasna — Price Subscriber (`chainId: 5318007`)

- **RPC URL:** `https://lasna-rpc.rnk.dev/`
- **Block Explorer:** `https://lasna.reactscan.net`

| Manifest Key | Role | Address | ABI |
| --- | --- | --- | --- |
| `lasna.subscriber` | `PoolPriceSubscriber` | `0xF4661247F45BC36BdBFdF355De965dE03DB5D467` | [`abi/PoolPriceSubscriber.json`](../abi/PoolPriceSubscriber.json) |
| *(System constant)* | Lasna System Contract | `0x8888888888888888888888888888888888888888` | Omni `ISystemContract` |

### Base Sepolia — Quote Settlement & Callback Destination (`chainId: 84532`)

- **RPC URL:** `https://sepolia.base.org`
- **Block Explorer:** `https://sepolia.basescan.org`

| Manifest Key | Role | Address | ABI / Notes |
| --- | --- | --- | --- |
| `base.control` | Control `QuoteSettlement` | `0x571d89770382C0697bF94523eB7dc56288fA6346` | [`abi/QuoteSettlement.json`](../abi/QuoteSettlement.json) (`protectedMode = false`) |
| `base.protected` | Protected `QuoteSettlement` | `0x216e52c338C6CE0197d5e3bCC4E99C94c12e359e` | [`abi/QuoteSettlement.json`](../abi/QuoteSettlement.json) (`protectedMode = true`) |
| `base.receiver` | `QuoteVersionReceiver` | `0x1f111Ad6583FC4dFACf260821de593029d7e7915` | [`abi/QuoteVersionReceiver.json`](../abi/QuoteVersionReceiver.json) |
| `base.taker` | `DemoTaker` | `0x2886842113B6aFAf4603b853c43ff9e49C3585e4` | [`abi/DemoTaker.json`](../abi/DemoTaker.json) (owned by `deployer`) |
| `base.tokenA` | Maker Token (`QSA`) | `0xD498FfB35de781dFF2EfDC310cf701B57aCb6aD8` | 18 decimals |
| `base.tokenB` | Taker Token (`QSB`) | `0x54aA3F15ddF203dC17766941405ef9F801BA0ADC` | 18 decimals |
| *(Callback proxy)* | Base Callback Proxy | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` | Official Omni service provider on Base Sepolia |

---

## 3. Reading Live State Using the Manifest and ABIs

### 3.1 Unichain Sepolia (`chainId: 1301`) — Pool Reserves & Spot Price

Use `deployments/stage-3.json -> source.pool` (`0x51e7249e7A5a08CAcB388372947b34eE5BbD03ec`) and [`abi/ControlledPool.json`](../abi/ControlledPool.json):

| Method Signature | Return Type | Units & Interpretation | Verified Stage 3 Post-Swap Value |
| --- | --- | --- | --- |
| `reserve0()` | `uint112` | Raw `token0` (`QFA`) reserve in wei (`10^18` base units = `1 QFA`) | `1021000000000000000000` (`1,021 QFA`) |
| `reserve1()` | `uint112` | Raw `token1` (`QFB`) reserve in wei (`10^18` base units = `1 QFB`) | `979431929480901077377` (`979.431929480901077377 QFB`) |
| `token0()` | `address` | Numerically lower token address (`QFA`) | `0x8D32Fdd31fBAB4F6C484b0F5358d9Ae61d3DEc44` |
| `token1()` | `address` | Numerically higher token address (`QFB`) | `0x92aFcaAF8932062797c94ec8A1E57E40C93E7F26` |

**Implied Spot Price Formula and Unit:**
- **Formula:** `price = (BigInt(reserve1) * 10n ** 18n) / BigInt(reserve0)` (integer division rounds down, matching `PoolPriceSubscriber.sol`).
- **Unit:** **Token 1 (`QFB`) per Token 0 (`QFA`) in 18-decimal fixed-point (`1e18` scale)**.
- **Example:** Post-swap `979431929480901077377 * 10^18 / 1021000000000000000000 = 959286904486680780` (`0.95928690448668078 QFB per QFA`).

### 3.2 Reactive Lasna (`chainId: 5318007`) — Accepted Reference Price & Requested Version

Use `deployments/stage-3.json -> lasna.subscriber` (`0xF4661247F45BC36BdBFdF355De965dE03DB5D467`) and [`abi/PoolPriceSubscriber.json`](../abi/PoolPriceSubscriber.json):

| Method Signature | Return Type | Units & Interpretation | Verified Stage 3 Post-Swap Value |
| --- | --- | --- | --- |
| `acceptedReference()` | `uint256` | Last accepted reference price in **token1 per token0 (`QFB` per `QFA`), 18-decimal fixed-point (`1e18` scale)** | `959286904486680780` (was `998002996004994006` before the qualifying swap) |
| `latestVersionRequested()` | `uint256` | Monotonic integer version counter (`0` initially; incremented by `1` on each qualifying price move) | `1` |
| `thresholdBps()` | `uint256` | Invalidation threshold in **basis points** (`1 bps = 0.01%`, `10000 bps = 100%`). A move qualifies when `abs(price - acceptedReference) * 10000 >= acceptedReference * thresholdBps` | `300` (`3.00%`) |
| `lastBlockNumber()` | `uint256` | Unichain Sepolia block number of the last processed `Sync` log | `67574196` (`0x40719b4`) |
| `lastLogIndex()` | `uint256` | Log index within `lastBlockNumber` of the last processed `Sync` log | `0` |
| `receiver()` | `address` | Destination `QuoteVersionReceiver` on Base Sepolia | `0x1f111Ad6583FC4dFACf260821de593029d7e7915` |

### 3.3 Base Sepolia (`chainId: 84532`) — Applied Version, Nonce Status, and Receiver State

Use `deployments/stage-3.json -> base.protected` (`0x216e52c338C6CE0197d5e3bCC4E99C94c12e359e`) and `base.control` (`0x571d89770382C0697bF94523eB7dc56288fA6346`) with the single shared [`abi/QuoteSettlement.json`](../abi/QuoteSettlement.json):

| Method Signature | Return Type | Units & Interpretation | Control Instance (`base.control`) | Protected Instance (`base.protected`) |
| --- | --- | --- | --- | --- |
| `quoteVersion()` | `uint256` | Applied quote version integer (`uint256`, unitless). Enforced on fill only when `protectedMode() == true` | `0` | `1` |
| `protectedMode()` | `bool` | Whether `fill` requires `quote.version == quoteVersion` | `false` | `true` |
| `nonceUsed(uint256)` | `bool` | Whether a quote `nonce` (`uint256`) has already been filled | `nonceUsed(1) = true`, `nonceUsed(2) = false` | `nonceUsed(1) = false`, `nonceUsed(2) = true` |
| `versionReceiver()` | `address` | Authorized callback receiver allowed to call `advanceVersion` | `0x0000000000000000000000000000000000000000` | `0x1f111Ad6583FC4dFACf260821de593029d7e7915` |
| `maker()` | `address` | Fixed maker signer (`deployer`) | `0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf` | `0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf` |
| `makerToken()` | `address` | Base `QSA` token (18 decimals, wei units `1e18`) | `0xD498FfB35de781dFF2EfDC310cf701B57aCb6aD8` | `0xD498FfB35de781dFF2EfDC310cf701B57aCb6aD8` |
| `takerToken()` | `address` | Base `QSB` token (18 decimals, wei units `1e18`) | `0x54aA3F15ddF203dC17766941405ef9F801BA0ADC` | `0x54aA3F15ddF203dC17766941405ef9F801BA0ADC` |
| `hashQuote((address,address,address,address,uint256,uint256,uint256,uint256,uint256))` | `bytes32` | EIP-712 digest (`\x19\x01` + `domainSeparator()` + struct hash). Amounts are in 18-decimal wei (`1e18`); `expiry` is Unix timestamp in seconds (`uint256`) | Instance-specific `bytes32` | Instance-specific `bytes32` |

To inspect the callback receiver directly on Base Sepolia (`84532`), use `base.receiver` (`0x1f111Ad6583FC4dFACf260821de593029d7e7915`) and [`abi/QuoteVersionReceiver.json`](../abi/QuoteVersionReceiver.json):
- `settlement()(address)` → `0x216e52c338C6CE0197d5e3bCC4E99C94c12e359e` (`base.protected`)
- `_SERVICE_PROVIDER()(address)` → `0x476F44b11F5C942c58f4c8E3d0300E5710743585` (Base callback proxy)
- `_CALLBACK_SENDER()(address)` → `0xF4661247F45BC36BdBFdF355De965dE03DB5D467` (`lasna.subscriber`)

---

## 4. Data Source Boundaries: Live Reads vs. Historical Replay vs. `DemoTaker` Actions

The frontend should combine live multi-chain reads with the deterministic Stage 3 replay fixture (`deployments/stage-3-replay.json`) and clearly label each data source.

### 4.1 Views Powered by Live On-Chain Reads (`eth_call`)

These panels query Unichain Sepolia (`1301`), Reactive Lasna (`5318007`), and Base Sepolia (`84532`) directly via JSON-RPC `eth_call`:

1. **Current Unichain Pool State (`1301`):**
   - Live `reserve0()` and `reserve1()` on `source.pool`, plus the live computed price `floor(reserve1 * 1e18 / reserve0)`.
2. **Current Lasna Subscriber State (`5318007`):**
   - Live `acceptedReference()`, `latestVersionRequested()`, `thresholdBps()`, and `lastBlockNumber()` on `lasna.subscriber`.
3. **Current Base Settlement State (`84532`):**
   - Live `quoteVersion()`, `protectedMode()`, `nonceUsed(1)`, and `nonceUsed(2)` on both `base.control` and `base.protected`.
4. **Live Simulated Stale-Quote Check (`eth_call` on Base Sepolia `84532`):**
   - Because `nonceUsed(1)` on `base.protected` remains `false` and the signed expiry is `1795031195` (`2026-11-18T19:46:35Z`), the frontend can execute a live read-only `eth_call` to `DemoTaker.fill(base.protected, protectedInitial.terms, protectedInitial.signature)` with `"from": "0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf"`.
   - Before expiry, the live contract returns custom error `0x29a199d7` = `StaleQuoteVersion(0, 1)`.
   - **Required UI Label:** Always label this rejection as a **simulated call (`eth_call`) against the live contract**, not a broadcasted on-chain revert receipt.

### 4.2 Views Powered by Historical Replay Data (`deployments/stage-3-replay.json`)

Because the on-chain contracts now sit in their **post-run** state (version `1`, post-swap reserves, control nonce `1` and protected nonce `2` already consumed), the following views use [`deployments/stage-3-replay.json`](../deployments/stage-3-replay.json):

1. **Pre-Swap vs. Post-Swap Price Move Comparison:**
   - Pre-swap reserves (`1001 QFA`, `999.000999000999001 QFB`) and initial accepted reference (`998002996004994006` = `0.998002996004994006 QFB/QFA`).
   - Qualifying 20 `QFA` → `19.569069520097923623 QFB` swap and resulting downward move of **~387.93 bps** vs. the **300 bps** threshold.
2. **Three-Chain Causal Transaction Timeline:**
   - Unichain qualifying swap tx [`0xde5cf4eba5b9226c9a5a26b1d3cd6c9e0dec70fcf996020b69e6080ba3194e68`](https://sepolia.uniscan.xyz/tx/0xde5cf4eba5b9226c9a5a26b1d3cd6c9e0dec70fcf996020b69e6080ba3194e68) (block `67,574,196`, `80,593` gas).
   - Lasna reaction tx [`0xa969f4e724be36142bd8a7fb48adf0e6f4f28a16127e09d948e18dc64e9bf75a`](https://lasna.reactscan.net/tx/0xa969f4e724be36142bd8a7fb48adf0e6f4f28a16127e09d948e18dc64e9bf75a) (block `8,107,954` / `0x7bb7b2`, `134,337` gas).
   - Base callback tx [`0x90503742545a0928b9d4fb65a40338341f4f551cc76eeab829933da929d58271`](https://sepolia.basescan.org/tx/0x90503742545a0928b9d4fb65a40338341f4f551cc76eeab829933da929d58271) (block `57,523,785`, `91,130` gas).
3. **Observer Timing Interval (`10.43 seconds`):**
   - `linkedTransactions.timingObservation.observedIntervalSeconds` = `10.430438` seconds (`10430.438 ms`).
   - **Required UI Label:** Always label the `10.43`-second interval as **one observed run with 1s polling** (single observer clock receipt visibility, not a latency distribution or cross-chain block timestamp subtraction).
4. **Side-by-Side Signed Quotes and Historical Fill Receipts:**
   - `quotes.controlInitial` (version `0`, nonce `1`, `100 QSA` → `99.8002996004994006 QSB`) and its successful fill receipt [`0xe0986ce84d9d4f87b2d8d48ab4169526908d5432a408d71f11a1207591860283`](https://sepolia.basescan.org/tx/0xe0986ce84d9d4f87b2d8d48ab4169526908d5432a408d71f11a1207591860283) (`153,254` gas).
   - `quotes.protectedInitial` (version `0`, nonce `1`, `100 QSA` → `99.8002996004994006 QSB`) and its recorded simulated `eth_call` revert `StaleQuoteVersion(0, 1)` at Base timestamp `1794427069` before expiry `1795031195` (labeled as a **simulated call against the live contract**).
   - `quotes.protectedFresh` (version `1`, nonce `2`, `100 QSA` → `95.928690448668078 QSB`) and its successful fill receipt [`0x63b51f771fc8e213be8cbf1b5ed1a0953c53d38bcd12360292d71eed663b9486`](https://sepolia.basescan.org/tx/0x63b51f771fc8e213be8cbf1b5ed1a0953c53d38bcd12360292d71eed663b9486) (`121,189` gas).

### 4.3 Actions Requiring the Deployer-Controlled `DemoTaker` (and Keystore Signer)

`QuoteSettlement.fill(quote, signature)` requires `msg.sender == quote.taker`. In the Stage 3 deployment, `quote.taker` is the `DemoTaker` contract (`0x2886842113B6aFAf4603b853c43ff9e49C3585e4`), whose functions (`fill` and `approveToken`) check `msg.sender == owner` (`0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf`). Likewise, `QuoteSettlement` has immutable `maker = 0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf`.

- **No Key Needed (Frontend Read / Simulation):**
  - Reading any contract view method on Unichain, Lasna, or Base.
  - Simulating `DemoTaker.fill(...)` via `eth_call` by setting `"from": "0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf"` in the RPC call parameters.
- **Deployer Keystore Required (`0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf`):**
  - Broadcasting a real state-changing `DemoTaker.fill` or `DemoTaker.approveToken` transaction on Base Sepolia.
  - Signing a new EIP-712 maker quote valid for `base.control` or `base.protected`.
  - Broadcasting a new qualifying swap from the pre-funded deployer wallet on Unichain Sepolia.

---

## 5. Running a Fresh Live Demo (Reproducible PowerShell Scripts)

To run a fresh end-to-end live cycle from an interactive terminal using the local Foundry keystore (`-Account quote-fuse-testnet`), use the five Stage 3 scripts in `script/`:

1. [`script/Stage3-SourceSetup.ps1`](../script/Stage3-SourceSetup.ps1) — Verifies Unichain Sepolia (`1301`) and keystore address, deploys/verifies `QFA`, `QFB`, and `ControlledPool`, seeds `1,000 QFA` + `1,000 QFB`, executes the 1-token rehearsal swap, verifies the `Sync` log against `reserve0`/`reserve1`, and saves `source.startingReference` to `deployments/stage-3.json`.
2. [`script/Stage3-SettlementSetup.ps1`](../script/Stage3-SettlementSetup.ps1) — Verifies all three chain IDs (`1301`, `5318007`, `84532`), deploys/verifies Base tokens (`QSA`, `QSB`), `control` and `protected` `QuoteSettlement` instances, `DemoTaker`, Lasna `PoolPriceSubscriber`, and Base `QuoteVersionReceiver`, wires the receiver on both Base and Lasna, funds execution reserves (`1 lREACT` on Lasna system contract, `0.01 ETH` on Base callback proxy), and mints/approves settlement tokens.
3. [`script/Stage3-SignAndRehearse.ps1`](../script/Stage3-SignAndRehearse.ps1) — Computes the EIP-712 quote digests on `base.control` and `base.protected` for the current version, signs both quotes with the local Foundry keystore, and verifies via `eth_call` through `DemoTaker.fill` that both quotes are fillable before the pool swap.
4. [`script/Stage3-TriggerAndObserve.ps1`](../script/Stage3-TriggerAndObserve.ps1) — Verifies that a 20-`QFA` swap crosses the 300 bps threshold, broadcasts `swapExact0For1(20e18, 1)` on Unichain Sepolia, polls Lasna (`latestVersionRequested`) and Base (`quoteVersion`) at `1,000 ms` intervals, and records `qualifyingSwapTx`, `lasnaReactionTx`, `baseVersionTx`, first-seen timestamps, and `observedLatencyMs`.
5. [`script/Stage3-FillAndVerify.ps1`](../script/Stage3-FillAndVerify.ps1) — Broadcasts the control fill via `DemoTaker.fill`, executes the read-only `eth_call` against `base.protected` with the old version-0 quote to verify `StaleQuoteVersion(signedVersion, currentVersion)` before expiry, signs a fresh version-`N` quote priced from the post-swap pool reserves, broadcasts the fresh protected fill via `DemoTaker.fill`, and updates `deployments/stage-3.json`.
