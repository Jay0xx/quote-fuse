# Quote Fuse — Stage 0.1 environment and RPC verification

**Date:** 11 November 2026 (Africa/Lagos)
**Scope:** Read-only on-chain checks and local build setup. No signer, deployment, or on-chain write.
**Verdict for Stage 1: PASS.** All required live reads matched expected chain IDs, the deployer had a positive native balance on each chain, both service addresses had bytecode, and the pinned Omni library compiled in Foundry. Balance positivity does **not** establish deployment gas sufficiency; estimate that using Stage 1 contracts.

## Live observations

Wallet queried: `0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf`. `eth_getBalance` used the exact `eth_blockNumber` returned immediately before each read. All values below are observations from the specified official RPCs, not explorer estimates.

| Network / RPC | `eth_chainId` | Pinned `eth_blockNumber` | `eth_getBalance` (wei) | Native balance | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Unichain Sepolia / `https://sepolia.unichain.org` | `0x515` = **1301** | `0x406a924` = **67,545,380** | **7,150,389,252,886,261** (`0x19673dbb6c8ef5`) | **0.007150389252886261 test ETH** | PASS |
| Reactive Lasna / `https://lasna-rpc.rnk.dev/` | `0x512577` = **5,318,007** | `0x7b4e5c` = **8,080,988** | **100,000,000,000,000,000,000** (`0x56bc75e2d63100000`) | **100 lREACT** | PASS |
| Base Sepolia / `https://sepolia.base.org` | `0x14a34` = **84,532** | `0x36b8b9b` = **57,379,739** | **109,706,941,869,761,150** (`0x185c1e1e38aa27e`) | **0.10970694186976115 test ETH** | PASS |

| Provider | Address | Network / pinned block | `eth_getCode` result | Result |
| --- | --- | --- | --- | --- |
| Omni system | `0x8888888888888888888888888888888888888888` | Lasna / 8,080,988 | 239 bytes, prefix `0x60806040525f600b6038565b5f015f9054906101000a900473ffffffffffffff` | PASS: deployed code |
| Callback proxy | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` | Base Sepolia / 57,379,739 | 218 bytes, same prefix | PASS: deployed code |

The address and chain-role assignments match the [official Reactive chain matrix](https://dev.reactive.network/origins-and-destinations) and [Lasna network page](https://dev.reactive.network/reactive-mainnet). Stage 0 documented the [subscription and callback interfaces](stage-0-feasibility-report.md); those findings were reused. Bytecode presence confirms deployment at the addresses, not a live end-to-end callback.

## Build environment

The intended folder is `quote-fuse` within this workspace. It initially contained only `docs/`, so I added a minimal `foundry.toml`, `.gitignore`, and `src/OmniCompileProbe.sol`. The probe imports the official Omni reactive and callback bases and compiles the typed callback request and both receiver authentication guards. It is build-only and has not been deployed.

The [official Foundry installation guide](https://www.getfoundry.sh/introduction/installation) says `foundryup` requires Git Bash or WSL on Windows and permits precompiled release binaries as an alternative. I downloaded the official Windows amd64 **v1.9.0** release into project-local `.tools/` and verified its SHA-256 against the release `.sha256` file. `.tools/` is gitignored.

| Tool | Version | Build commit |
| --- | --- | --- |
| forge | 1.9.0 | `6056c5845d34205a83cf7108042adb137325c9df` |
| cast | 1.9.0 | same |
| anvil | 1.9.0 | same |

Official dependency: [`Reactive-Network/reactive-lib-omni`](https://github.com/Reactive-Network/reactive-lib-omni), **tag `v0.1.0`**, exact commit **`3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8`**. The checkout is in `lib/reactive-lib-omni`, and `foundry.toml` pins Solidity **0.8.29**. `forge build` compiled 9 files with Solc 0.8.29 and ended **`Compiler run successful!`**. A nonfatal warning said the Foundry signature cache file under the user profile did not yet exist.

## Commands and relevant outputs

No credentials were supplied or printed. The read-only RPC sequence was executed against each URL using PowerShell `Invoke-RestMethod` with JSON-RPC 2.0 bodies:

```powershell
$addr = '0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$rpc = 'https://sepolia.unichain.org' # then Lasna and Base URLs above
function Rpc($method, $params) {
  $body = @{jsonrpc='2.0'; id=1; method=$method; params=$params} | ConvertTo-Json -Compress -Depth 5
  (Invoke-RestMethod -Uri $rpc -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20).result
}
$chain = Rpc 'eth_chainId' @()
$block = Rpc 'eth_blockNumber' @()
$balance = Rpc 'eth_getBalance' @($addr, $block)
$code = Rpc 'eth_getCode' @('0x8888888888888888888888888888888888888888', $block) # Lasna
$code = Rpc 'eth_getCode' @('0x476F44b11F5C942c58f4c8E3d0300E5710743585', $block) # Base
```

The prior single-command Unichain check also returned `{"jsonrpc":"2.0","result":"0x515","id":1}`. All Stage 0.1 RPC calls succeeded; **no live RPC errors** occurred.

```powershell
# Official v1.9.0 Windows amd64 release files downloaded from foundry-rs/foundry.
Get-FileHash .tools/foundry_v1.9.0_win32_amd64.zip -Algorithm SHA256
# 2B02444D46C9218FE2E6BE66015265CE131FE6B7C384E33E630B00F9A0BFF072
# Matches foundry_v1.9.0_win32_amd64.sha256.
git clone --depth 1 --branch v0.1.0 https://github.com/Reactive-Network/reactive-lib-omni.git lib/reactive-lib-omni
git -C lib/reactive-lib-omni rev-parse HEAD
# 3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8
.tools/foundry-v1.9.0/forge.exe --version
.tools/foundry-v1.9.0/cast.exe --version
.tools/foundry-v1.9.0/anvil.exe --version
.tools/foundry-v1.9.0/forge.exe build
# Compiling 9 files with Solc 0.8.29
# Compiler run successful!
```

## Next action and stop point

Stage 1 can begin with implementation of the one-event, one-Lasna-reaction, one-authenticated-Base-counter smoke test. Before broadcasting Stage 1 deployments, estimate gas and execution reserve needs against the compiled deployment contracts, fund the contract reserves separately from the deployer wallet, and capture the three required transaction hashes. **No Stage 1 work was done here.**
