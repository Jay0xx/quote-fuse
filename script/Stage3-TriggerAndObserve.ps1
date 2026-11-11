param([string]$Account = 'quote-fuse-testnet')
$ErrorActionPreference='Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$cast=Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$uni='https://sepolia.unichain.org';$lasna='https://lasna-rpc.rnk.dev/';$base='https://sepolia.base.org'
$expected='0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$path='deployments/stage-3.json';$s=Get-Content $path -Raw|ConvertFrom-Json
if(-not $s.demo.controlSignature -or -not $s.demo.protectedSignature){throw 'Sign and simulate both quotes before the source swap.'}
if(-not $s.base.reserveFunded -or -not $s.lasna.reserveFunded){throw 'Execution reserves not verified.'}
if(((& $cast wallet address --account $Account).Trim()) -ine $expected){throw 'Signer mismatch.'}
function Save {$s|ConvertTo-Json -Depth 10|Set-Content $path}
function Rpc($url,$method,$params){
    $body=@{jsonrpc='2.0';id=1;method=$method;params=$params}|ConvertTo-Json -Compress -Depth 6
    $r=Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 15
    if($r.error){throw "RPC $method failed: $($r.error.message)"}
    return $r.result
}
function FindRecentLog($url,$address,$topic){
    $latest=Rpc $url 'eth_blockNumber' @();$last=[Convert]::ToInt64($latest.Substring(2),16)
    $from='0x'+[Convert]::ToString([Math]::Max(0,$last-199),16)
    $logs=Rpc $url 'eth_getLogs' @(@{fromBlock=$from;toBlock=$latest;address=$address;topics=@($topic)})
    return @($logs|Sort-Object {[Convert]::ToInt64($_.blockNumber.Substring(2),16)} -Descending)[0]
}
$unit=[bigint]::Parse('1000000000000000000');$amountIn=([bigint]::Multiply(20,$unit)).ToString()
$r0=[bigint](((& $cast call $s.source.pool 'reserve0()(uint112)' --rpc-url $uni)-split '\s+')[0])
$r1=[bigint](((& $cast call $s.source.pool 'reserve1()(uint112)' --rpc-url $uni)-split '\s+')[0])
$oldPrice=[bigint](((& $cast call $s.lasna.subscriber 'acceptedReference()(uint256)' --rpc-url $lasna)-split '\s+')[0])
$requested=[bigint](((& $cast call $s.lasna.subscriber 'latestVersionRequested()(uint256)' --rpc-url $lasna)-split '\s+')[0])
$applied=[bigint](((& $cast call $s.base.protected 'quoteVersion()(uint256)' --rpc-url $base)-split '\s+')[0])
if(-not $s.demo.qualifyingSwapTx){
    if($requested -ne 0 -or $applied -ne 0){throw 'Version already changed; inspect state before firing.'}
    $out=[bigint]::Divide(($r1*[bigint]$amountIn),($r0+[bigint]$amountIn))
    $newPrice=[bigint]::Divide((($r1-$out)*$unit),($r0+[bigint]$amountIn))
    $move=[bigint]::Abs($newPrice-$oldPrice)
    if($move*10000 -lt $oldPrice*300){throw 'Planned 20-token swap does not cross 300 bps.'}
    $receipt=& $cast send $s.source.pool 'swapExact0For1(uint256,uint256)' $amountIn 1 --rpc-url $uni --account $Account --json|ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or $receipt.status -ne '0x1'){throw 'Swap failed. Inspect receipt; do not retry blindly.'}
    $s.demo.qualifyingSwapTx=$receipt.transactionHash
    $s.demo.sourceSeenUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $s.demo.pollIntervalMs=1000
    Save
    Write-Output "Source swap seen: $($s.demo.qualifyingSwapTx) at $($s.demo.sourceSeenUtc)"
}
$syncTopic=(& $cast keccak 'Sync(uint112,uint112)').Trim()
$swapReceipt=Rpc $uni 'eth_getTransactionReceipt' @($s.demo.qualifyingSwapTx)
$sync=@($swapReceipt.logs|Where-Object{$_.address -ieq $s.source.pool -and $_.topics[0] -ieq $syncTopic})
if($swapReceipt.status -ne '0x1' -or $sync.Count -ne 1){throw 'Source receipt does not contain one verified Sync event.'}
$newR0=((& $cast call $s.source.pool 'reserve0()(uint112)' --rpc-url $uni)-split '\s+')[0]
$newR1=((& $cast call $s.source.pool 'reserve1()(uint112)' --rpc-url $uni)-split '\s+')[0]
$encoded=(& $cast abi-encode 'f(uint112,uint112)' $newR0 $newR1).Trim()
if($sync[0].data -ine $encoded){throw 'Swap Sync data differs from pool state.'}
$reactTopic=(& $cast keccak 'ReferenceAccepted(uint256,uint256,uint256,uint256,uint256)').Trim()
$baseTopic=(& $cast keccak 'VersionAdvanced(uint256,uint256)').Trim()
for($i=0;$i -lt 300 -and -not $s.demo.lasnaReactionTx;$i++){
    $version=[bigint](((& $cast call $s.lasna.subscriber 'latestVersionRequested()(uint256)' --rpc-url $lasna)-split '\s+')[0])
    if($version -ge 1){
        $log=FindRecentLog $lasna $s.lasna.subscriber $reactTopic
        if($log){$s.demo.lasnaReactionTx=$log.transactionHash;$s.demo.lasnaSeenUtc=[DateTimeOffset]::UtcNow.ToString('o');Save;Write-Output "Lasna reaction seen: $($s.demo.lasnaReactionTx) at $($s.demo.lasnaSeenUtc)";break}
    }
    Start-Sleep -Milliseconds 1000
}
if(-not $s.demo.lasnaReactionTx){throw 'Lasna reaction not observed in 5 minutes. Inspect subscription and reserves before retrying.'}
for($i=0;$i -lt 300 -and -not $s.demo.baseVersionTx;$i++){
    $version=[bigint](((& $cast call $s.base.protected 'quoteVersion()(uint256)' --rpc-url $base)-split '\s+')[0])
    if($version -ge 1){
        $log=FindRecentLog $base $s.base.protected $baseTopic
        if($log){$s.demo.baseVersionTx=$log.transactionHash;$s.demo.baseSeenUtc=[DateTimeOffset]::UtcNow.ToString('o');Save;Write-Output "Base version update seen: $($s.demo.baseVersionTx) at $($s.demo.baseSeenUtc)";break}
    }
    Start-Sleep -Milliseconds 1000
}
if(-not $s.demo.baseVersionTx){throw 'Base callback not observed in 5 minutes. Inspect callback request and destination reserves; do not retry source swap.'}
if($s.demo.sourceSeenUtc -and $s.demo.baseSeenUtc){$latency=([DateTimeOffset]::Parse($s.demo.baseSeenUtc)-[DateTimeOffset]::Parse($s.demo.sourceSeenUtc)).TotalSeconds;$s.demo.observedLatencyMs=$latency*1000;Save;Write-Output "Observed source-to-Base receipt latency: $latency seconds (1000 ms polling; one observer clock)."}
