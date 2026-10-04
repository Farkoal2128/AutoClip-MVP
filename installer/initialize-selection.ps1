param([switch]$PrepareLaunchers,[switch]$Activate,[string]$BaseRoot,[string]$ReleaseId,
      [string]$RequestPath,[string]$RequestSha256,[string]$ReceiptPath,[string]$ReceiptSha256,
      [string]$ReceiptHelperSha256,[string]$UpdaterSha256,
      [switch]$AdmitNativeSetup,[int]$NativePid,[string]$NativeSha256,[string]$OutputPath,[string]$UpdaterPath,
      [string]$NativeSelectionPath,[string]$NativeSelectionSha256)

function Assert-NativeSetupSelection($File,[string]$Base) {
    if($File.bytes -gt 8192){throw 'Native selection proof exceeds bounded size.'}
    Assert-SetupReceiptPath (Split-Path -Parent $File.path) -Protected|Out-Null
    $proof=Read-SetupReceiptJson $File
    $fields=@('schema_version','selection_protocol','nonce','proof_path','base_root','recipient_sid','native_pid','native_start','native_path','native_sha256','source_pid','source_start','source_path','source_sha256')
    if(@($proof.PSObject.Properties).Count -ne $fields.Count -or @($proof.PSObject.Properties.Name|Where-Object{$_ -cnotin $fields}).Count -or $proof.schema_version -ne 1 -or $proof.selection_protocol -cne 'NATIVE_HELD_SELECTION_V1' -or $proof.nonce -cnotmatch '^[a-f0-9]{32}$' -or $proof.proof_path -ine $File.path -or $proof.base_root -ine $Base -or $proof.recipient_sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Invalid native Setup selection proof.'}
    $cursor=Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID);$found=$false
    for($depth=0;$cursor -and $depth -lt 8;$depth++){
        $owner=Invoke-CimMethod -InputObject $cursor -MethodName GetOwnerSid
        if($owner.ReturnValue -ne 0 -or $owner.Sid -cne $proof.recipient_sid){throw 'Native selection descendant owner differs.'}
        if($cursor.ProcessId -eq $proof.native_pid){$found=$true;break}
        $cursor=Get-CimInstance Win32_Process -Filter ('ProcessId='+$cursor.ParentProcessId)
    }
    if(!$found -or $cursor.ParentProcessId -ne $proof.source_pid){throw 'Native selection callback is not an authenticated descendant.'}
    foreach($kind in @('native','source')){
        $live=Get-Process -Id $proof.($kind+'_pid') -ErrorAction Stop
        if($live.Path -ine $proof.($kind+'_path') -or $live.StartTime.ToUniversalTime().ToString('o') -cne $proof.($kind+'_start')){throw 'Native selection process identity changed.'}
        $null=Get-SetupReceiptFile $live.Path $proof.($kind+'_sha256')
    }
    $probe=$null
    try{$probe=Acquire-SelectionMutex $Base}catch{if($_.Exception.Message -cnotlike 'AutoClip selection is busy.*'){throw}}
    if($probe){try{$probe.ReleaseMutex()}finally{$probe.Dispose()};throw 'Native selection proof has no retained owner.'}
    # Busy is only an exclusion check. Authority is the pinned producer and
    # live native/source ancestry above, within the trusted recipient scope.
    $proof
}

if($AdmitNativeSetup){
    $ErrorActionPreference='Stop';$selection=$null;$remote=0;$committed=$false
    $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        foreach($pin in @($ReceiptHelperSha256,$UpdaterSha256,$NativeSha256)){if($pin -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact native admission inputs required.'}}
        $writer=Join-Path $PSScriptRoot 'write-setup-receipt.ps1';$initial=[IO.File]::Open($writer,'Open','Read','Read')
        try{if((Get-FileHash -InputStream $initial).Hash.ToLowerInvariant() -cne $ReceiptHelperSha256){throw 'Native admission receipt helper differs.'};. $writer}finally{$initial.Dispose()}
        $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
        $self=Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID)
        $native=Get-Process -Id $NativePid -ErrorAction Stop;$nativeCim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$NativePid)
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $nativeOwner=Invoke-CimMethod -InputObject $nativeCim -MethodName GetOwnerSid
        if($self.ParentProcessId -ne $NativePid -or $nativeOwner.ReturnValue -ne 0 -or $nativeOwner.Sid -cne $sid.Value){throw 'Native admission parent identity differs.'}
        $source=Get-Process -Id $nativeCim.ParentProcessId -ErrorAction Stop
        $sourceCim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$source.Id);$sourceOwner=Invoke-CimMethod -InputObject $sourceCim -MethodName GetOwnerSid
        if($sourceOwner.ReturnValue -ne 0 -or $sourceOwner.Sid -cne $sid.Value){throw 'Native admission source ancestor owner differs.'}
        $sourceFile=Get-SetupReceiptFile $source.Path $NativeSha256
        $nativeFile=Get-SetupReceiptFile $native.Path
        $baseFull=Assert-SetupReceiptPath $BaseRoot
        if(!$UpdaterPath){$UpdaterPath=Join-Path $PSScriptRoot 'update-app.ps1'}
        $updater=Get-SetupReceiptFile $UpdaterPath $UpdaterSha256
        $text=[IO.File]::ReadAllText($updater.path);$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
        $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Acquire-SelectionMutex'},$false))
        if($errors.Count -or $nodes.Count -ne 1){throw 'Pinned native selection producer is invalid.'}
        . ([scriptblock]::Create($nodes[0].Extent.Text))
        $selection=Acquire-SelectionMutex $baseFull
        # Duplicate the validated object rather than implementing another SID,
        # canonicalization or ACL protocol in Pascal. Native takes ownership
        # only after this worker exits and releases its thread ownership.
        Add-Type -TypeDefinition @'
using System;using System.ComponentModel;using System.Runtime.InteropServices;
public static class AutoClipNativeSelectionTransfer {
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool DuplicateHandle(IntPtr source,IntPtr handle,IntPtr target,out IntPtr duplicate,uint access,bool inherit,uint flags);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 public static long Send(int pid,IntPtr handle){var target=OpenProcess(64,false,pid);if(target==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());try{IntPtr remote;if(!DuplicateHandle(new IntPtr(-1),handle,target,out remote,0,false,2))throw new Win32Exception(Marshal.GetLastWin32Error());return remote.ToInt64();}finally{CloseHandle(target);}}
 public static void Revoke(int pid,long remote){var target=OpenProcess(64,false,pid);if(target==IntPtr.Zero)return;try{IntPtr local;if(!DuplicateHandle(target,new IntPtr(remote),new IntPtr(-1),out local,0,false,3))throw new Win32Exception(Marshal.GetLastWin32Error());CloseHandle(local);}finally{CloseHandle(target);}}
}
'@
        $output=Assert-SetupReceiptPath $OutputPath
        if([IO.File]::Exists($output) -or [IO.Directory]::Exists($output+'.proof')){throw 'Native admission output already exists.'}
        $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
        foreach($id in @($sid.Value,'S-1-5-18','S-1-5-32-544')){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
        [IO.Directory]::CreateDirectory($output+'.proof',$acl)|Out-Null
        $proofPath=Join-Path ($output+'.proof') 'handoff.json'
        $record=[ordered]@{schema_version=1;selection_protocol='NATIVE_HELD_SELECTION_V1';nonce=[guid]::NewGuid().ToString('N');proof_path=$proofPath;base_root=$baseFull;recipient_sid=$sid.Value;native_pid=$native.Id;native_start=$native.StartTime.ToUniversalTime().ToString('o');native_path=$nativeFile.path;native_sha256=$nativeFile.sha256;source_pid=$source.Id;source_start=$source.StartTime.ToUniversalTime().ToString('o');source_path=$sourceFile.path;source_sha256=$sourceFile.sha256}
        $null=Write-SetupReceiptRecord $proofPath $record
        $remote=[AutoClipNativeSelectionTransfer]::Send($native.Id,$selection.SafeWaitHandle.DangerousGetHandle())
        $stream=[IO.File]::Open($output,'CreateNew','Write','None')
        try{$bytes=[Text.Encoding]::ASCII.GetBytes([string]$remote);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        $committed=$true
    }finally{
        try{if(!$committed -and $remote){[AutoClipNativeSelectionTransfer]::Revoke($NativePid,$remote)}}finally{
            if($selection){try{$selection.ReleaseMutex()}finally{$selection.Dispose()}}
            foreach($held in $script:SetupReceiptLocks){$held.Dispose()}
        }
    }
    return
}

function Commit-InitialSelection($Identity) {
    if(Test-Path -LiteralPath $appStatePath){throw 'Existing app selection must be preserved; use the updater.'}
    $current=[ordered]@{release_id=$Identity.release_id;archive_sha256=$Identity.archive_sha256;manifest_sha256=$Identity.release_manifest_sha256}
    if(Test-Path -LiteralPath $runtimeStatePath){
        $state=Get-Content -LiteralPath $runtimeStatePath -Raw|ConvertFrom-Json
        if($state.schema_version -ne 1 -or !$state.current -or $state.previous -or $state.current.release_id -cne $current.release_id -or $state.current.archive_sha256 -cne $current.archive_sha256 -or $state.current.manifest_sha256 -cne $current.manifest_sha256){throw 'Conflicting runtime selection preserved; use the updater.'}
        return
    }
    Write-AtomicText $runtimeStatePath ([ordered]@{schema_version=1;current=$current;previous=$null}|ConvertTo-Json -Depth 5)
}
function Prepare-InitialLaunchers {
    # Generate the existing updater launchers, then create only missing exact bytes.
    $expected=@{}
    function Write-AtomicText([string]$Path,[string]$Value){$expected[$Path]=$Value}
    Write-StableLauncher;Write-DesktopLauncher
    foreach($path in $expected.Keys){
        Assert-SetupReceiptPath $path|Out-Null
        if([IO.Directory]::Exists($path)){throw 'Stable launcher is not a regular file.'}
        if([IO.File]::Exists($path) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($expected[$path]))){throw 'Modified or unknown stable launcher preserved.'}
    }
    $created=@()
    try{
        foreach($path in $expected.Keys){
            if(![IO.File]::Exists($path)){
                $stream=[IO.File]::Open($path,'CreateNew','Write','None');$created+=,$path
                try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($expected[$path]);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
            }
        }
    }catch{
        foreach($path in $created){
            Assert-SetupReceiptPath $path|Out-Null
            if([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($expected[$path]))){[IO.File]::Delete($path)}
        }
        throw
    }
}
if($PrepareLaunchers -or $Activate){
    $ErrorActionPreference='Stop';$selection=$null;$script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        if($PrepareLaunchers -and $Activate){throw 'Choose preparation or activation.'}
        $inputPin=if($PrepareLaunchers){$RequestSha256}else{$ReceiptSha256}
        if($inputPin -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact initializer request or receipt pin required.'}
        foreach($pin in @($ReceiptHelperSha256,$UpdaterSha256)){if($pin -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact initializer helper pins required.'}}
        $selectionRequestPath=$RequestPath;$selectionRequestSha256=$RequestSha256
        $writer=Join-Path $PSScriptRoot 'write-setup-receipt.ps1'
        $initial=[IO.File]::Open($writer,'Open','Read','Read')
        try{
            if((Get-FileHash -InputStream $initial).Hash.ToLowerInvariant() -cne $ReceiptHelperSha256){throw 'Receipt helper differs.'}
            . $writer
            $RequestPath=$selectionRequestPath;$RequestSha256=$selectionRequestSha256
        }finally{$initial.Dispose()}
        $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
        $baseFull=Assert-SetupReceiptPath $BaseRoot
        $root=Join-Path $baseFull $ReleaseId
        if($ReleaseId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$' -or $ReleaseId.EndsWith('.')){throw 'Invalid initialization release identity.'}
        $setup=Join-Path $baseFull 'Setup'
        Assert-SetupReceiptPath $setup -Protected|Out-Null
        if($PSScriptRoot -ine $setup){throw 'Initializer must belong to the installed Setup.'}
        $updater=Get-SetupReceiptFile (Join-Path $setup 'update-app.ps1') $UpdaterSha256
        $reader=[IO.StreamReader]::new($updater.stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
        try{$source=$reader.ReadToEnd()}finally{$reader.Dispose();$updater.stream.Position=0}
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'Pinned updater does not parse.'}
        foreach($name in @('Acquire-SelectionMutex','Write-AtomicText','Write-StableLauncher','Write-DesktopLauncher','Test-AppHealth')){
            $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false))
            if($nodes.Count -ne 1){throw 'Required pinned updater function missing or ambiguous.'}
            . ([scriptblock]::Create($nodes[0].Extent.Text))
        }
        $runtimeStatePath=Join-Path $baseFull 'active.json';$appStatePath=Join-Path $baseFull 'app-active.json'
        $launcherPath=Join-Path $baseFull 'Start-AutoClip.ps1';$desktopLauncherPath=Join-Path $baseFull 'Start-AutoClip-Desktop.ps1'
        if($NativeSelectionPath -or $NativeSelectionSha256){
            if($NativeSelectionSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact native selection proof pin required.'}
            $null=Assert-NativeSetupSelection (Get-SetupReceiptFile $NativeSelectionPath $NativeSelectionSha256) $baseFull
        }else{$selection=Acquire-SelectionMutex $baseFull}
        if($PrepareLaunchers){
            $requestFile=Get-SetupReceiptFile $RequestPath $RequestSha256
            if($requestFile.bytes -gt 65536 -or !($requestFile.path.StartsWith((Join-Path $setup 'logs')+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Preparation request must be bounded owned Setup logs.'}
            $request=Read-SetupReceiptJson $requestFile
            if($request.schema_version -ne 1){throw 'Unsupported initialization request.'}
            $context=@{};foreach($p in $request.context.PSObject.Properties){$context[$p.Name]=$p.Value}
            $identity=Get-SetupReceiptContext $context
            if($identity.install_root -ine $root -or $identity.release_id -cne $ReleaseId -or $identity.source_helper_sha256 -cne $ReceiptHelperSha256){throw 'Preparation identity differs.'}
            $handoff=Read-SetupSourceHandoff $identity $request.handoff_sha256
        }else{
            if($ReceiptPath -ine (Join-Path $setup ('installation-receipts/'+$ReleaseId+'.json'))){throw 'Receipt is outside fixed initialization scope.'}
            $anchor=Get-SetupReceiptFile (Join-Path $setup ('installation-receipts/'+$ReleaseId+'.sha256'))
            if($anchor.bytes -ne 64 -or [IO.File]::ReadAllText($anchor.path) -cne $ReceiptSha256){throw 'Receipt anchor differs.'}
            $receipt=Read-SetupReceiptJson (Get-SetupReceiptFile $ReceiptPath $ReceiptSha256)
            if($receipt.schema_version -ne 2 -or $receipt.status -cne 'COMPLETE' -or $receipt.setup_root -ine $setup){throw 'Anchored COMPLETE ownership receipt required.'}
            $context=@{};foreach($p in $receipt.context.PSObject.Properties){if($p.Name -cne 'recipient_sid'){$context[$p.Name]=$p.Value}}
            $identity=Get-SetupReceiptContext $context;Test-SetupReceiptIdentity $receipt.context $identity
            if($identity.install_root -ine $root -or $identity.release_id -cne $ReleaseId -or $identity.source_helper_sha256 -cne $ReceiptHelperSha256){throw 'Activation identity differs.'}
            $null=Get-SetupReceiptRows $receipt.release_files $root
            $baseRows=Get-SetupReceiptRows $receipt.base_files $baseFull
            if($baseRows.Count -ne 2 -or !$baseRows.ContainsKey('Start-AutoClip.ps1') -or !$baseRows.ContainsKey('Start-AutoClip-Desktop.ps1')){throw 'Exact stable launcher ownership required.'}
            $handoff=Read-SetupSourceHandoff $identity $receipt.source_handoff.sha256
        }
        $null=Get-SetupReceiptFile (Join-Path $root 'release-manifest.json') $identity.release_manifest_sha256
        $marker=Get-SetupReceiptFile (Join-Path $root '.install-complete')
        if([IO.File]::ReadAllText($marker.path) -cne $identity.archive_sha256){throw 'Installed completion identity differs.'}
        Test-AppHealth (Join-Path $root '.venv/Scripts/python.exe') (Join-Path $root '.venv/Lib/site-packages')
        if($PrepareLaunchers){
            if(Test-Path -LiteralPath $appStatePath){throw 'Existing app selection preserved.'}
            if(Test-Path -LiteralPath $runtimeStatePath){
                $state=Read-SetupReceiptJson (Get-SetupReceiptFile $runtimeStatePath)
                if($state.schema_version -ne 1 -or !$state.current -or $state.previous -or $state.current.release_id -cne $ReleaseId -or $state.current.archive_sha256 -cne $identity.archive_sha256 -or $state.current.manifest_sha256 -cne $identity.release_manifest_sha256){throw 'Conflicting runtime selection preserved.'}
            }
            Prepare-InitialLaunchers
        }else{Commit-InitialSelection $identity}
        [pscustomobject]@{schema_version=1;status=$(if($PrepareLaunchers){'PREPARED_STABLE_LAUNCHERS'}else{'SELECTED_VERIFIED_RUNTIME'});release_id=$ReleaseId;manifest_sha256=$identity.release_manifest_sha256}|ConvertTo-Json -Compress
    }finally{
        if($selection){try{$selection.ReleaseMutex()}finally{$selection.Dispose()}}
        foreach($lock in $script:SetupReceiptLocks){$lock.Dispose()}
    }
}
