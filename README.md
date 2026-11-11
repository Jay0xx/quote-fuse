# Quote Fuse

Quote Fuse makes a fixed-price signed swap quote stale as soon as a reference pool moves far enough. A market maker signs EIP-712 quotes for a Base Sepolia settlement contract. A controlled AMM pool on Unichain Sepolia emits `Sync` after real swaps. A subscriber on Reactive Lasna watches that event and, at a 300 bps move from its last accepted reference, requests an authenticated callback to Base. The protected settlement advances its quote version and rejects old signatures; the control settlement keeps accepting an otherwise identical quote until expiry.

The Stage 3 live run proved the whole path: [Unichain swap](https://sepolia.uniscan.xyz/tx/0xde5cf4eba5b9226c9a5a26b1d3cd6c9e0dec70fcf996020b69e6080ba3194e68) → [Lasna reaction](https://lasna.reactscan.net/tx/0xa969f4e724be36142bd8a7fb48adf0e6f4f28a16127e09d948e18dc64e9bf75a) → [Base version advance](https://sepolia.basescan.org/tx/0x90503742545a0928b9d4fb65a40338341f4f551cc76eeab829933da929d58271). The [control fill](https://sepolia.basescan.org/tx/0xe0986ce84d9d4f87b2d8d48ab4169526908d5432a408d71f11a1207591860283) succeeded; the old protected quote returned `StaleQuoteVersion(0,1)` while unexpired; a [fresh protected fill](https://sepolia.basescan.org/tx/0x63b51f771fc8e213be8cbf1b5ed1a0953c53d38bcd12360292d71eed663b9486) succeeded. See the [full Stage 3 report](docs/stage-3-live-invalidation-report.md) and [public deployment manifest](deployments/stage-3.json). The observed source-to-Base receipt interval was 10.430438 seconds with 1-second polling for this run.

## Networks and contracts

| Role | Network | Chain ID | Contract |
| --- | --- | ---: | --- |
| Source pool | Unichain Sepolia | 1301 | [`ControlledPool.sol`](src/ControlledPool.sol) |
| Price subscriber | Reactive Lasna | 5318007 | [`PoolPriceSubscriber.sol`](src/PoolPriceSubscriber.sol) |
| Quote settlement and callback | Base Sepolia | 84532 | [`QuoteSettlement.sol`](src/QuoteSettlement.sol), [`QuoteVersionReceiver.sol`](src/QuoteVersionReceiver.sol) |

`MockERC20.sol` and `DemoTaker.sol` are testnet demo helpers. Stage 1's emitter, subscriber, and receiver remain in `src/` as the original callback smoke test. The tokens have public minting, and the pool is intentionally minimal; this repository is a testnet prototype.

## Local setup

Install [Foundry](https://getfoundry.sh/introduction/installation/) and ensure `forge`, `cast`, and `anvil` are on `PATH`. The project was verified with Foundry **1.9.0** and Solidity **0.8.29**. Clone with the pinned Omni submodule:

```sh
git clone --recurse-submodules https://github.com/Jay0xx/quote-fuse.git
cd quote-fuse
git -C lib/reactive-lib-omni rev-parse HEAD
forge build
forge test --summary
```

The required `reactive-lib-omni` commit is **`3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`** (`v0.1.0`). If the repository was cloned without submodules, run `git submodule update --init lib/reactive-lib-omni` before building. The nested `forge-std` submodule inside Omni is not used by this project's build or tests.

## Reproducing the live run

The `script/Stage3-*.ps1` scripts deploy and verify the pool and settlement path, sign matching quotes, send one qualifying swap, poll all three chains, and prove the control/stale/fresh outcomes. They use an interactive **local Foundry keystore** selected by `-Account`; no private key or password is stored in this repository. `deployments/stage-3.json` records the verified addresses and public transaction evidence. See the [Stage 3 report](docs/stage-3-live-invalidation-report.md) before any new testnet run. The scripts are resumable from their recorded public state, but an already-fired qualifying swap must be inspected before any retry.

## Frontend preview

The wallet-free [Overview and Replay frontend](frontend/README.md) lives in `frontend/`. From that directory, run `npm install`, then `npm run dev` for a local preview or `npm run build` for a production bundle. It imports the verified [Stage 3 replay fixture](deployments/stage-3-replay.json). Live State and DoraHacks submission are later work.
