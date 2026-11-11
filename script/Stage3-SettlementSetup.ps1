param([string]$Account = 'quote-fuse-testnet')
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$forge = Join-Path (Get-Location) '.tools/foundry-v1.9.0/forge.exe'
$cast = Join-Path (Get-Location) '.tools/foundry-v1.9.0/cast.exe'
$uni='https://sepolia.unichain.org';$lasna='https://lasna-rpc.rnk.dev/';$base='https://sepolia.base.org'
$expected='0xe87B50D0d9A2Eb84e484D9dfb385e14A366a81bf'
$system='0x8888888888888888888888888888888888888888';$proxy='0x476F44b11F5C942c58f4c8E3d0300E5710743585'
$path='deployments/stage-3.json'
if(-not(Test-Path $path)){throw 'Run Stage3-SourceSetup.ps1 first.'}
$state=Get-Content $path -Raw|ConvertFrom-Json
if(-not $state.source.startingReference){throw 'Source pool and rehearsal event are not verified.'}
if(((& $cast wallet address --account $Account).Trim()) -ine $expected){throw 'Signer mismatch.'}
foreach($n in @(@($uni,'1301'),@($lasna,'5318007'),@($base,'84532'))){
    $observed=$null
    for($attempt=0;$attempt -lt 3;$attempt++){
        $response=& $cast chain-id --rpc-url $n[0]
        if($LASTEXITCODE -eq 0 -and $response){$observed=($response|Select-Object -First 1).Trim();break}
        Start-Sleep -Seconds 1
    }
    if(-not $observed){throw "RPC unavailable after three chain ID reads: $($n[0])"}
    if($observed -ne $n[1]){throw "Chain ID mismatch at $($n[0]): expected $($n[1]), observed $observed"}
}
& $forge build --quiet|Out-Host;if($LASTEXITCODE -ne 0){throw 'Build failed.'}
$unit=[bigint]::Parse('1000000000000000000');$makerTarget=([bigint]::Multiply(300,$unit)).ToString();$takerTarget=([bigint]::Multiply(600,$unit)).ToString()
function Save { $state|ConvertTo-Json -Depth 10|Set-Content $path }
function Send($rpc,$to,$sig,$callArgs,$value=$null){
    $cmd=@($to,$sig)+$callArgs+@('--rpc-url',$rpc,'--account',$Account,'--json')
    if($value){$cmd+=@('--value',$value)}
    $raw=& $cast send @cmd
    $exit=$LASTEXITCODE
    if($exit -ne 0){throw "Transaction failed for $sig before a receipt was returned (cast exit $exit). See Foundry error above."}
    $r=($raw -join "`n")|ConvertFrom-Json
    if($r.status -ne '0x1' -and $r.status -ne 1){throw "Transaction failed for $sig. tx=$($r.transactionHash) status=$($r.status); inspect receipt before retrying."}
    return $r.transactionHash
}
function Deploy($section,$name,$rpc,$contract,$constructorArgs){
    $existing=$state.$section.$name
    if($existing){$code=& $cast code $existing --rpc-url $rpc;if($LASTEXITCODE -ne 0 -or $code.Length -le 2){throw "Recorded $section.$name has no code."};return}
    $cmd=@('create',$contract,'--rpc-url',$rpc,'--account',$Account,'--broadcast','--json')
    if($constructorArgs.Count){$cmd+=@('--constructor-args')+$constructorArgs}
    $r=& $forge @cmd|ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or -not $r.deployedTo){throw "Deployment failed: $section.$name. Inspect nonce and receipts before retrying."}
    $state.$section.$name=$r.deployedTo;Save
}
Deploy 'base' 'tokenA' $base 'src/MockERC20.sol:MockERC20' @('Quote Fuse Settlement A','QSA')
Deploy 'base' 'tokenB' $base 'src/MockERC20.sol:MockERC20' @('Quote Fuse Settlement B','QSB')
Deploy 'base' 'control' $base 'src/QuoteSettlement.sol:QuoteSettlement' @($expected,$state.base.tokenA,$state.base.tokenB,'false')
Deploy 'base' 'protected' $base 'src/QuoteSettlement.sol:QuoteSettlement' @($expected,$state.base.tokenA,$state.base.tokenB,'true')
Deploy 'base' 'taker' $base 'src/DemoTaker.sol:DemoTaker' @()
Deploy 'lasna' 'subscriber' $lasna 'src/PoolPriceSubscriber.sol:PoolPriceSubscriber' @($state.source.pool,$state.source.startingReference,'300')
Deploy 'base' 'receiver' $base 'src/QuoteVersionReceiver.sol:QuoteVersionReceiver' @($proxy,$state.lasna.subscriber,$state.base.protected)
if(((& $cast call $state.base.protected 'versionReceiver()(address)' --rpc-url $base).Trim()) -ieq '0x0000000000000000000000000000000000000000'){
    Send $base $state.base.protected 'setVersionReceiver(address)' @($state.base.receiver)|Out-Host
}
if(((& $cast call $state.base.protected 'versionReceiver()(address)' --rpc-url $base).Trim()) -ine $state.base.receiver){throw 'Protected settlement receiver mismatch.'}
$state.base.receiverWired=$true;Save
if(((& $cast call $state.lasna.subscriber 'receiver()(address)' --rpc-url $lasna).Trim()) -ieq '0x0000000000000000000000000000000000000000'){
    Send $lasna $state.lasna.subscriber 'setReceiver(address)' @($state.base.receiver)|Out-Host
}
if(((& $cast call $state.lasna.subscriber 'receiver()(address)' --rpc-url $lasna).Trim()) -ine $state.base.receiver){throw 'Lasna receiver mismatch.'}
$state.lasna.receiverWired=$true;Save
$lr=[bigint](((& $cast call $system 'reserves(address)(uint256)' $state.lasna.subscriber --rpc-url $lasna)-split '\s+')[0])
if($lr -eq 0){Send $lasna $system 'depositTo(address)' @($state.lasna.subscriber) '1ether'|Out-Host}
$br=[bigint](((& $cast call $proxy 'reserves(address)(uint256)' $state.base.receiver --rpc-url $base)-split '\s+')[0])
if($br -eq 0){Send $base $proxy 'depositTo(address)' @($state.base.receiver) '0.01ether'|Out-Host}
$lr=[bigint](((& $cast call $system 'reserves(address)(uint256)' $state.lasna.subscriber --rpc-url $lasna)-split '\s+')[0])
$ld=[bigint](((& $cast call $system 'debt(address)(uint256)' $state.lasna.subscriber --rpc-url $lasna)-split '\s+')[0])
$br=[bigint](((& $cast call $proxy 'reserves(address)(uint256)' $state.base.receiver --rpc-url $base)-split '\s+')[0])
$bd=[bigint](((& $cast call $proxy 'debt(address)(uint256)' $state.base.receiver --rpc-url $base)-split '\s+')[0])
if($lr -le 0 -or $br -le 0 -or $ld -ne 0 -or $bd -ne 0){throw 'Reserves/debt not ready.'}
$state.lasna.reserveFunded=$true;$state.base.reserveFunded=$true;Save
$makerBalance=[bigint](((& $cast call $state.base.tokenA 'balanceOf(address)(uint256)' $expected --rpc-url $base)-split '\s+')[0])
if($makerBalance -lt [bigint]$makerTarget){Send $base $state.base.tokenA 'mint(address,uint256)' @($expected,$makerTarget)|Out-Host}
$takerBalance=[bigint](((& $cast call $state.base.tokenB 'balanceOf(address)(uint256)' $state.base.taker --rpc-url $base)-split '\s+')[0])
if($takerBalance -lt [bigint]$takerTarget){Send $base $state.base.tokenB 'mint(address,uint256)' @($state.base.taker,$takerTarget)|Out-Host}
foreach($settlement in @($state.base.control,$state.base.protected)){
    $allowance=[bigint](((& $cast call $state.base.tokenA 'allowance(address,address)(uint256)' $expected $settlement --rpc-url $base)-split '\s+')[0])
    if($allowance -lt [bigint]$makerTarget){Send $base $state.base.tokenA 'approve(address,uint256)' @($settlement,$makerTarget)|Out-Host}
    $allowance=[bigint](((& $cast call $state.base.tokenB 'allowance(address,address)(uint256)' $state.base.taker $settlement --rpc-url $base)-split '\s+')[0])
    if($allowance -lt [bigint]$takerTarget){Send $base $state.base.taker 'approveToken(address,address,uint256)' @($state.base.tokenB,$settlement,$takerTarget)|Out-Host}
}
Write-Output "Wired and funded. control=$($state.base.control) protected=$($state.base.protected) taker=$($state.base.taker) subscriber=$($state.lasna.subscriber) receiver=$($state.base.receiver) LasnaReserve=$lr BaseReserve=$br"
