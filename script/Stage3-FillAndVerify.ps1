param([string]$Account = 'quote-fuse-testnet')
$ErrorActionPreference='Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$cast=Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$base='https://sepolia.base.org';$uni='https://sepolia.unichain.org'
$expected='0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$path='deployments/stage-3.json';$s=Get-Content $path -Raw|ConvertFrom-Json
foreach($name in @('freshSignature','freshTakerAmount','freshVersion','staleRevertData')){if(-not $s.demo.PSObject.Properties[$name]){$s.demo|Add-Member -NotePropertyName $name -NotePropertyValue $null}}
if(((& $cast wallet address --account $Account).Trim()) -ine $expected){throw 'Signer mismatch.'}
if(-not $s.demo.qualifyingSwapTx -or -not $s.demo.lasnaReactionTx -or -not $s.demo.baseVersionTx){throw 'Linked three-chain receipts not yet verified.'}
function Save {$s|ConvertTo-Json -Depth 10|Set-Content $path}
function Number($address,$signature,$rpc,$arguments){
    $v=& $cast call $address $signature @arguments --rpc-url $rpc
    if($LASTEXITCODE -ne 0){throw "Read failed: $signature"}
    $first=($v -split '\s+')[0]
    if($first -eq 'true'){return [bigint]1}
    if($first -eq 'false'){return [bigint]0}
    return [bigint]$first
}
function SendFill($settlement,$tuple,$signature){
    $r=& $cast send $s.base.taker 'fill(address,(address,address,address,address,uint256,uint256,uint256,uint256,uint256),bytes)' $settlement $tuple $signature --rpc-url $base --account $Account --json|ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or $r.status -ne '0x1'){throw "Fill failed: settlement=$settlement; inspect receipt before retrying."}
    return $r.transactionHash
}
$version=Number $s.base.protected 'quoteVersion()(uint256)' $base @()
if($version -lt 1){throw 'Protected version has not advanced.'}
$body=@{jsonrpc='2.0';id=1;method='eth_getBlockByNumber';params=@('latest',$false)}|ConvertTo-Json -Compress
$block=(Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json' -Body $body).result
$now=[Convert]::ToInt64($block.timestamp.Substring(2),16)
if($now -ge [int64]$s.demo.expiry){throw 'Old quotes expired; do not claim stale-version evidence.'}
$old="($expected,$($s.base.taker),$($s.base.tokenA),$($s.base.tokenB),$($s.demo.makerAmount),$($s.demo.initialTakerAmount),$($s.demo.expiry),1,0)"
if(-not $s.demo.controlFillTx){
    if((Number $s.base.control 'nonceUsed(uint256)(bool)' $base @(1)) -ne 0){throw 'Control nonce already used; inspect receipt before retrying.'}
    $s.demo.controlFillTx=SendFill $s.base.control $old $s.demo.controlSignature;Save
    Write-Output "Control fill: $($s.demo.controlFillTx)"
}
$controlReceipt=& $cast receipt $s.demo.controlFillTx --json --rpc-url $base|ConvertFrom-Json
if($controlReceipt.status -ne '0x1' -or (Number $s.base.control 'nonceUsed(uint256)(bool)' $base @(1)) -ne 1){throw 'Control fill receipt or nonce invalid.'}
if((Number $s.base.protected 'nonceUsed(uint256)(bool)' $base @(1)) -ne 0){throw 'Protected old nonce unexpectedly used.'}
$data=(& $cast calldata 'fill(address,(address,address,address,address,uint256,uint256,uint256,uint256,uint256),bytes)' $s.base.protected $old $s.demo.protectedSignature).Trim()
$request=@{jsonrpc='2.0';id=1;method='eth_call';params=@(@{from=$expected;to=$s.base.taker;data=$data},'latest')}|ConvertTo-Json -Compress -Depth 8
$reply=Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json' -Body $request
$revert=$reply.error.data
if($revert -is [pscustomobject]){$revert=$revert.data}
$selector=(& $cast sig 'StaleQuoteVersion(uint256,uint256)').Trim()
if(-not $revert -or -not $revert.StartsWith($selector,[StringComparison]::OrdinalIgnoreCase) -or $revert.Length -ne 138){throw "Expected StaleQuoteVersion revert, got: $($reply|ConvertTo-Json -Compress -Depth 8)"}
$signed=[bigint]::Parse(('0'+$revert.Substring(10,64)),[System.Globalization.NumberStyles]::AllowHexSpecifier)
$current=[bigint]::Parse(('0'+$revert.Substring(74,64)),[System.Globalization.NumberStyles]::AllowHexSpecifier)
if($signed -ne 0 -or $current -ne $version){throw "Unexpected stale revert arguments: signed=$signed current=$current"}
$s.demo.staleRevertData=$revert;Save
Write-Output "Unexpired protected quote rejected: StaleQuoteVersion($signed,$current), Base timestamp=$now expiry=$($s.demo.expiry)"
$r0=Number $s.source.pool 'reserve0()(uint112)' $uni @()
$r1=Number $s.source.pool 'reserve1()(uint112)' $uni @()
$unit=[bigint]::Parse('1000000000000000000')
$newReference=[bigint]::Divide(($r1*$unit),$r0)
$newAmount=[bigint]::Divide(([bigint]$s.demo.makerAmount*$newReference),$unit)
if($newAmount -eq [bigint]$s.demo.initialTakerAmount){throw 'Fresh quote does not reflect the new pool price.'}
$fresh="($expected,$($s.base.taker),$($s.base.tokenA),$($s.base.tokenB),$($s.demo.makerAmount),$newAmount,$($s.demo.expiry),2,$version)"
if(-not $s.demo.freshSignature){
    $digest=(& $cast call $s.base.protected 'hashQuote((address,address,address,address,uint256,uint256,uint256,uint256,uint256))(bytes32)' $fresh --rpc-url $base).Trim()
    if($LASTEXITCODE -ne 0){throw 'Fresh quote hash failed.'}
    $s.demo.freshSignature=(& $cast wallet sign $digest --no-hash --account $Account).Trim();Save
}
if(-not $s.demo.freshFillTx){
    if((Number $s.base.protected 'nonceUsed(uint256)(bool)' $base @(2)) -ne 0){throw 'Fresh nonce already used; inspect receipt before retrying.'}
    & $cast call $s.base.taker 'fill(address,(address,address,address,address,uint256,uint256,uint256,uint256,uint256),bytes)' $s.base.protected $fresh $s.demo.freshSignature --from $expected --rpc-url $base|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Fresh quote not fillable in eth_call.'}
    $s.demo.freshFillTx=SendFill $s.base.protected $fresh $s.demo.freshSignature;Save
    Write-Output "Fresh protected fill: $($s.demo.freshFillTx)"
}
$freshReceipt=& $cast receipt $s.demo.freshFillTx --json --rpc-url $base|ConvertFrom-Json
if($freshReceipt.status -ne '0x1' -or (Number $s.base.protected 'nonceUsed(uint256)(bool)' $base @(2)) -ne 1){throw 'Fresh fill receipt or nonce invalid.'}
$s.demo.freshTakerAmount=$newAmount.ToString();$s.demo.freshVersion=$version.ToString();Save
Write-Output "Stage 3 fill proof complete: control=$($s.demo.controlFillTx) stale=$selector fresh=$($s.demo.freshFillTx) freshTakerAmount=$newAmount version=$version"
