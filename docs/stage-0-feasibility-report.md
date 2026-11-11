# Quote Fuse — Stage 0 technical feasibility audit

**Date:** 11 November 2026 (Africa/Lagos)
**Scope:** Read-only inspection and network queries. No signing, deployment, or on-chain write was performed.
**Verdict for starting Stage 1: BLOCKED.** The current shell cannot open outbound RPC sockets, so none of the three live RPC reads, wallet balances, or contract bytecode checks could be verified. Foundry is also absent. The documented integration path is coherent, but the stated PASS gate has not been met.

## Environment and observed checks

| Check | Status | Observation |
| --- | --- | --- |
| Repository and Foundry | **FAIL** | The supplied working directory contains only `work/` and `outputs/`; no Foundry project, contracts, `foundry.toml`, or dependency lock is present. `forge`, `cast`, `anvil`, and `solc` are not on `PATH`, so versions cannot be reported. Stage 1 needs a Foundry installation/project and the current [`reactive-lib-omni`](https://github.com/Reactive-Network/reactive-lib-omni) dependency (Solidity `^0.8.29` in official source). |
| Unichain Sepolia RPC, chain 1301 | **UNVERIFIED** | `https://sepolia.unichain.org` and alternative `https://unichain-sepolia-rpc.publicnode.com` both failed before a JSON-RPC response: socket access forbidden. Latest block and deployer balance unavailable. |
| Reactive Lasna RPC, chain 5318007 | **UNVERIFIED** | Official `https://lasna-rpc.rnk.dev/` failed with the same socket error. Latest block and deployer balance unavailable. |
| Base Sepolia RPC, chain 84532 | **UNVERIFIED** | `https://sepolia.base.org` and alternative `https://base-sepolia-rpc.publicnode.com` failed with the same socket error. Latest block and deployer balance unavailable. |
| Origin/destination support | **PASS (documentation)** | The [official chain matrix](https://dev.reactive.network/origins-and-destinations) marks Unichain Sepolia (1301) as an origin and Base Sepolia (84532) as a destination. It lists Lasna (5318007). This confirms advertised support, not operational delivery. |
| Lasna system and Base proxy addresses | **PASS (documentation); UNVERIFIED (bytecode)** | Official docs identify the Omni Lasna system contract as `0x8888888888888888888888888888888888888888` and the Base Sepolia callback proxy as `0x476F44b11F5C942c58f4c8E3d0300E5710743585`. `eth_getCode` could not run, so deployment at either address is unverified. [Lasna details](https://dev.reactive.network/reactive-mainnet), [chain matrix](https://dev.reactive.network/origins-and-destinations). |
| Omni interfaces and receiver authentication | **PASS (official docs/source)** | See below. |
| Funding and execution reserves | **PASS (documented method); UNVERIFIED (live balances/sufficiency)** | See below. No Quote Fuse contracts exist in this directory, so their balances, reserves, debt, and gas needs cannot yet be measured. |

The funded testnet deployer address to check is `0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf`. **No balance value or block number was observed on any network.** “Funded” is the supplied description, not a verified result. No credential was used or exposed.

## Current Omni integration points

The current [Reactive Contracts guide](https://dev.reactive.network/reactive-contracts) and official [`ISystemContract`](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/interfaces/ISystemContract.sol), [`AbstractReactive`](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractReactive.sol), and [`AbstractCallback`](https://github.com/Reactive-Network/reactive-lib-omni/blob/master/src/base/AbstractCallback.sol) establish:

- Subscribe with `SYSTEM.subscribe(uint256 chainId_, address contract_, uint256 topic0_, uint256 topic1_, uint256 topic2_, uint256 topic3_)` on Lasna. `SYSTEM` is `0x8888888888888888888888888888888888888888`; unused topics use `REACTIVE_IGNORE`. `react(LogRecord memory log_) external onlySystem` authenticates event delivery from the system contract. Filter the origin chain, pool address, topic, and log shape in application logic as well.
- Request the Base callback with `SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0({chainId: 84532, recipient: baseReceiver, gasLimit: ..., payload: ...}))`. The generic `requestCallback(version, bytes)` also exists. Reserve the **first callback argument** as `address(0)` in the encoded payload; the network replaces it with the requesting Lasna contract address. The old `emit Callback(...)` path is deprecated for new Omni contracts.
- The Base receiver should inherit `AbstractCallback(baseProxy, lasnaSubscriber)` and guard its callback method with **both** `onlyServiceProvider` (checks `msg.sender` equals the Base proxy) and `onlyCallbackSender(reactive_)` (checks the injected first argument equals the specific Lasna contract). The [official receiver guide](https://dev.reactive.network/callback-contracts) explains that either check alone permits a forgery path. Both constructor values are immutable, so deploy Lasna first, Base receiver second, then set the receiver on Lasna through an owner-gated setter.
- Do not use legacy `reactive-lib`/ReactVM examples as the Stage 1 interface: the [Omni migration guide](https://dev.reactive.network/) replaces `vmOnly`, the old `0x...fffFfF` service address, and callback events for new contracts.

## Funding and reserve inspection for Stage 1

The [official economy guide](https://dev.reactive.network/economy) distinguishes three values per deployed contract: its own native-token balance; fee reserves held by its service provider; and debt owed to that provider. The deployer wallet's balances are separate and do not fund either contract automatically.

For the Lasna subscriber, fund lREACT through a payable deployment/direct transfer or `depositTo(address)` on the Lasna system contract. Read its wallet/contract balance with `eth_getBalance`, and its `reserves(address)` and `debt(address)` from `0x8888888888888888888888888888888888888888`. For the Base receiver, fund test ETH through payable deployment/direct transfer or `depositTo(address)` on the Base callback proxy, and read the same three values there. `depositTo` clears debt before crediting reserves; a direct transfer only changes contract balance. A contract with debt stops receiving execution. Read `_gasPriceCoeffPer1000()`, `_extraGas()`, and `_maxChargeGas()` on each provider and estimate actual gas after compilation; the Base callback must allow proxy overhead and at least the documented 100,000 gas minimum. **Gas sufficiency remains unverified.**

## Commands run and relevant outputs

All attempted on-chain operations were read-only. No signer or private key was requested. The RPC hosts below are public; there are no credentials to redact.

```powershell
Get-ChildItem -Force | Select-Object Name,Mode,Length
Get-Command forge,cast,anvil,solc -ErrorAction SilentlyContinue
# Result: only work/ and outputs/; no matching Foundry/solc commands.

$body='{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
Invoke-RestMethod -Uri https://sepolia.unichain.org -Method Post -ContentType application/json -Body $body
Invoke-RestMethod -Uri https://unichain-sepolia-rpc.publicnode.com -Method Post -ContentType application/json -Body $body
Invoke-RestMethod -Uri https://lasna-rpc.rnk.dev/ -Method Post -ContentType application/json -Body $body
Invoke-RestMethod -Uri https://sepolia.base.org -Method Post -ContentType application/json -Body $body
Invoke-RestMethod -Uri https://base-sepolia-rpc.publicnode.com -Method Post -ContentType application/json -Body $body
# Each: "An attempt was made to access a socket in a way forbidden by its access permissions. (<host>:443)"
```

Because `eth_chainId` never returned, no `eth_blockNumber`, block-pinned `eth_getBalance`, `eth_getCode`, or `eth_call` result could be obtained. Claiming a block, balance, or bytecode result from a block explorer would misstate the required live RPC verification.

## Blockers, assumptions, and exact next action

1. **Live path blocker:** enable outbound HTTPS JSON-RPC from the execution environment, or run the read-only checks in an environment that permits it. Retry the three official endpoints above; for each, capture `eth_chainId`, `eth_blockNumber`, `eth_getBalance(deployer, blockNumber)`, and `eth_getCode` at the same explicit block for the Lasna system/Base proxy. Confirm expected IDs, nonzero bytecode, and positive deployer balances. Record raw wei and converted native units plus block number.
2. **Build blocker:** locate or initialize the intended Quote Fuse repository, install Foundry, and add/pin `Reactive-Network/reactive-lib-omni`; report `forge --version`, `cast --version`, and `anvil --version`. The current directory is an audit workspace, not an existing contract repo.
3. **Unresolved assumptions:** the listed public RPCs may be healthy despite this environment's socket denial; wallet balances and contract code are unknown; the reference pool/event ABI, deployment addresses, fee settings, and execution gas are not established.

**Stop point:** Stage 0 ends here. Stage 1 deployment and the one-event/one-reaction/one-authenticated-callback acceptance test remain untouched.
