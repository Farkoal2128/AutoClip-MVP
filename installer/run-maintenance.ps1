param([string]$BaseRoot,[string]$ReleaseId,[string]$ReceiptPath,[string]$ReceiptSha256,
      [string]$ReceiptHelperSha256,[string]$OwnershipHelperSha256,[string]$UpdaterSha256,
      [string]$BootstrapSha256,[string]$DependencyManifestSha256,
      [string]$ManifestPath,[string]$ManifestSha256,[string]$WheelPath,[string]$WheelSha256,
      [switch]$Rollback,[switch]$NoShortcut)

$ErrorActionPreference='Stop'
$locks=[Collections.Generic.List[IO.FileStream]]::new()
$script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
$transcript=$false;$code=1
try{
    if(!$BaseRoot){$BaseRoot=Join-Path $env:LOCALAPPDATA 'AutoClip'}
    $base=[IO.Path]::GetFullPath($BaseRoot).TrimEnd('\');$setup=Join-Path $base 'Setup'
    if($ReleaseId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$'){throw 'Invalid maintenance release identifier.'}
    # The compiled caller holds and hashes this helper before executing it.
    # Protect the library before importing any functions from it.
    $receiptHelper=Join-Path $setup 'write-setup-receipt.ps1'
    $initial=[IO.File]::Open($receiptHelper,'Open','Read','Read');$locks.Add($initial)
    if($ReceiptHelperSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $receiptHelper).Hash.ToLowerInvariant() -cne $ReceiptHelperSha256){throw 'Receipt helper SHA256 differs.'}
    . $receiptHelper
    $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    Assert-SetupReceiptPath $base|Out-Null;Assert-SetupReceiptPath $setup -Protected|Out-Null
    $root=Assert-SetupReceiptPath (Join-Path $base $ReleaseId) -Protected
    $expectedReceipt=Join-Path $setup ('installation-receipts/'+$ReleaseId+'.json')
    if($ReceiptPath -ine $expectedReceipt){throw 'Maintenance receipt is outside the fixed installed scope.'}
    $receiptFile=Get-SetupReceiptFile $ReceiptPath $ReceiptSha256
    $anchor=Get-SetupReceiptFile ($ReceiptPath -replace '\.json$','.sha256')
    if([IO.File]::ReadAllText($anchor.path) -cne $receiptFile.sha256){throw 'Maintenance receipt anchor differs.'}
    $receipt=Read-SetupReceiptJson $receiptFile
    $fields=@('schema_version','status','context','setup_root','setup_sha256','source_handoff','app_health','release_files','release_directories','setup_files','shortcuts','registration')
    if($receipt.schema_version -eq 2){$fields+='base_files'}
    if($receipt.schema_version -cnotin @(1,2) -or @($receipt.PSObject.Properties).Count -ne $fields.Count -or @($receipt.PSObject.Properties.Name|Where-Object{$_ -cnotin $fields}).Count -or $receipt.status -cne 'COMPLETE' -or $receipt.setup_root -ine $setup){throw 'Unsupported complete maintenance receipt.'}
    $context=@{};foreach($property in $receipt.context.PSObject.Properties){if($property.Name -cne 'recipient_sid'){$context[$property.Name]=$property.Value}}
    $identity=Get-SetupReceiptContext $context;Test-SetupReceiptIdentity $receipt.context $identity
    if($identity.install_root -ine $root -or $identity.release_id -cne $ReleaseId -or $identity.bootstrap_sha256 -cne $BootstrapSha256 -or $identity.dependency_manifest_sha256 -cne $DependencyManifestSha256){throw 'Installed maintenance provenance differs.'}
    foreach($entry in @(@('install.ps1',$BootstrapSha256),@('installer-dependencies-v1.json',$DependencyManifestSha256),@('update-app.ps1',$UpdaterSha256),@('uninstall-owned-release.ps1',$OwnershipHelperSha256))){
        if($entry[1] -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact maintenance input pin required.'}
        Get-SetupReceiptFile (Join-Path $setup $entry[0]) $entry[1]|Out-Null
    }
    # Import only the ownership functions, never the cleanup entry point.
    $ownership=Join-Path $setup 'uninstall-owned-release.ps1'
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($ownership,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Pinned ownership helper does not parse.'}
    foreach($name in @('Test-UninstallRows','Stop-OwnedAutoClip')){
        $nodes=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
        if($nodes.Count -ne 1){throw 'Pinned ownership function is absent or ambiguous.'}
        . ([scriptblock]::Create($nodes[0].Extent.Text))
    }
    Test-UninstallRows $receipt.release_files
    if($Rollback -and ($ManifestPath -or $WheelPath)){throw 'Rollback cannot accept update fixture inputs.'}
    $arguments=@{BaseRoot=$base;NoShortcut=$NoShortcut}
    if($Rollback){$arguments.Rollback=$true}
    if($ManifestPath){Get-SetupReceiptFile $ManifestPath $ManifestSha256|Out-Null;$arguments.ManifestPath=$ManifestPath}
    elseif($ManifestSha256){throw 'Manifest pin requires its exact local file.'}
    if($WheelPath){Get-SetupReceiptFile $WheelPath $WheelSha256|Out-Null;$arguments.WheelPath=$WheelPath}
    elseif($WheelSha256){throw 'Wheel pin requires its exact local file.'}
    # update-app owns the same selection mutex while this callback validates
    # installed bytes, stops only owned AutoClip processes, and activates.
    # Keep the caller scope: GetNewClosure isolates the imported functions.
    $maintenanceRoot=$root;$maintenanceReceipt=$receipt
    $arguments.StopOwnedApp={
        param($SelectedRoot)
        if($SelectedRoot -and $SelectedRoot -ine $maintenanceRoot){throw 'Maintenance selected another runtime; preserved.'}
        Get-SetupReceiptRows $maintenanceReceipt.release_files $maintenanceRoot|Out-Null
        Stop-OwnedAutoClip $maintenanceRoot $maintenanceReceipt.release_files
    }
    $logs=Join-Path $setup 'logs'
    if(![IO.Directory]::Exists($logs)){[IO.Directory]::CreateDirectory($logs,(Get-Acl -LiteralPath $setup))|Out-Null}
    Assert-SetupReceiptPath $logs -Protected|Out-Null
    $log=Join-Path $logs ('maintenance-'+[guid]::NewGuid().ToString('N')+'.txt')
    Start-Transcript -LiteralPath $log -NoClobber|Out-Null;$transcript=$true
    Write-Host ('AutoClip maintenance log: '+$log)
    Write-Host $(if($Rollback){'Verifying the retained app and selecting rollback.'}else{'Verifying the app release; reusing the installed runtime.'})
    $global:LASTEXITCODE=0
    . (Join-Path $setup 'update-app.ps1') @arguments
    $code=[int]$LASTEXITCODE
    if($code -ne 0){throw ('App maintenance worker failed with exit '+$code+'.')}
    Write-Host 'AutoClip maintenance completed.'
}catch{
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine($_.ScriptStackTrace)
}finally{
    if($transcript){Stop-Transcript|Out-Null}
    foreach($held in $script:SetupReceiptLocks){$held.Dispose()}
    foreach($held in $locks){$held.Dispose()}
}
exit $code
