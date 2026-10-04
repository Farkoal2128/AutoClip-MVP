param([string]$ReceiptPath,[string]$ReceiptSha256,[string]$ReleaseId,[string]$InstallRoot,
      [string]$ReceiptHelperSha256,[string]$RemovalHelperSha256,[string]$SourceBuildHelperSha256,[string]$UpdaterSha256,[switch]$Preflight,
      [switch]$LaunchNativeUninstall,[string]$HandoffPath,[string]$HandoffSha256,[switch]$NativeSilent)

function Get-UninstallNativeMetadata([string]$Path) {
    if(!('AutoClip.UninstallMetadata' -as [type])){
        Add-Type -TypeDefinition @'
using System; using System.IO; using System.ComponentModel; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
namespace AutoClip { public static class UninstallMetadata {
 [StructLayout(LayoutKind.Sequential)] struct Info { public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation,Access,Write; public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string p,uint a,uint s,IntPtr x,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static string Read(string path) {
  // Zero data access works while Inno holds DAT read/write with fsNone.
  using(var h=CreateFileW(path,0,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero)) {
   if(h.IsInvalid)throw new Win32Exception(Marshal.GetLastWin32Error()); Info i;
   if(!GetFileInformationByHandle(h,out i))throw new Win32Exception(Marshal.GetLastWin32Error());
   if((i.Attributes & 0x410)!=0 || i.Links!=1)throw new InvalidDataException("Unsafe native file identity.");
   return String.Join(":",i.Volume,i.IndexHigh,i.IndexLow,i.SizeHigh,i.SizeLow,i.Creation.dwHighDateTime,i.Creation.dwLowDateTime,i.Write.dwHighDateTime,i.Write.dwLowDateTime,i.Attributes,i.Links);
  }
 }
} }
'@
    }
    Assert-SetupReceiptPath $Path|Out-Null
    [AutoClip.UninstallMetadata]::Read($Path)
}
function Assert-UninstallHandoff($File,$Receipt,[string]$Root,[string]$Setup,$NativeRows) {
    $handoff=Read-SetupReceiptJson $File
    $directory=Join-Path $Setup 'uninstall-handoffs'
    $fields=@('schema_version','status','nonce','receipt_sha256','install_root','base_root','selection_protocol','recipient_sid','launcher_pid','launcher_start','launcher_path','native_files')
    if(@($handoff.PSObject.Properties).Count -ne $fields.Count -or @($handoff.PSObject.Properties.Name|Where-Object{$_ -cnotin $fields}).Count -or $handoff.schema_version -isnot [int] -or $handoff.schema_version -ne 2 -or $handoff.status -cne 'VERIFIED_PRELAUNCH' -or $handoff.nonce -cnotmatch '^[a-f0-9]{32}$' -or $File.path -ine (Join-Path $directory ($handoff.nonce+'.json')) -or $handoff.receipt_sha256 -cne $Receipt.sha256 -or $handoff.install_root -ine $Root -or $handoff.base_root -ine (Split-Path -Parent $Setup) -or $handoff.selection_protocol -cne 'PARENT_HELD_SELECTION_V1' -or $handoff.recipient_sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or @($handoff.native_files).Count -ne @($NativeRows).Count){throw 'Invalid or stale native launch handoff.'}
    $launcher=Get-Process -Id $handoff.launcher_pid -ErrorAction Stop
    if($launcher.StartTime.ToUniversalTime().ToString('o') -cne $handoff.launcher_start -or $launcher.Path -ine $handoff.launcher_path){throw 'Native launcher identity changed.'}
    $cursor=Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID);$nativeFound=$false;$ancestorFound=$false
    for($depth=0;$cursor -and $depth -lt 16;$depth++){
        $owner=Invoke-CimMethod -InputObject $cursor -MethodName GetOwnerSid
        if($owner.ReturnValue -ne 0 -or $owner.Sid -cne $handoff.recipient_sid){throw 'Native callback process owner differs.'}
        if($cursor.ProcessId -eq $handoff.launcher_pid){$ancestorFound=$true;break}
        if($cursor.ExecutablePath -and [IO.File]::Exists($cursor.ExecutablePath)){
            $exe=@($NativeRows|Where-Object path -Match '\.exe$')[0]
            if((Get-Item -LiteralPath $cursor.ExecutablePath).Length -eq $exe.bytes -and (Get-FileHash -LiteralPath $cursor.ExecutablePath).Hash.ToLowerInvariant() -ceq $exe.sha256){$nativeFound=$true}
        }
        $cursor=Get-CimInstance Win32_Process -Filter ('ProcessId='+$cursor.ParentProcessId)
    }
    if(!$ancestorFound -or !$nativeFound){throw 'Callback is not a native uninstall descendant of its live verified launcher.'}
    foreach($row in $NativeRows){$snapshot=@($handoff.native_files|Where-Object path -CEQ $row.path);if($snapshot.Count -ne 1 -or $snapshot[0].sha256 -cne $row.sha256 -or $snapshot[0].bytes -ne $row.bytes -or (Get-UninstallNativeMetadata (Join-Path $Setup $row.path)) -cne $snapshot[0].metadata){throw 'Native file metadata changed after prelaunch verification.'}}
    # Authority is the pinned live launcher/ancestor protocol above. Busy alone
    # does not authenticate its owner. Reuse full canonical path and ACL checks.
    $probe=$null
    try{$probe=Acquire-SelectionMutex $handoff.base_root}catch{if($_.Exception.Message -cnotlike 'AutoClip selection is busy.*'){throw}}
    if($probe){try{$probe.ReleaseMutex()}finally{$probe.Dispose()};throw 'Native selection delegation has no retained owner.'}
    $handoff
}

function Test-UninstallRows($Rows) {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($Rows)){
        $names=@($row.PSObject.Properties.Name);if($row -is [Collections.IDictionary]){$names=@($row.Keys)}
        if($names.Count -ne 3 -or @($names|Where-Object{$_ -notin @('path','bytes','sha256')}).Count -or $row.path -isnot [string] -or $row.bytes -isnot [int] -and $row.bytes -isnot [long] -or $row.bytes -lt 0 -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid uninstall inventory row.'}
        $relative=Get-SetupRelativePath $row.path
        if(!$seen.Add($relative)){throw 'Duplicate uninstall inventory row.'}
    }
}
function Remove-ReceiptOwnedReleaseFiles {
    param([string]$Root,[object[]]$Rows,[object[]]$Directories)
    Assert-SetupReceiptPath $Root -Protected|Out-Null
    Test-UninstallRows $Rows
    $dirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($directory in @($Directories)){if($directory -isnot [string] -or !$dirs.Add((Get-SetupRelativePath $directory))){throw 'Invalid directory inventory.'}}
    $removed=@();$preserved=@()
    foreach($row in $Rows){
        $result=Remove-SetupOwnedFile -Root $Root -Row $row
        if($result.status -in @('REMOVED','MISSING')){$removed+=,(Join-Path $Root $row.path)}else{$preserved+=,[pscustomobject]@{path=(Join-Path $Root $row.path);status=$result.status}}
    }
    foreach($relative in @($dirs|Sort-Object Length -Descending)){
        $path=Join-Path $Root $relative
        try{Assert-SetupReceiptPath $path|Out-Null;if([IO.Directory]::Exists($path)){if(@(Get-Item -LiteralPath $path -Stream * -ErrorAction Stop|Where-Object Stream -NE ':$DATA').Count){throw 'Directory contains an alternate stream.'};[IO.Directory]::Delete($path,$false)}}catch{$preserved+=,[pscustomobject]@{path=$path;status='NONEMPTY_OR_UNSAFE'}}
    }
    [pscustomobject]@{schema_version=1;status=$(if($preserved.Count){'PRESERVED'}else{'REMOVED'});removed=$removed;preserved=$preserved}
}
function Remove-ReceiptOwnedBaseFiles {
    param([string]$BaseRoot,[object[]]$Rows)
    Test-UninstallRows $Rows
    if($Rows.Count -ne 2 -or @($Rows.path|Select-Object -Unique).Count -ne 2 -or @($Rows|Where-Object{$_.path -cnotin @('Start-AutoClip.ps1','Start-AutoClip-Desktop.ps1')}).Count){throw 'Exact finite stable launcher cleanup required.'}
    $removed=@();$preserved=@()
    foreach($row in $Rows){
        $result=Remove-SetupOwnedFile -Root $BaseRoot -Row $row -AllowInheritedRoot
        if($result.status -in @('REMOVED','MISSING')){$removed+=,(Join-Path $BaseRoot $row.path)}else{$preserved+=,[pscustomobject]@{path=(Join-Path $BaseRoot $row.path);status=$result.status}}
    }
    [pscustomobject]@{status=$(if($preserved.Count){'PRESERVED'}else{'REMOVED'});removed=$removed;preserved=$preserved}
}
function Import-UninstallFunctions([string]$Path,[string]$Pin,[string[]]$Names) {
    $file=Get-SetupReceiptFile $Path $Pin
    $text=[IO.File]::ReadAllText($file.path);$tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Pinned cleanup dependency does not parse.'}
    foreach($name in $Names){
        $nodes=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false))
        if($nodes.Count -ne 1){throw 'Required cleanup dependency function is ambiguous.'}
        . ([scriptblock]::Create($nodes[0].Extent.Text.Replace('function '+$name,'function script:'+$name)))
    }
}
function Stop-OwnedAutoClip([string]$Root,$Rows) {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $folderArguments='-B -c "import os,runpy;os.environ[''PYTHONDONTWRITEBYTECODE'']=''1'';runpy.run_module(''autoclip.desktop'',run_name=''__main__'')"'
    foreach($process in Get-CimInstance Win32_Process){
        if(!$process.ExecutablePath -or !$process.ExecutablePath.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){continue}
        $relative=$process.ExecutablePath.Substring($Root.Length+1).Replace('\','/')
        $row=@($Rows|Where-Object path -IEQ $relative)
        # Match the interpreter entry point, never text in a script's arguments.
        # The folder shortcut uses one exact -c wrapper to suppress bytecode.
        $exe=[regex]::Escape($process.ExecutablePath)
        $prefix='^(?i:"'+$exe+'"|'+$exe+')[ \t]+'
        $entry='(?:(?:-B[ \t]+)?-m[ \t]+autoclip\.(?:desktop|cli)(?:[ \t]|$)|'+[regex]::Escape($folderArguments)+'[ \t]*$)'
        if($row.Count -ne 1 -or $relative -notin @('.venv/Scripts/python.exe','.venv/Scripts/pythonw.exe') -or $process.CommandLine -cnotmatch ($prefix+$entry)){throw 'Unknown process uses the release; preserved.'}
        $owner=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
        if($owner.ReturnValue -ne 0 -or $owner.Sid -cne $sid){throw 'Release process owner differs; preserved.'}
        $file=Get-SetupReceiptFile $process.ExecutablePath $row[0].sha256
        if($file.bytes -ne $row[0].bytes){throw 'Release process executable differs; preserved.'}
        $live=Get-Process -Id $process.ProcessId -ErrorAction Stop
        # CIM exposes microseconds; the native process API retains 100ns ticks.
        $liveTicks=$live.StartTime.ToUniversalTime().Ticks;$cimTicks=$process.CreationDate.ToUniversalTime().Ticks
        if($live.Path -ine $process.ExecutablePath -or ($liveTicks-($liveTicks%10)) -ne ($cimTicks-($cimTicks%10))){throw 'Release process identity changed; preserved.'}
        if($live.CloseMainWindow()){$null=$live.WaitForExit(3000)}
        if(!$live.HasExited){$live.Kill();$live.WaitForExit()}
    }
}
function Assert-UninstallRegistration($Expected) {
    $key='Software\Microsoft\Windows\CurrentVersion\Uninstall\{D7451842-48F4-487B-80E0-5C7E9E326342}_is1'
    if($Expected.key -cne $key -or $Expected.view -cne 'Registry64' -or $null -eq $Expected.values -or @($Expected.subkeys).Count){throw 'Exact native registration snapshot required.'}
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try{
        $actual=$base.OpenSubKey($key,$false);if(!$actual){throw 'Native uninstall registration missing.'}
        try{
            if(@($actual.GetSubKeyNames()).Count){throw 'Unknown uninstall registration subkey; preserved.'}
            $values=@($actual.GetValueNames()|Sort-Object|ForEach-Object{[ordered]@{name=$_;kind=$actual.GetValueKind($_).ToString();value=$actual.GetValue($_,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}})
            if(($values|ConvertTo-Json -Depth 8 -Compress) -cne ($Expected.values|ConvertTo-Json -Depth 8 -Compress)){throw 'Native uninstall registration changed; preserved.'}
        }finally{$actual.Dispose()}
    }finally{$base.Dispose()}
}

if($ReceiptPath){
    $ErrorActionPreference='Stop';$script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new();$selection=$null;$target=$null
    try{
        if([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Cleanup requires the ordinary recipient.'}
        # Bootstrap trust is the compiled Inno pin; the protected receipt anchor
        # supplies its dynamic receipt hash. No remote helper acquisition occurs.
        foreach($pin in @($ReceiptSha256,$ReceiptHelperSha256,$RemovalHelperSha256,$SourceBuildHelperSha256,$UpdaterSha256)){if($pin -isnot [string] -or $pin -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact pinned cleanup inputs required.'}}
        if($NativeSilent -and !$LaunchNativeUninstall){throw 'Native quiet mode is available only to the verified launcher.'}
        if($LaunchNativeUninstall -and ($HandoffPath -or $HandoffSha256)){throw 'A new native launch cannot adopt an existing handoff.'}
        $receiptHelper=Join-Path $PSScriptRoot 'write-setup-receipt.ps1'
        if((Get-FileHash -LiteralPath $receiptHelper).Hash.ToLowerInvariant() -cne $ReceiptHelperSha256){throw 'Receipt helper differs.'}
        $initial=[IO.File]::Open($receiptHelper,'Open','Read','Read')
        try{if((Get-FileHash -LiteralPath $receiptHelper).Hash.ToLowerInvariant() -cne $ReceiptHelperSha256){throw 'Receipt helper changed.'};. $receiptHelper}finally{$initial.Dispose()}
        $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
        $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $base=Assert-SetupReceiptPath (Join-Path $local 'AutoClip')
        $setup=Assert-SetupReceiptPath (Join-Path $base 'Setup') -Protected
        $root=Assert-SetupReceiptPath $InstallRoot -Protected
        if($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$' -or $root -ine (Join-Path $base $ReleaseId) -or $ReceiptPath -ine (Join-Path $setup ('installation-receipts/'+$ReleaseId+'.json'))){throw 'Cleanup target or receipt is outside its fixed release scope.'}
        Assert-SetupReceiptPath $PSScriptRoot -Protected|Out-Null
        $removal=Get-SetupReceiptFile (Join-Path $PSScriptRoot 'remove-owned-file.ps1') $RemovalHelperSha256
        . $removal.path
        Import-UninstallFunctions (Join-Path $PSScriptRoot 'update.ps1') $UpdaterSha256 @('Acquire-SelectionMutex')
        Import-UninstallFunctions (Join-Path $PSScriptRoot 'run-source-build.ps1') $SourceBuildHelperSha256 @('Assert-BuildPath','New-BuildDirectoryAcl','Get-BuildStoragePath','Initialize-BuildStorage','Get-BuildTargetIdentity','Open-BuildTargetLock')
        if($LaunchNativeUninstall){$selection=Acquire-SelectionMutex $base;$target=Open-BuildTargetLock $root}
        $receiptFile=Get-SetupReceiptFile $ReceiptPath $ReceiptSha256
        $receipt=Read-SetupReceiptJson $receiptFile
        $fields=@('schema_version','status','context','setup_root','setup_sha256','source_handoff','app_health','release_files','release_directories','setup_files','shortcuts','registration')
        if($receipt.schema_version -eq 2){$fields+='base_files'}
        if(@($receipt.PSObject.Properties).Count -ne $fields.Count -or @($receipt.PSObject.Properties.Name|Where-Object{$_ -cnotin $fields}).Count){throw 'Unsupported complete receipt schema.'}
        if($receipt.schema_version -isnot [int] -or $receipt.schema_version -notin @(1,2) -or $receipt.status -cne 'COMPLETE' -or $receipt.setup_root -ine $setup -or $receipt.context.install_root -ine $root -or $receipt.context.release_id -cne $ReleaseId -or $receipt.context.recipient_sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Complete receipt identity differs.'}
        $context=@{};foreach($property in $receipt.context.PSObject.Properties){if($property.Name -cne 'recipient_sid'){$context[$property.Name]=$property.Value}}
        $identity=Get-SetupReceiptContext $context;Test-SetupReceiptIdentity $receipt.context $identity
        if($receipt.setup_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $receipt.source_handoff.path -ine (Join-Path $root '.setup-source-ownership.json') -or $receipt.source_handoff.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $receipt.app_health.status -cne 'VERIFIED_HEALTH_HOME' -or $receipt.app_health.install_root -ine $root -or $receipt.app_health.manifest_sha256 -cne $identity.release_manifest_sha256){throw 'Complete receipt evidence binding differs.'}
        Test-UninstallRows $receipt.release_files;Test-UninstallRows $receipt.setup_files
        foreach($directory in $receipt.release_directories){Get-SetupRelativePath $directory|Out-Null}
        $helperNames=@('uninstall-owned-release.ps1','write-setup-receipt.ps1','remove-owned-file.ps1','run-source-build.ps1','update.ps1')
        if($receipt.schema_version -eq 2){
            $helperNames+=@('update-app.ps1','initialize-selection.ps1','run-maintenance.ps1','AutoClip-Maintenance.exe','install.ps1','installer-dependencies-v1.json')
            Test-UninstallRows $receipt.base_files
            if($receipt.base_files.Count -ne 2 -or @($receipt.base_files|Where-Object{$_.path -cnotin @('Start-AutoClip.ps1','Start-AutoClip-Desktop.ps1')}).Count){throw 'Invalid finite base ownership scope.'}
        }
        $notices=@('notices/inno-setup-7.1.0-LICENSE.txt','notices/uv-0.12.19-LICENSE-MIT.txt','notices/uv-0.12.19-LICENSE-APACHE.txt','notices/setup-tool-sources.md')
        $uninstall=@($receipt.setup_files|Where-Object path -Match '^unins[0-9]+\.exe$')
        if($uninstall.Count -ne 1 -or @($receipt.setup_files|Where-Object path -IEQ ($uninstall[0].path -replace '\.exe$','.dat')).Count -ne 1){throw 'Exact native uninstaller pair required.'}
        foreach($row in $receipt.setup_files){if($row.path -cnotin $helperNames -and $row.path -cnotin $notices -and $row.path -notmatch '^unins[0-9]+\.(exe|dat|msg)$'){throw 'Unapproved setup cleanup scope.'}}
        foreach($name in $helperNames){$rows=@($receipt.setup_files|Where-Object path -CEQ $name);if($rows.Count -ne 1){throw 'Durable helper missing from receipt.'};$file=Get-SetupReceiptFile (Join-Path $setup $name) $rows[0].sha256;if($file.bytes -ne $rows[0].bytes){throw 'Durable helper length changed.'}}
        $nativeRows=@($receipt.setup_files|Where-Object path -Match '^unins[0-9]+\.(exe|dat|msg)$')
        if(!$LaunchNativeUninstall -and (!$HandoffPath -or $HandoffSha256 -cnotmatch '^[a-f0-9]{64}$')){throw 'Direct native uninstall requires a verified prelaunch handoff.'}
        foreach($native in $nativeRows){
            if(!$LaunchNativeUninstall -and $native.path -like '*.dat'){continue}
            $file=Get-SetupReceiptFile (Join-Path $setup $native.path) $native.sha256;if($file.bytes -ne $native.bytes){throw 'Native uninstaller output changed; preserved.'}
            if($LaunchNativeUninstall -and @(Get-Item -LiteralPath $file.path -Stream * -ErrorAction Stop|Where-Object Stream -NE ':$DATA').Count){throw 'Native output has an unknown stream; preserved.'}
        }
        if($receipt.registration.install_location -ine ($setup+'\') -or $receipt.registration.native_uninstaller -ine (Join-Path $setup $uninstall[0].path) -or !$receipt.registration.uninstall_string){throw 'Native registration scope differs.'}
        Assert-UninstallRegistration $receipt.registration
        if(!$LaunchNativeUninstall){$proof=Get-SetupReceiptFile $HandoffPath $HandoffSha256;Assert-SetupReceiptPath (Split-Path -Parent $proof.path) -Protected|Out-Null;$delegation=Assert-UninstallHandoff $proof $receiptFile $root $setup $nativeRows;$target=Open-BuildTargetLock $root}
        $programs=[Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
        $nativeShortcut=Join-Path $programs 'AutoClip/AutoClip.lnk'
        $maintenanceShortcut=Join-Path $programs 'AutoClip/AutoClip Maintenance.lnk'
        $shortcutCount=if($receipt.schema_version -eq 2){3}else{2}
        if(@($receipt.shortcuts).Count -ne $shortcutCount -or @($receipt.shortcuts.path|Select-Object -Unique).Count -ne $shortcutCount){throw 'Exact finite owned shortcuts required.'}
        foreach($shortcut in $receipt.shortcuts){
            if($shortcut.path -ine (Join-Path $root 'AutoClip.lnk') -and $shortcut.path -ine $nativeShortcut -and !($receipt.schema_version -eq 2 -and $shortcut.path -ieq $maintenanceShortcut)){throw 'Shortcut outside fixed ownership scope.'}
            if($shortcut.bytes -isnot [int] -and $shortcut.bytes -isnot [long] -or $shortcut.bytes -lt 0 -or $shortcut.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid shortcut ownership row.'}
        }
        $statePath=Join-Path $base 'active.json';$stateFile=$null;$reset=$false
        if(Test-Path -LiteralPath $statePath){
            $stateFile=Get-SetupReceiptFile $statePath;$state=Read-SetupReceiptJson $stateFile
            if($state.schema_version -ne 1 -or !$state.current){throw 'Invalid selection state; preserved.'}
            if($state.previous.release_id -ceq $ReleaseId -or ($state.current.release_id -ceq $ReleaseId -and $state.previous)){throw 'Release remains an active/rollback reference; preserved.'}
            $reset=$state.current.release_id -ceq $ReleaseId
            if($reset -and ($state.current.archive_sha256 -cne $receipt.context.archive_sha256 -or $state.current.manifest_sha256 -cne $receipt.context.release_manifest_sha256)){throw 'Selected release identity differs; preserved.'}
        }
        $appPath=Join-Path $base 'app-active.json'
        if(Test-Path -LiteralPath $appPath){$app=Read-SetupReceiptJson (Get-SetupReceiptFile $appPath);if($app.schema_version -ne 1 -or !$app.current -or $app.current.required_runtime -ceq $ReleaseId -or $app.previous.required_runtime -ceq $ReleaseId){throw 'App state invalid or release remains referenced; preserved.'}}
        if($Preflight){[pscustomobject]@{schema_version=1;status='VERIFIED_UNINSTALL_PREFLIGHT';release_id=$ReleaseId;install_root=$root;receipt_sha256=$receiptFile.sha256}|ConvertTo-Json -Compress;return}
        if($LaunchNativeUninstall){
            $directory=Join-Path $setup 'uninstall-handoffs'
            if(![IO.Directory]::Exists($directory)){[IO.Directory]::CreateDirectory($directory,(New-BuildDirectoryAcl))|Out-Null}
            Assert-SetupReceiptPath $directory -Protected|Out-Null
            $nonce=[guid]::NewGuid().ToString('N');$current=Get-Process -Id $PID
            $snapshot=@($nativeRows|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256;metadata=(Get-UninstallNativeMetadata (Join-Path $setup $_.path))}})
            $record=[ordered]@{schema_version=2;status='VERIFIED_PRELAUNCH';nonce=$nonce;receipt_sha256=$receiptFile.sha256;install_root=$root;base_root=$base;selection_protocol='PARENT_HELD_SELECTION_V1';recipient_sid=$identity.recipient_sid;launcher_pid=$PID;launcher_start=$current.StartTime.ToUniversalTime().ToString('o');launcher_path=$current.Path;native_files=$snapshot}
            $handoff=Write-SetupReceiptRecord (Join-Path $directory ($nonce+'.json')) $record
            foreach($held in $script:SetupReceiptLocks){$held.Dispose()};$script:SetupReceiptLocks.Clear()
            # The proof handle remains live while native uninstall runs; DAT is
            # released before Inno opens it exclusively. The trusted actor cutoff
            # accepts that bounded prelaunch/open race, not continuous hashing.
            $proof=[IO.File]::Open($handoff.path,'Open','Read','Read')
            $target.Dispose();$target=$null
            try{
                $nativeArgs=@(('/AUTOCLIP-HANDOFF="'+$handoff.path+'"'),('/AUTOCLIP-HANDOFF-SHA256='+$handoff.sha256))
                if($NativeSilent){$nativeArgs+=@('/VERYSILENT','/NORESTART')}
                # Windows PowerShell -Wait waits the process tree, including an
                # original stub which exits while its native descendant runs.
                # ponytail: launcher death remains R5; this is ordinary lifetime exclusion.
                $nativeStyle=if($NativeSilent){'Hidden'}else{'Normal'}
                $native=Start-Process -FilePath (Join-Path $setup $uninstall[0].path) -ArgumentList $nativeArgs -WindowStyle $nativeStyle -PassThru -Wait
                $null=$native.Handle;$native.WaitForExit();$originalCode=[int]$native.ExitCode;$code=$originalCode;$native.Dispose()
                $completionPath=Join-Path $directory ($nonce+'.result.json')
                $completion=$null
                if([IO.File]::Exists($completionPath)){
                    $completion=Read-SetupReceiptJson (Get-SetupReceiptFile $completionPath)
                    if(@($completion.PSObject.Properties).Count -ne 4 -or $completion.schema_version -ne 1 -or $completion.handoff_sha256 -cne $handoff.sha256 -or $completion.receipt_sha256 -cne $receiptFile.sha256 -or $completion.result.status -cnotin @('REMOVED','PRESERVED')){throw 'Native callback completion binding differs.'}
                }
                $remaining=@($nativeRows|Where-Object{[IO.File]::Exists((Join-Path $setup $_.path))})
                $remainingOwnedSetup=@($receipt.setup_files|Where-Object{[IO.File]::Exists((Join-Path $setup $_.path))})
                $registrationBase=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
                try{$registration=$registrationBase.OpenSubKey($receipt.registration.key,$false);$registered=$null -ne $registration;if($registration){$registration.Dispose()}}finally{$registrationBase.Dispose()}
                if(!$completion -and $remaining.Count -eq $nativeRows.Count -and $registered){
                    # Cancelled/failed callbacks must preserve the exact native inputs.
                    foreach($row in $nativeRows){$file=Get-SetupReceiptFile (Join-Path $setup $row.path) $row.sha256;if($file.bytes -ne $row.bytes){throw 'Native cancellation changed owned inputs.'}}
                    Assert-UninstallRegistration $receipt.registration
                    $disposition='NATIVE_RETAINED'
                }elseif($completion -and !$remainingOwnedSetup.Count -and !$registered){
                    $disposition='NATIVE_'+$completion.result.status
                    if($completion.result.status -ceq 'REMOVED' -and ([IO.File]::Exists($ReceiptPath) -or [IO.File]::Exists([IO.Path]::ChangeExtension($ReceiptPath,'.sha256')))){throw 'Clean native removal did not retire receipt evidence.'}
                }else{$disposition='NATIVE_INCOMPLETE';if($code -eq 0){$code=1}}
                [pscustomobject]@{schema_version=1;status=$disposition;native_original_exit_code=$originalCode;native_post_uninstall_observed=$true;handoff_path=$handoff.path;callback_result=$(if($completion){$completion.result}else{$null})}|ConvertTo-Json -Depth 9 -Compress
            }finally{$proof.Dispose()}
            if($code -ne 0){exit $code};return
        }
        Stop-OwnedAutoClip $root $receipt.release_files
        foreach($held in $script:SetupReceiptLocks){$held.Dispose()};$script:SetupReceiptLocks.Clear()
        if($reset){
            $row=@{path='active.json';bytes=$stateFile.bytes;sha256=$stateFile.sha256}
            $selectionRemoval=Remove-SetupOwnedFile -Root $base -Row $row -AllowInheritedRoot
            if($selectionRemoval.status -cne 'REMOVED'){throw ('Selection changed or unsafe; release preserved. outcome='+$selectionRemoval.status)}
        }
        $result=Remove-ReceiptOwnedReleaseFiles -Root $root -Rows $receipt.release_files -Directories $receipt.release_directories
        if($reset -and $receipt.schema_version -eq 2){$baseResult=Remove-ReceiptOwnedBaseFiles -BaseRoot $base -Rows $receipt.base_files;$result.removed+=@($baseResult.removed);$result.preserved+=@($baseResult.preserved)}
        $shell=Remove-ReceiptOwnedReleaseFiles -Root $setup -Rows @($receipt.setup_files|Where-Object{$_.path -cin $notices}) -Directories @('notices')
        $result.removed+=@($shell.removed);$result.preserved+=@($shell.preserved)
        foreach($shortcut in @($receipt.shortcuts|Where-Object{$_.path -ieq $nativeShortcut -or ($receipt.schema_version -eq 2 -and $_.path -ieq $maintenanceShortcut)})){
            $row=@{path=[IO.Path]::GetFileName($shortcut.path);bytes=$shortcut.bytes;sha256=$shortcut.sha256}
            $outcome=Remove-SetupOwnedFile -Root (Join-Path $programs 'AutoClip') -Row $row -AllowInheritedRoot
            if($outcome.status -in @('REMOVED','MISSING')){$result.removed+=,$shortcut.path}else{$result.preserved+=,[pscustomobject]@{path=$shortcut.path;status=$outcome.status}}
        }
        if($result.preserved.Count){$result.status='PRESERVED'}
        try{
            Assert-SetupReceiptPath $root -Protected|Out-Null
            if([IO.Directory]::Exists($root)){
                if(@(Get-Item -LiteralPath $root -Stream * -ErrorAction Stop|Where-Object Stream -NE ':$DATA').Count){throw 'Release root alternate stream remains.'}
                [IO.Directory]::Delete($root,$false)
            }
        }catch{$result.status='PRESERVED';$result.preserved+=,[pscustomobject]@{path=$root;status='NONEMPTY_OR_UNSAFE'}}
        $result|Add-Member selection $(if($reset){'RESET'}else{'PRESERVED'})
        # Inno owns the pinned durable helpers, registration and running native
        # uninstaller pair. Their exact preflight precedes native removal.
        $null=Write-SetupReceiptRecord (Join-Path (Split-Path -Parent $HandoffPath) ($delegation.nonce+'.result.json')) ([ordered]@{schema_version=1;handoff_sha256=$HandoffSha256;receipt_sha256=$ReceiptSha256;result=$result})
        $result|ConvertTo-Json -Depth 8 -Compress
    }catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
    finally{foreach($held in $script:SetupReceiptLocks){$held.Dispose()};if($target){$target.Dispose()};if($selection){try{$selection.ReleaseMutex()}finally{$selection.Dispose()}}}
}
