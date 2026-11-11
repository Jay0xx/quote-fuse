param([string]$Account = 'quote-fuse-testnet')
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$forge = Join-Path (Get-Location) '.tools/foundry-v1.9.0/forge.exe'
$cast = Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$rpc = 'https://sepolia.unichain.org'
$expected = '0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$path = 'deployments/stage-3.json'
$unit = [bigint]::Parse('1000000000000000000')
$seed = [bigint]::Multiply(1000, $unit).ToString()
$mint = [bigint]::Multiply(1100, $unit).ToString()
if ((& $cast chain-id --rpc-url $rpc).Trim() -ne '1301') { throw 'Wrong Unichain RPC.' }
if ((& $cast wallet address --account $Account).Trim() -ine $expected) { throw 'Signer mismatch.' }
& $forge build | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
if (Test-Path $path) { $state = Get-Content $path -Raw | ConvertFrom-Json }
else { $state = [pscustomobject]@{deployer=$expected; source=[pscustomobject]@{tokenA=$null;tokenB=$null;token0=$null;token1=$null;pool=$null;seedTx=$null;rehearsalTx=$null;startingReference=$null};base=[pscustomobject]@{tokenA=$null;tokenB=$null;control=$null;protected=$null;taker=$null;receiver=$null;receiverWired=$false;reserveFunded=$false};lasna=[pscustomobject]@{subscriber=$null;receiverWired=$false;reserveFunded=$false};demo=[pscustomobject]@{expiry=$null;makerAmount=$null;initialTakerAmount=$null;controlSignature=$null;protectedSignature=$null;qualifyingSwapTx=$null;sourceSeenUtc=$null;pollIntervalMs=$null;lasnaReactionTx=$null;lasnaSeenUtc=$null;baseVersionTx=$null;baseSeenUtc=$null;observedLatencyMs=$null;controlFillTx=$null;freshFillTx=$null;freshSignature=$null;freshTakerAmount=$null;freshVersion=$null;staleRevertData=$null}} }
function Save { $state | ConvertTo-Json -Depth 10 | Set-Content $path }
function Send($to,$sig,$callArgs,$value=$null) {
    $cmd=@($to,$sig)+$callArgs+@('--rpc-url',$rpc,'--account',$Account,'--json')
    if($value){$cmd+=@('--value',$value)}
    $raw=& $cast send @cmd
    $exit=$LASTEXITCODE
    if($exit -ne 0){throw "Transaction failed for $sig before a receipt was returned (cast exit $exit): $($raw -join ' ')"}
    $r=($raw -join "`n") | ConvertFrom-Json
    if($r.status -ne '0x1' -and $r.status -ne 1){throw "Transaction failed for $sig. tx=$($r.transactionHash) status=$($r.status); inspect receipt before retrying."}
    return $r.transactionHash
}
function Deploy($name,$contract,$constructorArgs) {
    $existing=$state.source.$name
    if($existing){$code=& $cast code $existing --rpc-url $rpc;if($LASTEXITCODE -ne 0 -or $code.Length -le 2){throw "Recorded $name has no code."};return}
    $cmd=@('create',$contract,'--rpc-url',$rpc,'--account',$Account,'--broadcast','--json')
    if($constructorArgs.Count){$cmd+=@('--constructor-args')+$constructorArgs}
    $r=& $forge @cmd | ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or -not $r.deployedTo){throw "Deployment failed for $name. Inspect chain before retrying."}
    $state.source.$name=$r.deployedTo;Save
}
Deploy 'tokenA' 'src/MockERC20.sol:MockERC20' @('Quote Fuse Test A','QFA')
Deploy 'tokenB' 'src/MockERC20.sol:MockERC20' @('Quote Fuse Test B','QFB')
foreach($t in @($state.source.tokenA,$state.source.tokenB)) { if(((& $cast call $t 'decimals()(uint8)' --rpc-url $rpc) -split '\s+')[0] -ne '18'){throw "Token $t must have 18 decimals."} }
if([bigint]::Parse(('0'+$state.source.tokenA.Substring(2)),[System.Globalization.NumberStyles]::AllowHexSpecifier) -lt [bigint]::Parse(('0'+$state.source.tokenB.Substring(2)),[System.Globalization.NumberStyles]::AllowHexSpecifier)) {
    $state.source.token0=$state.source.tokenA;$state.source.token1=$state.source.tokenB
} else { $state.source.token0=$state.source.tokenB;$state.source.token1=$state.source.tokenA }
Save
Deploy 'pool' 'src/ControlledPool.sol:ControlledPool' @($state.source.token0,$state.source.token1)
foreach($t in @($state.source.token0,$state.source.token1)) {
    if([bigint](((& $cast call $t 'balanceOf(address)(uint256)' $expected --rpc-url $rpc) -split '\s+')[0]) -lt [bigint]$mint){Send $t 'mint(address,uint256)' @($expected,$mint)|Out-Host}
    Send $t 'approve(address,uint256)' @($state.source.pool,$mint)|Out-Host
}
if(-not $state.source.seedTx){
    $state.source.seedTx=Send $state.source.pool 'seed(uint256,uint256)' @($seed,$seed);Save
}
if(-not $state.source.rehearsalTx){
    $state.source.rehearsalTx=Send $state.source.pool 'swapExact0For1(uint256,uint256)' @($unit.ToString(),'1');Save
}
$receipt=& $cast receipt $state.source.rehearsalTx --json --rpc-url $rpc | ConvertFrom-Json
$topic=(& $cast keccak 'Sync(uint112,uint112)').Trim()
$sync=@($receipt.logs | Where-Object { $_.address -ieq $state.source.pool -and $_.topics[0] -ieq $topic })
if($receipt.status -ne '0x1' -or $sync.Count -ne 1 -or $sync[0].topics.Count -ne 1){throw 'Rehearsal swap receipt has no unique LOG1 Sync event.'}
$r0=((& $cast call $state.source.pool 'reserve0()(uint112)' --rpc-url $rpc) -split '\s+')[0]
$r1=((& $cast call $state.source.pool 'reserve1()(uint112)' --rpc-url $rpc) -split '\s+')[0]
$encoded=(& $cast abi-encode 'f(uint112,uint112)' $r0 $r1).Trim()
if($sync[0].data -ine $encoded){throw 'Sync event data does not match pool reserve state.'}
$state.source.startingReference=[bigint]::Divide(([bigint]$r1 * $unit),[bigint]$r0).ToString();Save
Write-Output "Source pool verified: $($state.source.pool) token0=$($state.source.token0) token1=$($state.source.token1) reserve0=$r0 reserve1=$r1 reference=$($state.source.startingReference) rehearsalTx=$($state.source.rehearsalTx)"
