param([string]$Account = 'quote-fuse-testnet')
$ErrorActionPreference='Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$cast=Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$base='https://sepolia.base.org';$expected='0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$path='deployments/stage-3.json';$s=Get-Content $path -Raw|ConvertFrom-Json
if(-not $s.base.reserveFunded -or -not $s.lasna.reserveFunded -or -not $s.base.receiverWired -or -not $s.lasna.receiverWired){throw 'Wiring and reserves must be verified first.'}
if(((& $cast wallet address --account $Account).Trim()) -ine $expected){throw 'Maker signer mismatch.'}
if(((& $cast call $s.base.protected 'quoteVersion()(uint256)' --rpc-url $base)-split '\s+')[0] -ne '0'){throw 'Protected version is no longer zero.'}
$unit=[bigint]::Parse('1000000000000000000')
if(-not $s.demo.expiry){
    $body=@{jsonrpc='2.0';id=1;method='eth_getBlockByNumber';params=@('latest',$false)}|ConvertTo-Json -Compress
    $block=(Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json' -Body $body).result
    $now=[Convert]::ToInt64($block.timestamp.Substring(2),16)
    $s.demo.expiry=($now + 7*86400).ToString()
    $s.demo.makerAmount=([bigint]::Multiply(100,$unit)).ToString()
    $s.demo.initialTakerAmount=[bigint]::Divide(([bigint]$s.demo.makerAmount * [bigint]$s.source.startingReference),$unit).ToString()
    $s|ConvertTo-Json -Depth 10|Set-Content $path
}
$tuple="($expected,$($s.base.taker),$($s.base.tokenA),$($s.base.tokenB),$($s.demo.makerAmount),$($s.demo.initialTakerAmount),$($s.demo.expiry),1,0)"
function Sign($settlement){
    $digest=(& $cast call $settlement 'hashQuote((address,address,address,address,uint256,uint256,uint256,uint256,uint256))(bytes32)' $tuple --rpc-url $base).Trim()
    if($LASTEXITCODE -ne 0 -or $digest -notmatch '^0x[0-9a-fA-F]{64}$'){throw 'Quote hash failed.'}
    $signature=(& $cast wallet sign $digest --no-hash --account $Account).Trim()
    if($LASTEXITCODE -ne 0 -or $signature -notmatch '^0x[0-9a-fA-F]{130}$'){throw 'Quote signing failed.'}
    return $signature
}
if(-not $s.demo.controlSignature){$s.demo.controlSignature=Sign $s.base.control;$s|ConvertTo-Json -Depth 10|Set-Content $path}
if(-not $s.demo.protectedSignature){$s.demo.protectedSignature=Sign $s.base.protected;$s|ConvertTo-Json -Depth 10|Set-Content $path}
foreach($item in @(@($s.base.control,$s.demo.controlSignature),@($s.base.protected,$s.demo.protectedSignature))){
    & $cast call $s.base.taker 'fill(address,(address,address,address,address,uint256,uint256,uint256,uint256,uint256),bytes)' $item[0] $tuple $item[1] --from $expected --rpc-url $base|Out-Null
    if($LASTEXITCODE -ne 0){throw "Pre-swap fill simulation failed for $($item[0]). No source swap should be triggered."}
}
Write-Output "Both signed quotes are fillable in eth_call before swap. expiry=$($s.demo.expiry) makerAmount=$($s.demo.makerAmount) takerAmount=$($s.demo.initialTakerAmount)"
