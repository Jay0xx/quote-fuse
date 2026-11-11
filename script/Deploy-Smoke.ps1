param([Parameter(Mandatory=$true)][string]$Account)
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$forge = Join-Path (Get-Location) '.tools/foundry-v1.9.0/forge.exe'
$cast = Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$expected = '0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$uni = 'https://sepolia.unichain.org'
$lasna = 'https://lasna-rpc.rnk.dev/'
$base = 'https://sepolia.base.org'
$system = '0x8888888888888888888888888888888888888888'
$proxy = '0x476F44b11F5C942c58f4c8E3d0300E5710743585'
$statePath = 'deployments/stage-1.json'
$signer = (& $cast wallet address --account $Account).Trim()
if ($LASTEXITCODE -ne 0 -or $signer -ine $expected) { throw "Configured signer address does not match expected deployer." }
foreach ($item in @(@($uni,'1301'),@($lasna,'5318007'),@($base,'84532'))) {
    $actual = (& $cast chain-id --rpc-url $item[0]).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $item[1]) { throw "Chain ID mismatch for $($item[0]): $actual" }
}
& $forge build | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
New-Item -ItemType Directory -Force 'deployments' | Out-Null
if (Test-Path $statePath) {
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    if ($state.deployer -ine $signer) { throw 'Deployment state has a different deployer.' }
} else {
    $state = [ordered]@{deployer=$signer; emitter=$null; subscriber=$null; receiver=$null; emitterTx=$null; subscriberTx=$null; receiverTx=$null; wired=$false; funded=$false}
}
function Save-State { $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath }
Save-State
if ($state.emitter) {
    $code = & $cast code $state.emitter --rpc-url $uni
    if ($LASTEXITCODE -ne 0 -or $code.Length -le 2) { throw 'Recorded emitter has no verified code.' }
} else {
    $created = (& $forge create src/SmokeEmitter.sol:SmokeEmitter --rpc-url $uni --account $Account --broadcast --json | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or -not $created.deployedTo) { throw 'Emitter deployment failed. Inspect receipts before retrying.' }
    $state.emitter=$created.deployedTo; $state.emitterTx=$created.transactionHash; Save-State
}
if ($state.subscriber) {
    $code = & $cast code $state.subscriber --rpc-url $lasna
    $actualEmitter = & $cast call $state.subscriber 'emitter()(address)' --rpc-url $lasna
    if ($LASTEXITCODE -ne 0 -or $code.Length -le 2 -or $actualEmitter.Trim() -ine $state.emitter) { throw 'Recorded subscriber code/emitter mismatch.' }
} else {
    $created = (& $forge create src/SmokeSubscriber.sol:SmokeSubscriber --rpc-url $lasna --account $Account --broadcast --json --constructor-args $state.emitter | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or -not $created.deployedTo) { throw 'Subscriber deployment failed. Inspect receipts before retrying.' }
    $state.subscriber=$created.deployedTo; $state.subscriberTx=$created.transactionHash; Save-State
}
if ($state.receiver) {
    $code = & $cast code $state.receiver --rpc-url $base
    $actualSender = & $cast call $state.receiver '_CALLBACK_SENDER()(address)' --rpc-url $base
    if ($LASTEXITCODE -ne 0 -or $code.Length -le 2 -or $actualSender.Trim() -ine $state.subscriber) { throw 'Recorded receiver code/sender mismatch.' }
} else {
    Write-Output "Deploying Base receiver for subscriber $($state.subscriber). This step may prompt for the local keystore password."
    $priorErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $forgeOutput = & $forge create src/SmokeReceiver.sol:SmokeReceiver --rpc-url $base --account $Account --broadcast --json --constructor-args $proxy $state.subscriber 2>&1
    $forgeExit = $LASTEXITCODE
    $ErrorActionPreference = $priorErrorActionPreference
    if ($forgeExit -ne 0) { throw "Receiver deployment command exited $forgeExit. Forge output: $($forgeOutput -join ' ')" }
    try { $created = $forgeOutput | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Receiver deployment output was not valid JSON: $($forgeOutput -join ' ')" }
    if (-not $created.deployedTo) { throw "Receiver deployment returned no address. Inspect Base nonce and receipts. Forge output: $($forgeOutput -join ' ')" }
    $state.receiver=$created.deployedTo; $state.receiverTx=$created.transactionHash; Save-State
}
$actualReceiver = (& $cast call $state.subscriber 'receiver()(address)' --rpc-url $lasna).Trim()
if ($actualReceiver -ieq '0x0000000000000000000000000000000000000000') {
    # Read-only eth_call catches constructor/wiring mistakes before a signed transaction.
    & $cast call $state.subscriber 'setReceiver(address)' $state.receiver --from $signer --rpc-url $lasna | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Read-only wiring preflight reverted. Do not broadcast.' }
    & $cast send $state.subscriber 'setReceiver(address)' $state.receiver --rpc-url $lasna --account $Account | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Wiring failed. Inspect state before retrying.' }
} elseif ($actualReceiver -ine $state.receiver) { throw 'Subscriber is wired to a different receiver.' }
$state.wired=$true; Save-State
$lasnaReserve = ((& $cast call $system 'reserves(address)(uint256)' $state.subscriber --rpc-url $lasna) -split '\s+')[0]
if ([bigint]$lasnaReserve -le 0) {
    & $cast send $system 'depositTo(address)' $state.subscriber --value 1ether --rpc-url $lasna --account $Account | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Lasna reserve deposit failed. Inspect debt and reserves.' }
}
$baseReserve = ((& $cast call $proxy 'reserves(address)(uint256)' $state.receiver --rpc-url $base) -split '\s+')[0]
if ([bigint]$baseReserve -le 0) {
    & $cast send $proxy 'depositTo(address)' $state.receiver --value 0.01ether --rpc-url $base --account $Account | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Base reserve deposit failed. Inspect debt and reserves.' }
}
$lasnaReserve = ((& $cast call $system 'reserves(address)(uint256)' $state.subscriber --rpc-url $lasna) -split '\s+')[0]
$lasnaDebt = ((& $cast call $system 'debt(address)(uint256)' $state.subscriber --rpc-url $lasna) -split '\s+')[0]
$baseReserve = ((& $cast call $proxy 'reserves(address)(uint256)' $state.receiver --rpc-url $base) -split '\s+')[0]
$baseDebt = ((& $cast call $proxy 'debt(address)(uint256)' $state.receiver --rpc-url $base) -split '\s+')[0]
Write-Output "Lasna reserve=$lasnaReserve debt=$lasnaDebt; Base reserve=$baseReserve debt=$baseDebt"
if ([bigint]$lasnaReserve -le 0 -or [bigint]$baseReserve -le 0 -or [bigint]$lasnaDebt -ne 0 -or [bigint]$baseDebt -ne 0) { throw 'Reserve verification failed. Do not trigger.' }
$state.funded=$true; Save-State
Write-Output "Ready to trigger. Deployment state: $statePath"
