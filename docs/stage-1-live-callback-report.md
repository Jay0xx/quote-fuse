# Quote Fuse — Stage 1 live three-chain callback

**Date:** 11 November 2026 (Africa/Lagos)
**Verdict: PASS.** One Unichain event for run ID `0xbb74ea4bc9143588124694c72452fc36a2f91a52cf2357bf1eb749e5c91262c5` produced one successful Lasna reaction and one authenticated Base callback. The Base counter changed from **0 to 1**. No quote settlement, pool-price logic, or frontend work was performed.

## Implementation and local verification

| Component | Final address and behavior |
| --- | --- |
| Unichain emitter | `0xCd3789E4cB5aF0118f2e3b667b98FBa8793CbE9D`; emits `Smoke(bytes32 indexed runId)` |
| Lasna subscriber | `0x269C9B7E8c7C7D11F5EAe7d0Cc0072aA18d38e2a`; subscribes to chain 1301, emitter, and event topic; `react()` is `onlySystem`; filters origin and LOG2 shape; deduplicates run IDs; requests a typed V1.0 callback to Base chain 84532 with 300,000 gas |
| Base receiver | `0xd23d37E513398F934dA1Df396dfD91018E155cab`; `onlyServiceProvider` authenticates Base proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585`, and `onlyCallbackSender` authenticates the Lasna subscriber; increments once per run ID and emits `SmokeReceived` |

Source: [`SmokeEmitter.sol`](../src/SmokeEmitter.sol), [`SmokeSubscriber.sol`](../src/SmokeSubscriber.sol), [`SmokeReceiver.sol`](../src/SmokeReceiver.sol). Scripts: [`Deploy-Smoke.ps1`](../script/Deploy-Smoke.ps1), [`Trigger-Smoke.ps1`](../script/Trigger-Smoke.ps1). Solidity **0.8.29**; [`reactive-lib-omni` v0.1.0](https://github.com/Reactive-Network/reactive-lib-omni/tree/v0.1.0), commit `3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`.

`forge build` succeeded. `forge test --summary` passed **7/7** tests covering valid subscription/payload/callback, direct proxy bypass, unapproved Lasna sender, duplicate Base run ID, unauthenticated `react()`, duplicate Lasna request, mismatched origin logs, and destination configuration without local Lasna code. Tests use a mock system; live receipts below establish actual delivery.

## Three linked live transactions

| Chain | Transaction | Receipt evidence | Gas used |
| --- | --- | --- | ---: |
| Unichain Sepolia | [Event `0x2fad…084b`](https://sepolia.uniscan.xyz/tx/0x2fad4897cf447281c1eb7580a0f643d3cbfa04d0eb4ae4aa11e5e17f61ee084b) | Status `0x1`, block **67,550,089**; one `Smoke` log from the emitter with topic 1 equal to the run ID | 23,137 |
| Reactive Lasna | [Reaction `0xc15c…9c51`](https://lasna.reactscan.net/tx/0xc15c2993b133efb7640e59e8a19bf190c66debf15f9fb2b7f115dbabf7019c51) | Status `0x1`, block **8,085,399**; `SmokeMatched` has the run ID; same receipt has system `CallbackRequest` with destination **84532**, sender = subscriber, recipient = Base receiver; `requested(runId) = true` | 101,532 |
| Base Sepolia | [Callback `0x578d…f876`](https://sepolia.basescan.org/tx/0x578d2f31c5ac02fe0d1b78851d86a2a2199d88aa6f9fedf6b801bcb671b6f876) | Status `0x1`, block **57,403,251**; transaction targets official proxy; one `SmokeReceived` log from receiver has the run ID and counter `1`; `processed(runId) = true` | 108,411 |

The Base counter was read as **0 immediately before** the source trigger and **1 after** the callback, a delta of **+1**. The receiver's explorer log list had exactly one item and no next page. No retry event was sent. Chain block timestamps are unsuitable for a precise latency claim here: Lasna's reaction block timestamp was one second earlier than Unichain's source block, suggesting clock skew or differing timestamp semantics. The causal proof rests on the shared run ID, contract state, and three receipts.

## Deployments, reserves, and gas

The expected deployer `0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf` was checked against the user's encrypted Foundry keystore locally by the user. The key and password were never supplied to the agent or written into the project. Broadcasts were made from the user's interactive terminal on the three specified testnets.

| Contract | Deployment receipt | Final address |
| --- | --- | --- |
| Emitter | [Unichain `0xf761…db4b`](https://sepolia.uniscan.xyz/tx/0xf761894a972aace11853b89a7483ad6927c85a3ce709a25165646c30e2e3db4b) | `0xCd3789E4cB5aF0118f2e3b667b98FBa8793CbE9D` |
| Corrected subscriber | [Lasna `0xdc11…df95`](https://lasna.reactscan.net/tx/0xdc11f664b976fa2d2dcd9b339f416dc655d41ddc4295c7cdcb6c16f6477adf95) | `0x269C9B7E8c7C7D11F5EAe7d0Cc0072aA18d38e2a` |
| Replacement receiver | [Base `0x0506…c053`](https://sepolia.basescan.org/tx/0x0506090897a9cf63a1762c3827b6e82d47c1a34b896e7f228eee3fadf7fbc053) | `0xd23d37E513398F934dA1Df396dfD91018E155cab` |

Lasna `receiver()` equals the final Base address. Base `_CALLBACK_SENDER()` equals the final Lasna address. Read-only calls after the smoke cycle showed:

| Provider / beneficiary | Initially funded reserve | Reserve after callback | Debt after callback |
| --- | ---: | ---: | ---: |
| Lasna system / subscriber | 1 lREACT | 0.984822 lREACT (`984822000000000000` wei) | 0 |
| Base proxy / receiver | 0.01 test ETH | 0.0099991394392 ETH (`9999139439200000` wei) | 0 |

The Base reserve deposit is [transaction `0x84e3…f2bb`](https://sepolia.basescan.org/tx/0x84e3325ef6465699b1ec69ddf01f813aa6db8a0d13e6167b8dfe2cc7fa14f2bb). Recipient contract balances are separate from provider reserves; the [official Omni economy guide](https://dev.reactive.network/economy) describes this accounting and proxy overhead.

Before deployment, `cast estimate --create` returned **153,555 gas** for the emitter, **1,100,520 gas** for the subscriber, and **576,344 gas** for the receiver using compiled init code and nonzero constructor addresses. The Lasna system reported `_gasPriceCoeffPer1000=1000`, `_extraGas=100000`, `_maxChargeGas=50000`; Base proxy reported `1100`, `80000`, `50000`. The requested 300,000 callback gas budget allowed for proxy overhead. Actual successful smoke transaction gas usage is above. Wallet balances were not treated as contract reserves.

## Issues resolved and stop point

The first subscriber incorrectly required Base receiver code to exist on Lasna, so wiring reverted before broadcast. Its and the first Base receiver's receipts are preserved in `deployments/stage-1-invalid-crosschain-check.json`; neither was funded or used for the trigger. The check was removed, a regression test added, and corrected contracts deployed while reusing the emitter. The deployment script gained a read-only wiring preflight and resumable state handling. Its final numeric parsing was corrected after `cast` appended display hints; `deployments/stage-1.json` was reconciled with live reserve/debt reads.

**No Stage 1 blocker remains. Stop after this smoke test.** The next project stage can implement quote settlement and price logic using these callback integration points, with fresh gas estimates for its own contracts. The frontend remains out of scope.

## Reproducible read-only checks

```powershell
.tools/foundry-v1.9.0/forge.exe build
.tools/foundry-v1.9.0/forge.exe test --summary
.tools/foundry-v1.9.0/cast.exe receipt 0x2fad4897cf447281c1eb7580a0f643d3cbfa04d0eb4ae4aa11e5e17f61ee084b --json --rpc-url https://sepolia.unichain.org
.tools/foundry-v1.9.0/cast.exe receipt 0xc15c2993b133efb7640e59e8a19bf190c66debf15f9fb2b7f115dbabf7019c51 --json --rpc-url https://lasna-rpc.rnk.dev/
.tools/foundry-v1.9.0/cast.exe receipt 0x578d2f31c5ac02fe0d1b78851d86a2a2199d88aa6f9fedf6b801bcb671b6f876 --json --rpc-url https://sepolia.base.org
.tools/foundry-v1.9.0/cast.exe call 0xd23d37E513398F934dA1Df396dfD91018E155cab 'counter()(uint256)' --rpc-url https://sepolia.base.org
```
