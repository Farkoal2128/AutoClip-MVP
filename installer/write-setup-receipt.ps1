param([switch]$Finalize,[string]$RequestPath,[string]$RequestSha256)
# Import these explicit functions from pinned first-party bytes. No native execution.
$script:SetupReceiptProofs=@{}
function Assert-SetupReceiptPath([string]$Path,[switch]$Protected) {
    if($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(3) -match '[:*?"<>|\x00-\x1f]' -or @($Path.Substring(3).Split([char[]]'\/')|Where-Object{!$_ -or $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ')}).Count){throw 'Receipt path must be absolute, local and safe.'}
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trusted=@($sid,'S-1-5-18','S-1-5-32-544')
    while($cursor){
        try{
            $attributes=[IO.File]::GetAttributes($cursor)
            if($attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Receipt path contains a reparse point.'}
        }catch [IO.FileNotFoundException]{}catch [IO.DirectoryNotFoundException]{}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if(Test-Path -LiteralPath $full){
            $acl=Get-Acl -LiteralPath $full
            if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted){throw 'Receipt path owner is foreign.'}
            if($Protected -and !$acl.AreAccessRulesProtected){throw 'Receipt staging must be protected.'}
            $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));if(!$rules.Count){throw 'Empty receipt ACL.'}
            $writes=278 -bor 64 -bor 65536 -bor 262144 -bor 524288 -bor 268435456 -bor 1073741824
            foreach($rule in $rules){if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and ([long]$rule.FileSystemRights -band $writes)){throw 'Receipt path permits foreign writes.'}}
    }
    $full
}
function Get-SetupReceiptContext([hashtable]$Context) {
    $fields=@('install_root','release_id','profile','archive_sha256','release_manifest_sha256','dependency_manifest_sha256','bootstrap_sha256','source_helper_sha256','health_helper_sha256')
    if($Context.Count -ne $fields.Count -or @($Context.Keys|Where-Object{$_ -notin $fields}).Count){throw 'Unsupported receipt context fields.'}
    $result=[ordered]@{}
    foreach($field in $fields){if($Context[$field] -isnot [string] -or !$Context[$field]){throw 'Receipt context requires strings.'};$result[$field]=$Context[$field]}
    $result.install_root=Assert-SetupReceiptPath $result.install_root
    if($result.release_id -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$' -or $result.release_id.EndsWith('.') -or $result.profile -cnotin @('cpu','nvidia')){throw 'Invalid release identity/profile.'}
    foreach($field in $fields|Where-Object{$_ -like '*sha256'}){if($result[$field] -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact lowercase receipt pin required.'}}
    $result.recipient_sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    [pscustomobject]$result
}
function Test-SetupReceiptIdentity($Actual,$Expected) {
    foreach($field in $Expected.PSObject.Properties.Name){if($field -eq 'install_root'){if($Actual.$field -ine $Expected.$field){throw 'Receipt install root differs.'}}elseif($Actual.$field -cne $Expected.$field){throw ('Receipt identity differs: '+$field)}}
}
function Get-SetupRelativePath([string]$Path) {
    if(!$Path -or $Path -match '[\\:*?"<>|\x00-\x1f]' -or $Path.StartsWith('/') -or @($Path.Split('/')|Where-Object{!$_ -or $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'}).Count){throw 'Unsafe relative receipt path.'}
    $Path
}
function Get-SetupReceiptFile([string]$Path,[string]$Pin) {
    $Path=Assert-SetupReceiptPath $Path
    if(!(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Receipt regular file is missing.'}
    $stream=[IO.File]::Open($Path,'Open','Read','Read');$script:SetupReceiptLocks.Add($stream)
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$sha=[BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
    if($Pin -and ($Pin -cnotmatch '^[a-f0-9]{64}$' -or $Pin -cne $sha)){throw 'Receipt file SHA256 differs.'}
    $stream.Position=0
    [pscustomobject]@{path=$Path;bytes=$stream.Length;sha256=$sha;stream=$stream}
}
function Read-SetupReceiptJson($File) {
    if($File.bytes -gt 16777216){throw 'Receipt JSON exceeds bounded size.'}
    $reader=[IO.StreamReader]::new($File.stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
    try{$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose();$File.stream.Position=0}
}
function Get-SetupReceiptTree([string]$Root) {
    $files=[Collections.Generic.List[string]]::new();$directories=[Collections.Generic.List[string]]::new()
    if(!(Test-Path -LiteralPath $Root)){return [pscustomobject]@{files=@();directories=@()}}
    if(!(Test-Path -LiteralPath $Root -PathType Container)){throw 'Install root is not a directory.'}
    $pending=[Collections.Generic.Queue[string]]::new();$pending.Enqueue($Root)
    while($pending.Count){
        $directory=$pending.Dequeue();Assert-SetupReceiptPath $directory|Out-Null
        foreach($item in Get-ChildItem -LiteralPath $directory -Force){
            Assert-SetupReceiptPath $item.FullName|Out-Null
            $relative=Get-SetupRelativePath ($item.FullName.Substring($Root.TrimEnd('\').Length+1).Replace('\','/'))
            if($item.PSIsContainer){$directories.Add($relative);$pending.Enqueue($item.FullName)}else{$files.Add($relative)}
        }
    }
    [pscustomobject]@{files=$files.ToArray();directories=$directories.ToArray()}
}
function Get-SetupReceiptRows($Rows,[string]$Root) {
    $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($Rows)){
        $relative=Get-SetupRelativePath ([string]$row.path)
        $names=if($row -is [Collections.IDictionary]){@($row.Keys)}else{@($row.PSObject.Properties.Name)}
        if($names.Count -ne 3 -or @($names|Where-Object{$_ -notin @('path','bytes','sha256')}).Count -or $row.bytes -isnot [ValueType] -or [long]$row.bytes -lt 0 -or [double]$row.bytes -ne [long]$row.bytes -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $map.ContainsKey($relative)){throw 'Invalid or duplicate receipt inventory row.'}
        $file=Get-SetupReceiptFile (Join-Path $Root $relative) $row.sha256
        if($file.bytes -ne [long]$row.bytes){throw 'Receipt inventory length differs.'}
        $map.Add($relative,[pscustomobject]@{path=$relative;bytes=$file.bytes;sha256=$file.sha256})
    }
    return ,$map
}
function Get-SetupArchiveRows([string]$ManifestPath,$Identity,[switch]$ExistingOnly) {
    $file=Get-SetupReceiptFile $ManifestPath $Identity.release_manifest_sha256
    $manifest=Read-SetupReceiptJson $file
    if($manifest.schema_version -ne 3 -or $manifest.files -isnot [array]){throw 'Source manifest schema3/files required.'}
    $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in @($manifest.files)){
        $relative=Get-SetupRelativePath ([string]$row.path)
        if($relative -in @('.setup-source-ownership.json','.install-complete','native-build-receipt.json','AutoClip.lnk') -or $map.ContainsKey($relative) -or $row.bytes -isnot [ValueType] -or [long]$row.bytes -lt 0 -or [double]$row.bytes -ne [long]$row.bytes -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid archive inventory.'}
        $map.Add($relative,$row)
    }
    if($map.ContainsKey('release-manifest.json')){throw 'Manifest cannot inventory itself.'}
    $map.Add('release-manifest.json',[pscustomobject]@{path='release-manifest.json';bytes=$file.bytes;sha256=$file.sha256})
    foreach($relative in $map.Keys){
        $path=Join-Path $Identity.install_root $relative
        if($ExistingOnly -and !(Test-Path -LiteralPath $path)){continue}
        $actual=Get-SetupReceiptFile $path $map[$relative].sha256
        if($actual.bytes -ne $map[$relative].bytes){throw 'Archive file length differs.'}
    }
    return ,$map
}
function Assert-SetupHealth($Identity,$Pin) {
    if($Pin.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $Pin.bytes -isnot [ValueType] -or [long]$Pin.bytes -le 0 -or $Pin.install_root -ine $Identity.install_root -or $Pin.manifest_sha256 -cne $Identity.release_manifest_sha256 -or $Pin.status -cne 'VERIFIED_HEALTH_HOME'){throw 'Health receipt binding differs.'}
    $file=Get-SetupReceiptFile $Pin.result_path $Pin.sha256
    if($file.bytes -ne $Pin.bytes -or $file.bytes -gt 65536){throw 'Health receipt length differs.'}
    $health=Read-SetupReceiptJson $file
    if($health.schema_version -ne 1 -or $health.status -cne 'VERIFIED_HEALTH_HOME' -or $health.install_root -ine $Identity.install_root -or $health.manifest_sha256 -cne $Identity.release_manifest_sha256 -or $health.isolated_health_only -isnot [bool] -or !$health.isolated_health_only -or $health.child.exit_code -ne 0 -or $health.child.receipt.health_status -ne 200 -or $health.child.receipt.home_status -ne 200){throw 'Actual health result differs.'}
    foreach($flag in @('desktop_tested','media_tested','model_inference_tested')){if($health.$flag -isnot [bool] -or $health.$flag){throw 'Health evidence must retain isolated-only scope.'}}
    [pscustomobject]@{result_path=$file.path;bytes=$file.bytes;sha256=$file.sha256;status=$health.status;install_root=$health.install_root;manifest_sha256=$health.manifest_sha256}
}
function Assert-SetupShortcut([string]$Path,$Identity,[string]$Pin,[switch]$Folder,[switch]$Stable) {
    if($Pin -cnotmatch '^[a-f0-9]{64}$'){throw 'Exact shortcut pin required.'}
    $file=Get-SetupReceiptFile $Path $Pin
    $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($file.path)
    if($Stable){
        $base=Split-Path -Parent $Identity.install_root
        if($link.TargetPath -ine (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -or $link.Arguments -cne ('-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "'+(Join-Path $base 'Start-AutoClip-Desktop.ps1')+'"') -or $link.WorkingDirectory -ine $base){throw 'Actual stable shortcut semantics differ.'}
    }elseif($link.TargetPath -ine (Join-Path $Identity.install_root '.venv/Scripts/pythonw.exe') -or $link.Arguments -cne '-B -c "import os,runpy;os.environ[''PYTHONDONTWRITEBYTECODE'']=''1'';runpy.run_module(''autoclip.desktop'',run_name=''__main__'')"' -or $link.WorkingDirectory -ine $Identity.install_root -or ($Folder -and $link.Description -cne 'Start AutoClip')){throw 'Actual shortcut semantics differ.'}
    [pscustomobject]@{path=$file.path;bytes=$file.bytes;sha256=$file.sha256;target=$link.TargetPath;arguments=$link.Arguments;working_directory=$link.WorkingDirectory;description=$link.Description}
}
function Read-SetupSourceHandoff($Identity,[string]$Pin) {
    $file=Get-SetupReceiptFile (Join-Path $Identity.install_root '.setup-source-ownership.json') $Pin
    $record=Read-SetupReceiptJson $file
    if($record.schema_version -isnot [int] -or $record.schema_version -ne 1 -or $record.status -cne 'VERIFIED_SOURCE_OUTPUTS'){throw 'Source handoff schema/status differs.'}
    Test-SetupReceiptIdentity $record.context $Identity
    $rows=Get-SetupReceiptRows $record.files $Identity.install_root
    if($rows.ContainsKey('.setup-source-ownership.json') -or $rows.ContainsKey('.install-complete')){throw 'Source handoff cannot own itself or predeclare marker.'}
    $tree=Get-SetupReceiptTree $Identity.install_root
    foreach($path in $tree.files){if($path -notin @('.setup-source-ownership.json','.install-complete') -and !$rows.ContainsKey($path)){throw 'Unknown retained source file; preserved.'}}
    $dirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in @($record.directories)){if(!$dirs.Add((Get-SetupRelativePath $path))){throw 'Duplicate source directory.'}}
    if($dirs.Count -ne $tree.directories.Count -or @($tree.directories|Where-Object{!$dirs.Contains($_)}).Count){throw 'Retained source directory inventory differs.'}
    $native=Get-SetupReceiptFile (Join-Path $Identity.install_root 'native-build-receipt.json') $record.native_receipt.sha256
    if($native.bytes -ne $record.native_receipt.bytes -or !$rows.ContainsKey('native-build-receipt.json') -or $rows['native-build-receipt.json'].sha256 -cne $native.sha256){throw 'Native receipt binding differs.'}
    $nativeRecord=Read-SetupReceiptJson $native
    if($nativeRecord.profile -cne $Identity.profile){throw 'Native receipt profile differs.'}
    $health=Assert-SetupHealth $Identity $record.app_health
    if($nativeRecord.setup_app_health.sha256 -cne $health.sha256 -or $nativeRecord.setup_app_health.result_path -ine $health.result_path){throw 'Native health binding differs.'}
    $launcher=Assert-SetupShortcut (Join-Path $Identity.install_root 'AutoClip.lnk') $Identity $record.launcher.sha256 -Folder
    if(!$rows.ContainsKey('AutoClip.lnk') -or $rows['AutoClip.lnk'].sha256 -cne $launcher.sha256 -or $nativeRecord.setup_owned_launcher.sha256 -cne $launcher.sha256 -or $nativeRecord.setup_owned_launcher.bytes -ne $launcher.bytes -or $nativeRecord.setup_owned_launcher.archive_sha256 -cne $Identity.archive_sha256 -or $nativeRecord.setup_owned_launcher.release_manifest_sha256 -cne $Identity.release_manifest_sha256){throw 'Native launcher binding differs.'}
    $marker=Join-Path $Identity.install_root '.install-complete'
    if(Test-Path -LiteralPath $marker){$mark=Get-SetupReceiptFile $marker;$reader=[IO.StreamReader]::new($mark.stream);try{if($reader.ReadToEnd() -cne $Identity.archive_sha256){throw 'Marker identity differs.'}}finally{$reader.Dispose()}}
    [pscustomobject]@{record=$record;file=$file;rows=$rows;tree=$tree}
}
function Write-SetupReceiptRecord([string]$Path,$Record,[string]$ReplacePin) {
    $Path=Assert-SetupReceiptPath $Path;$parent=Split-Path -Parent $Path
    Assert-SetupReceiptPath $parent -Protected|Out-Null
    if(!(Test-Path -LiteralPath $parent -PathType Container)){throw 'Receipt protected parent must exist.'}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Record|ConvertTo-Json -Depth 16))
    if($bytes.Length -gt 16777216){throw 'Receipt exceeds bounded size.'}
    if(Test-Path -LiteralPath $Path){
        $existing=Get-SetupReceiptFile $Path $ReplacePin
        $same=$existing.bytes -eq $bytes.Length
        if($same){$current=New-Object byte[] $bytes.Length;$null=$existing.stream.Read($current,0,$current.Length);for($i=0;$i -lt $bytes.Length;$i++){if($current[$i] -ne $bytes[$i]){$same=$false;break}}}
        if($same){return [pscustomobject]@{path=$Path;bytes=$existing.bytes;sha256=$existing.sha256;status=$Record.status}}
        if(!$ReplacePin){throw 'Conflicting installation receipt; preserved.'}
        $existing.stream.Dispose()
    }
    $temporary=Join-Path $parent ('.receipt-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $writer=[IO.File]::Open($temporary,'CreateNew','Write','None')
    try{$writer.Write($bytes,0,$bytes.Length);$writer.Flush($true)}finally{$writer.Dispose()}
    try{if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,[NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}}finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    $file=Get-SetupReceiptFile $Path
    [pscustomobject]@{path=$file.path;bytes=$file.bytes;sha256=$file.sha256;status=$Record.status}
}
function Assert-SetupStartingProvenance {
    param([Parameter(Mandatory)][hashtable]$Context,[Parameter(Mandatory)][string]$ManifestPath)
    $ErrorActionPreference='Stop'
    $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        $identity=Get-SetupReceiptContext $Context
        $root=$identity.install_root
        if(Test-Path -LiteralPath $root){Assert-SetupReceiptPath $root -Protected|Out-Null}else{Assert-SetupReceiptPath (Split-Path -Parent $root)|Out-Null}
        $archive=Get-SetupArchiveRows $ManifestPath $identity -ExistingOnly
        $previous=$null
        if(Test-Path -LiteralPath (Join-Path $root '.setup-source-ownership.json')){$previous=Read-SetupSourceHandoff $identity}
        else{
            $tree=Get-SetupReceiptTree $root
            foreach($path in $tree.files){if(!$archive.ContainsKey($path)){throw 'Unproven existing source file; preserved.'}}
            foreach($path in $tree.directories){if(!@($archive.Keys|Where-Object{$_.StartsWith($path+'/',[StringComparison]::OrdinalIgnoreCase)}).Count){throw 'Unproven existing directory; preserved.'}}
        }
        $proof=[pscustomobject]@{nonce=[guid]::NewGuid().ToString('N');context=$identity;manifest_path=(Assert-SetupReceiptPath $ManifestPath);previous_sha256=$(if($previous){$previous.file.sha256}else{$null})}
        $script:SetupReceiptProofs[$proof.nonce]=@{proof=$proof;context_json=($identity|ConvertTo-Json -Compress);manifest_path=$proof.manifest_path;previous_sha256=$proof.previous_sha256}
        $proof
    }finally{foreach($lock in $script:SetupReceiptLocks){$lock.Dispose()}}
}
function Write-SetupSourceReceipt {
    param([Parameter(Mandatory)][hashtable]$Context,[Parameter(Mandatory)]$StartingProof)
    $ErrorActionPreference='Stop'
    $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        $identity=Get-SetupReceiptContext $Context
        $registered=$script:SetupReceiptProofs[$StartingProof.nonce]
        if(!$StartingProof.nonce -or !$registered -or ![object]::ReferenceEquals($registered.proof,$StartingProof)){throw 'Registered starting provenance required.'}
        Test-SetupReceiptIdentity ($registered.context_json|ConvertFrom-Json) $identity
        $archive=Get-SetupArchiveRows $registered.manifest_path $identity
        $tree=Get-SetupReceiptTree $identity.install_root;$rows=@()
        foreach($directory in $tree.directories){
            if($directory -notmatch '^(\.venv|publisher-wheels|wheelhouse|tools|tools/ffmpeg)(/|$)' -and !@($archive.Keys|Where-Object{$_.StartsWith($directory+'/',[StringComparison]::OrdinalIgnoreCase)}).Count){throw 'Unknown generated directory; preserved.'}
        }
        foreach($relative in $tree.files){
            if($relative -eq '.setup-source-ownership.json'){continue}
            if($relative -eq '.install-complete'){throw 'Source handoff must precede marker.'}
            if(!$archive.ContainsKey($relative) -and $relative -notin @('native-build-receipt.json','AutoClip.lnk','.inno-runtime-tools.json') -and $relative -notmatch '^(\.venv|publisher-wheels|wheelhouse|tools/ffmpeg)/'){throw 'Unknown generated output; preserved.'}
            $file=Get-SetupReceiptFile (Join-Path $identity.install_root $relative)
            $rows+=,[pscustomobject]@{path=$relative;bytes=$file.bytes;sha256=$file.sha256}
        }
        $native=Get-SetupReceiptFile (Join-Path $identity.install_root 'native-build-receipt.json')
        $receipt=Read-SetupReceiptJson $native
        if($receipt.profile -cne $identity.profile){throw 'Native profile differs.'}
        $health=Assert-SetupHealth $identity $receipt.setup_app_health
        $launcher=Assert-SetupShortcut (Join-Path $identity.install_root 'AutoClip.lnk') $identity $receipt.setup_owned_launcher.sha256 -Folder
        if($receipt.setup_owned_launcher.bytes -ne $launcher.bytes -or $receipt.setup_owned_launcher.archive_sha256 -cne $identity.archive_sha256 -or $receipt.setup_owned_launcher.release_manifest_sha256 -cne $identity.release_manifest_sha256){throw 'Source launcher identity differs.'}
        $record=[ordered]@{schema_version=1;status='VERIFIED_SOURCE_OUTPUTS';context=$identity;native_receipt=@{path='native-build-receipt.json';bytes=$native.bytes;sha256=$native.sha256};app_health=$health;launcher=$launcher;files=@($rows|Sort-Object path);directories=@($tree.directories|Sort-Object)}
        $result=Write-SetupReceiptRecord (Join-Path $identity.install_root '.setup-source-ownership.json') $record $registered.previous_sha256
        $script:SetupReceiptProofs.Remove($StartingProof.nonce);$result
    }finally{foreach($lock in $script:SetupReceiptLocks){$lock.Dispose()}}
}
function Write-SetupInstallationReceipt {
    param([Parameter(Mandatory)][hashtable]$Context,[Parameter(Mandatory)][string]$HandoffSha256,[Parameter(Mandatory)][string]$SetupRoot,[Parameter(Mandatory)][string]$SetupExePath,[Parameter(Mandatory)][string]$SetupSha256,[Parameter(Mandatory)][object[]]$NativeFiles,[Parameter(Mandatory)][string]$NativeShortcutPath,[Parameter(Mandatory)][string]$NativeShortcutSha256,[Parameter(Mandatory)][hashtable]$Registration,[string]$ReceiptPath,[object[]]$BaseFiles,[string]$MaintenanceShortcutPath,[string]$MaintenanceShortcutSha256)
    $ErrorActionPreference='Stop'
    $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        $identity=Get-SetupReceiptContext $Context;$SetupRoot=Assert-SetupReceiptPath $SetupRoot -Protected
        $directory=Join-Path $SetupRoot 'installation-receipts'
        $expectedReceiptPath=Join-Path $directory ($identity.release_id+'.json')
        if($ReceiptPath -and (Assert-SetupReceiptPath $ReceiptPath) -ine $expectedReceiptPath){throw 'Final receipt must use the canonical installation-receipts location.'}
        if($SetupRoot -ieq $identity.install_root -or $SetupRoot.StartsWith($identity.install_root+'\',[StringComparison]::OrdinalIgnoreCase) -or $identity.install_root.StartsWith($SetupRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Setup and release scopes overlap.'}
        $handoff=Read-SetupSourceHandoff $identity $HandoffSha256
        $marker=Get-SetupReceiptFile (Join-Path $identity.install_root '.install-complete')
        $setupExe=Get-SetupReceiptFile $SetupExePath $SetupSha256
        $native=Get-SetupReceiptRows $NativeFiles $SetupRoot
        $notices=@('notices/inno-setup-7.1.0-LICENSE.txt','notices/uv-0.12.19-LICENSE-MIT.txt','notices/uv-0.12.19-LICENSE-APACHE.txt','notices/setup-tool-sources.md')
        foreach($path in $notices){if(!$native.ContainsKey($path)){throw 'Required native notice is missing.'}}
        $uninstall=@($native.Keys|Where-Object{$_ -match '^unins[0-9]+\.exe$'})
        if($uninstall.Count -ne 1 -or !$native.ContainsKey(($uninstall[0] -replace '\.exe$','.dat'))){throw 'Exact generated native uninstaller pair required.'}
        $cleanupHelpers=@('uninstall-owned-release.ps1','write-setup-receipt.ps1','remove-owned-file.ps1','run-source-build.ps1','update.ps1')
        if($BaseFiles){$cleanupHelpers+=@('update-app.ps1','initialize-selection.ps1','run-maintenance.ps1','AutoClip-Maintenance.exe','install.ps1','installer-dependencies-v1.json')}
        $presentHelpers=@($cleanupHelpers|Where-Object{$native.ContainsKey($_)})
        if(($BaseFiles -or $presentHelpers.Count) -and $presentHelpers.Count -ne $cleanupHelpers.Count){throw 'Cleanup helper inventory must be complete.'}
        foreach($path in $native.Keys){if($path -notin $notices -and $path -notin $cleanupHelpers -and $path -notin @($uninstall[0],($uninstall[0] -replace '\.exe$','.dat'),($uninstall[0] -replace '\.exe$','.msg'))){throw 'Unsupported native output scope.'}}
        $nativeUninstaller=Join-Path $SetupRoot $uninstall[0]
        $expectedCommand=if($Registration.ContainsKey('uninstall_command')){$Registration.uninstall_command}else{'"'+$nativeUninstaller+'"'}
        if($Registration.key -cne 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D7451842-48F4-487B-80E0-5C7E9E326342}_is1' -or $Registration.view -cne 'Registry64' -or $Registration.install_location -ine ($SetupRoot+'\') -or !$expectedCommand -or $Registration.uninstall_string -cne $expectedCommand -or ($Registration.ContainsKey('native_uninstaller') -and $Registration.native_uninstaller -ine $nativeUninstaller)){throw 'Native registration snapshot binding differs.'}
        $baseRows=@()
        if($BaseFiles){
            if($BaseFiles.Count -ne 2 -or @($BaseFiles.path|Select-Object -Unique).Count -ne 2 -or @($BaseFiles|Where-Object{$_.path -cnotin @('Start-AutoClip.ps1','Start-AutoClip-Desktop.ps1')}).Count){throw 'Exact finite stable launcher pair required.'}
            $baseRows=@((Get-SetupReceiptRows $BaseFiles (Split-Path -Parent $identity.install_root)).Values|Sort-Object path)
        }
        $shortcut=Assert-SetupShortcut $NativeShortcutPath $identity $NativeShortcutSha256 -Stable:([bool]$BaseFiles)
        $releaseRows=@($handoff.record.files)+@([pscustomobject]@{path='.setup-source-ownership.json';bytes=$handoff.file.bytes;sha256=$handoff.file.sha256},[pscustomobject]@{path='.install-complete';bytes=$marker.bytes;sha256=$marker.sha256})
        $registrationRecord=[ordered]@{key=$Registration.key;view=$Registration.view;install_location=$Registration.install_location;uninstall_string=$Registration.uninstall_string;native_uninstaller=$nativeUninstaller}
        if($Registration.ContainsKey('quiet_uninstall_command')){$registrationRecord.quiet_uninstall_string=$Registration.quiet_uninstall_command}
        if($Registration.ContainsKey('values')){$registrationRecord.values=$Registration.values;$registrationRecord.subkeys=$Registration.subkeys}
        $record=[ordered]@{schema_version=1;status='COMPLETE';context=$identity;setup_root=$SetupRoot;setup_sha256=$setupExe.sha256;source_handoff=@{path=$handoff.file.path;bytes=$handoff.file.bytes;sha256=$handoff.file.sha256};app_health=$handoff.record.app_health;release_files=@($releaseRows|Sort-Object path);release_directories=$handoff.record.directories;setup_files=@($native.Values|Sort-Object path);shortcuts=@($handoff.record.launcher,$shortcut);registration=$registrationRecord}
        if($BaseFiles){
            $maintenanceLink=Get-SetupReceiptFile $MaintenanceShortcutPath $MaintenanceShortcutSha256
            $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($maintenanceLink.path)
            if($link.TargetPath -ine (Join-Path $SetupRoot 'AutoClip-Maintenance.exe') -or $link.Arguments -cne '' -or $link.WorkingDirectory -ine $SetupRoot){throw 'Actual maintenance shortcut semantics differ.'}
            $record.schema_version=2;$record.base_files=$baseRows
            $record.shortcuts+=@{path=$maintenanceLink.path;bytes=$maintenanceLink.bytes;sha256=$maintenanceLink.sha256}
        }
        if(!(Test-Path -LiteralPath $directory)){[IO.Directory]::CreateDirectory($directory,(Get-Acl -LiteralPath $SetupRoot))|Out-Null}
        Write-SetupReceiptRecord $expectedReceiptPath $record
    }finally{foreach($lock in $script:SetupReceiptLocks){$lock.Dispose()}}
}

# The wizard calls this entry point after native files and registration exist.
# Importing the library for source ownership has no finalization side effects.
if($Finalize){
    $ErrorActionPreference='Stop'
    $outerLocks=[Collections.Generic.List[IO.FileStream]]::new();$targetLock=$null
    $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
    try{
        if(![Environment]::Is64BitProcess -or ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Finalization requires the ordinary native64 recipient.'}
        if(!$RequestPath -or $RequestSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'A pinned finalization request is required.'}
        $input=Get-SetupReceiptFile $RequestPath $RequestSha256;$outerLocks.Add($input.stream)
        if($input.bytes -gt 65536){throw 'Finalization request exceeds bounded size.'}
        $request=Read-SetupReceiptJson $input
        $fields=@('schema_version','context','handoff_sha256','setup_path','setup_sha256','source_build_helper_sha256','notices','helpers','native_shortcut_path','native_shortcut_sha256','native_uninstaller','uninstall_command','quiet_uninstall_command')
        if($request.schema_version -isnot [int] -or $request.schema_version -ne 1 -or @($request.PSObject.Properties).Count -ne $fields.Count -or @($request.PSObject.Properties.Name|Where-Object{$_ -notin $fields}).Count){throw 'Unsupported finalization request schema.'}
        $context=@{};foreach($property in $request.context.PSObject.Properties){$context[$property.Name]=$property.Value}
        $identity=Get-SetupReceiptContext $context
        $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $setupRoot=Join-Path $local 'AutoClip/Setup'
        $logs=Join-Path $setupRoot 'logs'
        if([IO.Path]::GetFileName($RequestPath) -cne 'final-request.json' -or !([IO.Path]::GetFullPath($RequestPath)).StartsWith($logs+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Finalization request must belong to protected setup logs.'}
        $own=Get-SetupReceiptFile $PSCommandPath $identity.source_helper_sha256;$outerLocks.Add($own.stream)
        $supervisor=Get-SetupReceiptFile (Join-Path $PSScriptRoot 'run-source-build.ps1') $request.source_build_helper_sha256;$outerLocks.Add($supervisor.stream)
        $reader=[IO.StreamReader]::new($supervisor.stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
        try{$source=$reader.ReadToEnd()}finally{$reader.Dispose();$supervisor.stream.Position=0}
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'Pinned source supervisor does not parse.'}
        foreach($name in @('Assert-BuildPath','New-BuildDirectoryAcl','Get-BuildStoragePath','Initialize-BuildStorage','Get-BuildTargetIdentity','Open-BuildTargetLock')){
            $nodes=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false))
            if($nodes.Count -ne 1){throw 'Required pinned target lock function is absent or ambiguous.'}
            . ([scriptblock]::Create($nodes[0].Extent.Text))
        }
        $targetLock=Open-BuildTargetLock $identity.install_root
        $key='Software\Microsoft\Windows\CurrentVersion\Uninstall\{D7451842-48F4-487B-80E0-5C7E9E326342}_is1'
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
        try{
            $registrationKey=$base.OpenSubKey($key,$false)
            if(!$registrationKey){throw 'Native per-user uninstall registration is missing.'}
            try{
                $values=@($registrationKey.GetValueNames()|Sort-Object|ForEach-Object{[ordered]@{name=$_;kind=$registrationKey.GetValueKind($_).ToString();value=$registrationKey.GetValue($_,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}})
                $subkeys=@($registrationKey.GetSubKeyNames())
                if($subkeys.Count){throw 'Unexpected native uninstall registration subkey; preserved.'}
                $registration=@{key=$key;view='Registry64';install_location=$registrationKey.GetValue('InstallLocation');uninstall_string=$registrationKey.GetValue('UninstallString');values=$values;subkeys=$subkeys}
            }finally{$registrationKey.Dispose()}
        }finally{$base.Dispose()}
        if($registration.install_location -ine ($setupRoot+'\') -or $registration.uninstall_string -isnot [string]){throw 'Native registration does not identify this setup shell.'}
        if($request.uninstall_command -isnot [string] -or !$request.uninstall_command -or $registration.uninstall_string -cne $request.uninstall_command){throw 'Registered loader differs from the pinned setup request.'}
        $quiet=@($registration.values|Where-Object name -CEQ 'QuietUninstallString')
        if($request.quiet_uninstall_command -isnot [string] -or !$request.quiet_uninstall_command -or $quiet.Count -ne 1 -or $quiet[0].value -cne $request.quiet_uninstall_command){throw 'Registered quiet loader differs from the pinned setup request.'}
        $match=[regex]::Match($request.native_uninstaller,'^'+[regex]::Escape($setupRoot)+'\\(?<file>unins[0-9]+\.exe)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if(!$match.Success){throw 'Native uninstaller path is outside its fixed scope.'}
        $registration.native_uninstaller=$request.native_uninstaller;$registration.uninstall_command=$request.uninstall_command
        $registration.quiet_uninstall_command=$request.quiet_uninstall_command
        $rows=@($request.notices)+@($request.helpers)
        $helperNames=@('uninstall-owned-release.ps1','write-setup-receipt.ps1','remove-owned-file.ps1','run-source-build.ps1','update.ps1')
        $hasMaintenance=@($request.helpers|Where-Object path -CEQ 'AutoClip-Maintenance.exe').Count -eq 1
        if($hasMaintenance){$helperNames+=@('update-app.ps1','initialize-selection.ps1','run-maintenance.ps1','AutoClip-Maintenance.exe','install.ps1','installer-dependencies-v1.json')}
        if(@($request.helpers).Count -ne $helperNames.Count -or @($request.helpers|Where-Object{$_.path -cnotin $helperNames}).Count -or @($request.helpers.path|Select-Object -Unique).Count -ne $helperNames.Count){throw 'Exact finite durable cleanup helpers required.'}
        $exe=$match.Groups['file'].Value
        foreach($relative in @($exe,($exe -replace '\.exe$','.dat'),($exe -replace '\.exe$','.msg'))){
            $path=Join-Path $setupRoot $relative
            if($relative -like '*.msg' -and !(Test-Path -LiteralPath $path)){continue}
            $file=Get-SetupReceiptFile $path;$outerLocks.Add($file.stream)
            $rows+=@{path=$relative;bytes=$file.bytes;sha256=$file.sha256}
        }
        $expectedShortcut=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) 'AutoClip/AutoClip.lnk'
        if($request.native_shortcut_path -ine $expectedShortcut){throw 'Native shortcut path is outside its fixed scope.'}
        $baseRows=@()
        if($hasMaintenance){foreach($name in @('Start-AutoClip.ps1','Start-AutoClip-Desktop.ps1')){$file=Get-SetupReceiptFile (Join-Path (Split-Path -Parent $identity.install_root) $name);$baseRows+=@{path=$name;bytes=$file.bytes;sha256=$file.sha256}}}
        $maintenanceArgs=@{}
        if($hasMaintenance){$link=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) 'AutoClip/AutoClip Maintenance.lnk';$file=Get-SetupReceiptFile $link;$maintenanceArgs=@{MaintenanceShortcutPath=$link;MaintenanceShortcutSha256=$file.sha256}}
        $descriptor=Write-SetupInstallationReceipt -Context $context -HandoffSha256 $request.handoff_sha256 -SetupRoot $setupRoot -SetupExePath $request.setup_path -SetupSha256 $request.setup_sha256 -NativeFiles $rows -NativeShortcutPath $expectedShortcut -NativeShortcutSha256 $request.native_shortcut_sha256 -Registration $registration -BaseFiles $baseRows @maintenanceArgs
        $outputPath=$RequestPath+'.receipt.json'
        $script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new()
        Write-SetupReceiptRecord $outputPath $descriptor|Out-Null
        $descriptor|ConvertTo-Json -Compress
    }catch{
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }finally{
        if($targetLock){$targetLock.Dispose()}
        foreach($lock in $outerLocks){$lock.Dispose()}
        foreach($lock in $script:SetupReceiptLocks){$lock.Dispose()}
    }
}
