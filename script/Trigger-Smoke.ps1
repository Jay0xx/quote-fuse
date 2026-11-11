param([Parameter(Mandatory=$true)][string]$Account,[Parameter(Mandatory=$true)][string]$RunId)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$cast = Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$expected = '0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$uni = 'https://sepolia.unichain.org'
$lasna = 'https://lasna-rpc.rnk.dev/'
$base = 'https://sepolia.base.org'
$state = Get-Content 'deployments/stage-1.json' -Raw | ConvertFrom-Json
if (-not $state.wired -or -not $state.funded) { throw 'Wiring and reserve funding are not verified.' }
if ($RunId -notmatch '^0x[0-9a-fA-F]{64}$' -or $RunId -eq ('0x' + ('0'*64))) { throw 'RunId must be a nonzero bytes32 hex value.' }
$signer = (& $cast wallet address --account $Account).Trim()
if ($LASTEXITCODE -ne 0 -or $signer -ine $expected) { throw 'Signer mismatch.' }
$processed = (& $cast call $state.receiver 'processed(bytes32)(bool)' $RunId --rpc-url $base).Trim()
if ($processed -ne 'false') { throw 'Run ID already processed or check failed; do not fire another event.' }
$requested = (& $cast call $state.subscriber 'requested(bytes32)(bool)' $RunId --rpc-url $lasna).Trim()
if ($requested -ne 'false') { throw 'Run ID already requested; inspect callback delivery before retrying.' }
$before = (& $cast call $state.receiver 'counter()(uint256)' --rpc-url $base).Trim()
Write-Output "Counter before: $before"
$receipt = & $cast send $state.emitter 'emitSmoke(bytes32)' $RunId --rpc-url $uni --account $Account --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $receipt.transactionHash) { throw 'Trigger submission failed. Inspect emitter receipts before retrying.' }
Write-Output "Unichain trigger: $($receipt.transactionHash)"
Write-Output "Follow this run ID on Lasna and Base before considering any retry: $RunId"
