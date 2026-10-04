param(
    [Parameter(Mandatory)][string]$BootstrapPath, [Parameter(Mandatory)][string]$BootstrapSha256,
    [Parameter(Mandatory)][string]$ManifestPath, [Parameter(Mandatory)][string]$ManifestSha256,
    [Parameter(Mandatory)][string]$DownloaderPath, [Parameter(Mandatory)][string]$DownloaderSha256,
    [Parameter(Mandatory)][string]$ArgumentsPath, [Parameter(Mandatory)][string]$ArgumentsSha256,
    [Parameter(Mandatory)][string]$AttemptDirectory,
    [Parameter(Mandatory)][string]$HelperSha256,
    [switch]$Worker,
    [switch]$RequestCancellation
)
$ErrorActionPreference = 'Stop'
function Assert-BuildPath([string]$Path,[switch]$Protected,[switch]$SystemExecutable) {
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path -match '["\r\n]' -or
        $Path -match '(^|[\\/])\.\.?([\\/]|$)' -or $Path.Substring(3).Contains(':')) { throw 'Unsafe build path.' }
    $full=[IO.Path]::GetFullPath($Path); $cursor=$full
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Build path contains a reparse point.' }
        }
        $next=Split-Path -Parent $cursor; if($next -eq $cursor){break}; $cursor=$next
    }
    if(Test-Path -LiteralPath $full) {
        $acl=Get-Acl -LiteralPath $full
        $trusted=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
        if($SystemExecutable) { $trusted += ([Security.Principal.NTAccount]::new('NT SERVICE\TrustedInstaller')).Translate([Security.Principal.SecurityIdentifier]).Value }
        if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted -or ($Protected -and -not $acl.AreAccessRulesProtected)) { throw 'Build path ownership/DACL is invalid.' }
        $writes=278 -bor 64 -bor 65536 -bor 262144 -bor 524288 -bor 268435456 -bor 1073741824
        foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and ([long]$rule.FileSystemRights -band $writes)) { throw 'Build path grants foreign write access.' }
        }
    }
    return $full
}
function New-BuildDirectoryAcl {
    $acl=[Security.AccessControl.DirectorySecurity]::new(); $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false)
    foreach($id in @($sid.Value,'S-1-5-18','S-1-5-32-544')) { $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','ContainerInherit,ObjectInherit','None','Allow')) }
    return $acl
}
function Get-BuildStoragePath([ValidateSet('logs','locks')][string]$Kind) {
    Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) ('AutoClip/Setup/'+$Kind)
}
function Initialize-BuildStorage([ValidateSet('logs','locks')][string]$Kind,[switch]$ExistingOnly) {
    $local=Assert-BuildPath ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))
    if(-not(Test-Path -LiteralPath $local -PathType Container)){throw 'Recipient local application data is missing.'}
    $path=$local
    foreach($part in @('AutoClip','Setup',$Kind)) {
        $path=Join-Path $path $part
        Assert-BuildPath $path | Out-Null
        if(Test-Path -LiteralPath $path) {
            if(-not(Test-Path -LiteralPath $path -PathType Container)){throw 'Build storage parent is not a directory.'}
            Assert-BuildPath $path -Protected:($part -ne 'AutoClip') | Out-Null
        } elseif(-not $ExistingOnly) {
            [IO.Directory]::CreateDirectory($path,(New-BuildDirectoryAcl)) | Out-Null
            Assert-BuildPath $path -Protected | Out-Null
        }
    }
    return $path
}
function Get-BuildTargetIdentity([string]$Root) {
    $path=(Assert-BuildPath $Root).TrimEnd('\')
    $missing=@()
    while(-not(Test-Path -LiteralPath $path)) {
        $missing=@([IO.Path]::GetFileName($path))+$missing
        $parent=Split-Path -Parent $path
        if(-not $parent -or $parent -eq $path){throw 'Install target has no existing local ancestor.'}
        $path=$parent
    }
    if(-not(Test-Path -LiteralPath $path -PathType Container)){throw 'Install target ancestor is not a directory.'}
    # .NET expands existing short names; an absent suffix can prevent expansion
    # of its immediate ancestor, so resolve that ancestor before appending it.
    $path=Assert-BuildPath $path
    foreach($part in $missing){$path=Join-Path $path $part}
    return (Assert-BuildPath $path).TrimEnd('\').ToUpperInvariant()
}
function Open-BuildTargetLock([string]$Root) {
    $directory=Initialize-BuildStorage 'locks'
    $setup=Split-Path -Parent $directory
    $normalized=Get-BuildTargetIdentity $Root
    if($normalized -eq $setup -or $normalized.StartsWith($setup+'\',[StringComparison]::OrdinalIgnoreCase) -or $setup.StartsWith($normalized+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Install target overlaps protected build storage.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $path=Join-Path $directory ($key+'.lock')
    Assert-BuildPath $path | Out-Null
    if((Test-Path -LiteralPath $path) -and -not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Target build lock is not a regular file.'}
    try {$stream=[IO.File]::Open($path,'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{throw 'Another source worker holds this install target, or its lock cannot be opened.'}
    try {
        Assert-BuildPath $path | Out-Null
        if($stream.Length -ne 0){throw 'Target build lock changed.'}
        return $stream
    } catch {$stream.Dispose();throw}
}
function Open-BuildInput([string]$Path,[string]$Pin) {
    $Path=Assert-BuildPath $Path
    if($Pin -notmatch '^[a-fA-F0-9]{64}$' -or -not(Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Build input pin or regular file is missing.' }
    $stream=[IO.File]::Open($Path,'Open','Read','Read')
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        if([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') -ne $Pin) { throw 'Build input SHA-256 differs.' }
        $stream.Position=0; return $stream
    } catch { $stream.Dispose(); throw } finally { $sha.Dispose() }
}
function Read-BuildArguments($Stream) {
    if($Stream.Length -gt 65536) { throw 'Build argument JSON is too large.' }
    $reader=[IO.StreamReader]::new($Stream,[Text.Encoding]::UTF8,$true,1024,$true)
    try { $document=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose(); $Stream.Position=0 }
    if($document.schema_version -ne 1 -or -not $document.parameters -or
        @($document.PSObject.Properties.Name | Where-Object {$_ -notin @('schema_version','parameters')}).Count) { throw 'Invalid build argument schema.' }
    $paths=@('InstallRoot','ArchivePath','ExternalCache','NativeBuildRoot','MsysBash','MsysPackageReceiptPath','MsysBaseArchivePath','GitExePath','UvExePath','CudaRoot','FfmpegArchivePath','CpuNativeArtifactPath','NvidiaNativeArtifactPath')
    $pins=@('MsysPackageReceiptSha256','ToolArchiveHelperSha256','RuntimeToolPathHelperSha256','AppHealthHelperSha256','SetupReceiptHelperSha256','CpuNativeHelperSha256','PythonPrerequisiteHelperSha256','VcRuntimeHelperSha256')
    $switches=@('NonInteractive','NoPrerequisiteAcquisition','SkipDesktopShortcut','InstallNvidiaGpu','AcceptNvidiaTerms','AcceptCublasTerms','AcceptMicrosoftTerms','AllowPinnedNvidiaAcquisition','OfflinePublisherCache')
    $result=@{}
    foreach($property in $document.parameters.PSObject.Properties) {
        $name=$property.Name; $value=$property.Value
        if($name -in $switches) { if($value -isnot [bool]){throw 'Build switch requires Boolean.'} }
        elseif($name -in $paths) { if($value -isnot [string] -or -not $value){throw 'Build path requires string.'}; Assert-BuildPath $value | Out-Null }
        elseif($name -in $pins) { if($value -isnot [string] -or $value -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid build parameter pin.'} }
        else { throw "Unsupported build parameter: $name" }
        $result[$name]=$value
    }
    foreach($name in @('NonInteractive','NoPrerequisiteAcquisition','SkipDesktopShortcut')) { if($result[$name] -ne $true){throw "Required build switch: $name"} }
    foreach($name in @('InstallRoot','ArchivePath')) { if(-not $result[$name]){throw "Required build path: $name"} }
    return $result
}
function Quote-BuildArgument([string]$Value) {
    # Native CommandLineToArgvW quoting, including trailing backslashes.
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Assert-BuildCancelPath {
    Assert-BuildPath $cancel | Out-Null
    if((Test-Path -LiteralPath $cancel) -and -not(Test-Path -LiteralPath $cancel -PathType Leaf)) { throw 'Cancellation signal must be a regular file.' }
}
function Open-BuildDecisionLock {
    $path=Join-Path $AttemptDirectory 'decision.lock'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true) {
        Assert-BuildPath $AttemptDirectory -Protected | Out-Null
        Assert-BuildPath $path | Out-Null
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Protected build decision lock is missing.'}
        try { $stream=[IO.File]::Open($path,'Open','ReadWrite','None'); if($stream.Length -ne 0){$stream.Dispose();throw 'Build decision lock changed.'}; return $stream }
        catch [IO.IOException] { if($watch.Elapsed.TotalSeconds -ge 10){throw 'Build decision lock remains busy.'}; Start-Sleep -Milliseconds 100 }
    }
}
function Test-BuildCommit {
    $path=Join-Path $AttemptDirectory 'commit.json'; Assert-BuildPath $path | Out-Null
    if(-not(Test-Path -LiteralPath $path)){return $false}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Build commit is not a regular file.'}
    $file=[IO.File]::Open($path,'Open','Read','Read')
    try {
        if($file.Length -gt 8192){throw 'Build commit is too large.'}
        $reader=[IO.StreamReader]::new($file,[Text.Encoding]::UTF8,$true,1024,$true)
        try{$commit=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
    } finally{$file.Dispose()}
    $manifestReader=[IO.StreamReader]::new($locks[1],[Text.Encoding]::UTF8,$true,1024,$true)
    try{$manifest=$manifestReader.ReadToEnd()|ConvertFrom-Json}finally{$manifestReader.Dispose();$locks[1].Position=0}
    if($commit.schema_version -isnot [int] -or $commit.schema_version -ne 1 -or $commit.decision -ne 'COMMIT_STARTED' -or
       $commit.install_root -ne $arguments.InstallRoot -or $commit.dependency_manifest_sha256 -ne $ManifestSha256 -or
       [string]$commit.archive_sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $commit.archive_sha256 -ne $manifest.target_release.sha256 -or
       [string]$commit.release_manifest_sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $commit.release_manifest_sha256 -ne $manifest.target_release.manifest_sha256 -or
       @($commit.PSObject.Properties.Name|Where-Object{$_ -notin @('schema_version','decision','install_root','dependency_manifest_sha256','archive_sha256','release_manifest_sha256')}).Count) { throw 'Build commit binding is invalid.' }
    if([IO.File]::Exists($cancel)){throw 'Build decision contains both commit and cancellation.'}
    return $true
}
function Save-BuildStatus([string]$State,$Process,$ExitCode) {
    $path=Join-Path $AttemptDirectory 'status.json'; Assert-BuildPath $path | Out-Null
    $pending=Join-Path $AttemptDirectory 'status.pending'; Assert-BuildPath $pending | Out-Null
    $file=[IO.File]::Open($pending,'CreateNew','Write','None')
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes(([ordered]@{schema_version=1;attempt_directory=$AttemptDirectory;install_root=$arguments.InstallRoot;helper_sha256=$HelperSha256;bootstrap_sha256=$BootstrapSha256;manifest_sha256=$ManifestSha256;downloader_sha256=$DownloaderSha256;arguments_sha256=$ArgumentsSha256;status=$State;phase='Source build and installed-runtime verification';worker_pid=$Process.Id;worker_start_utc=$Process.StartTime.ToUniversalTime().ToString('o');exit_code=$ExitCode;cancel_requested=[IO.File]::Exists($cancel)}|ConvertTo-Json))
        $file.Write($bytes,0,$bytes.Length)
    } finally { $file.Dispose() }
    try {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while($true) {
            Assert-BuildPath $path | Out-Null
            Assert-BuildPath $pending | Out-Null
            try {
                if([IO.File]::Exists($path)){[IO.File]::Replace($pending,$path,[NullString]::Value)}else{[IO.File]::Move($pending,$path)}
                return
            } catch [IO.IOException] {
                if(($_.Exception.HResult -band 65535) -notin @(32,33)){throw}
                # A normal reader can deny delete sharing: skip live display frames.
                # Terminal evidence is mandatory; refuse if it cannot be published.
                if($State -ne 'TERMINAL'){return}
                if($watch.Elapsed.TotalSeconds -ge 10){throw 'Terminal build status remains busy.'}
                Start-Sleep -Milliseconds 100
            }
        }
    } finally {
        if([IO.File]::Exists($pending)) {
            Assert-BuildPath $pending | Out-Null
            if([Convert]::ToBase64String([IO.File]::ReadAllBytes($pending)) -ne [Convert]::ToBase64String($bytes)){throw 'Build status staging changed.'}
            [IO.File]::Delete($pending)
        }
    }
}
function Save-BuildTail {
    $parts=@()
    foreach($name in @('stdout.log','stderr.log')) {
        $path=Join-Path $AttemptDirectory $name; Assert-BuildPath $path | Out-Null
        $file=[IO.File]::Open($path,'Open','Read','ReadWrite')
        try { $file.Position=[Math]::Max(0,$file.Length-2048); $bytes=New-Object byte[] 2048; $count=$file.Read($bytes,0,$bytes.Length); $parts += [Text.Encoding]::UTF8.GetString($bytes,0,$count) }
        finally { $file.Dispose() }
    }
    $path=Join-Path $AttemptDirectory 'tail.txt'; Assert-BuildPath $path | Out-Null
    try { [IO.File]::WriteAllText($path,($parts -join "`r`n"),[Text.Encoding]::UTF8) }
    catch [IO.IOException] {
        # A wizard reader can deny write sharing; skip this display frame only.
        if(($_.Exception.HResult -band 65535) -notin @(32,33)){throw}
    }
}
$locks=[Collections.Generic.List[IO.FileStream]]::new()
$targetLock=$null
try {
    foreach($buildInput in @(@($BootstrapPath,$BootstrapSha256),@($ManifestPath,$ManifestSha256),@($DownloaderPath,$DownloaderSha256),@($ArgumentsPath,$ArgumentsSha256))) { $locks.Add((Open-BuildInput $buildInput[0] $buildInput[1])) }
    # Keep the first-party worker script immutable while its second process opens it.
    $locks.Add((Open-BuildInput $PSCommandPath $HelperSha256))
    $arguments=Read-BuildArguments $locks[3]
    if($Worker -and $RequestCancellation){throw 'Worker and cancellation request modes are exclusive.'}
    $AttemptDirectory=Assert-BuildPath $AttemptDirectory
    $release=[IO.Path]::GetFullPath($arguments.InstallRoot).TrimEnd('\')
    if($AttemptDirectory -eq $release -or $AttemptDirectory.StartsWith($release+'\',[StringComparison]::OrdinalIgnoreCase) -or $release.StartsWith($AttemptDirectory.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build logs and release must be separate paths.' }
    $cancel=Join-Path $AttemptDirectory 'cancel.txt'
    $parent=Split-Path -Parent $AttemptDirectory
    $durable=$parent -ieq (Get-BuildStoragePath 'logs')
    if($durable -and [IO.Path]::GetFileName($AttemptDirectory) -notmatch '^source-build-[A-Za-z0-9_.-]+-[0-9]+$'){throw 'Unrecognized durable build attempt name.'}
    if($RequestCancellation) {
        if($durable){Initialize-BuildStorage 'logs' -ExistingOnly | Out-Null}
        else {Assert-BuildPath $parent | Out-Null; if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Build request staging parent is missing.'}}
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while(-not(Test-Path -LiteralPath (Join-Path $AttemptDirectory 'decision.lock'))) {
            Assert-BuildPath $AttemptDirectory | Out-Null
            if($durable){Initialize-BuildStorage 'logs' -ExistingOnly | Out-Null}
            if($watch.Elapsed.TotalSeconds -ge 10){exit 2}; Start-Sleep -Milliseconds 100
        }
        $decision=Open-BuildDecisionLock
        try {
            Assert-BuildCancelPath
            if(Test-BuildCommit){exit 170}
            [IO.File]::WriteAllText($cancel,'cancel',[Text.Encoding]::UTF8)
            exit 0
        } finally{$decision.Dispose()}
    }
    if($Worker) {
        [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        Assert-BuildPath $AttemptDirectory -Protected | Out-Null
        if(-not(Test-Path -LiteralPath $AttemptDirectory -PathType Container)){throw 'Worker attempt is missing.'}
        Assert-BuildCancelPath
        if([IO.File]::Exists($cancel)){exit 1223}
        $targetLock=Open-BuildTargetLock $arguments.InstallRoot
        $arguments.CancelPath=$cancel
        $arguments.SecureAcquisitionManifestPath=$ManifestPath
        $arguments.SecureAcquisitionManifestSha256=$ManifestSha256
        $arguments.SecureDownloaderSha256=$DownloaderSha256
        if ($arguments.SetupReceiptHelperSha256) { $arguments.BootstrapIdentitySha256=$BootstrapSha256 }
        $global:LASTEXITCODE=0
        & $BootstrapPath @arguments
        $succeeded=$?; $code=[int]$LASTEXITCODE
        Test-BuildCommit | Out-Null
        if([IO.File]::Exists($cancel)){exit 1223}
        if($code -ne 0){exit $code}
        if(-not $succeeded){exit 1}
        exit 0
    }
    if(Test-Path -LiteralPath $AttemptDirectory){throw 'Build attempt directory must be fresh.'}
    if($durable){Initialize-BuildStorage 'logs' | Out-Null}
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Build attempt parent missing.'}
    Assert-BuildPath $parent | Out-Null
    [IO.Directory]::CreateDirectory($AttemptDirectory,(New-BuildDirectoryAcl))|Out-Null
    Assert-BuildPath $AttemptDirectory -Protected | Out-Null
    $decisionFile=[IO.File]::Open((Join-Path $AttemptDirectory 'decision.lock'),'CreateNew','Write','None'); $decisionFile.Dispose()
    $windows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $powershell=Join-Path $windows 'System32/WindowsPowerShell/v1.0/powershell.exe'
    if([Environment]::Is64BitOperatingSystem -and -not[Environment]::Is64BitProcess){$powershell=Join-Path $windows 'Sysnative/WindowsPowerShell/v1.0/powershell.exe'}
    Assert-BuildPath $powershell -SystemExecutable | Out-Null
    $args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Quote-BuildArgument $PSCommandPath),'-Worker')
    foreach($name in @('BootstrapPath','BootstrapSha256','ManifestPath','ManifestSha256','DownloaderPath','DownloaderSha256','ArgumentsPath','ArgumentsSha256','AttemptDirectory','HelperSha256')) { $args += '-'+$name; $args += Quote-BuildArgument ([string](Get-Variable -Name $name -ValueOnly)) }
    $process=Start-Process -FilePath $powershell -ArgumentList ($args -join ' ') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $AttemptDirectory 'stdout.log') -RedirectStandardError (Join-Path $AttemptDirectory 'stderr.log')
    $processHandle=$process.Handle # Materialize handle before quick child exit.
    Save-BuildStatus 'RUNNING' $process $null
    while(-not $process.WaitForExit(200)) { Assert-BuildCancelPath; Save-BuildTail; Save-BuildStatus $(if([IO.File]::Exists($cancel)){'CANCELLATION_PENDING'}else{'RUNNING'}) $process $null }
    $process.WaitForExit(); $exitCode=[int]$process.ExitCode
    Test-BuildCommit | Out-Null
    if([IO.File]::Exists($cancel)){$exitCode=1223}
    Save-BuildTail; Save-BuildStatus 'TERMINAL' $process $exitCode
    exit $exitCode
} finally {
    # An observation failure is not worker termination. Keep input locks until
    # the owned worker really exits; never kill a native/vendor descendant.
    if($process -and -not $Worker) { while(-not $process.WaitForExit(200)) {}; $process.Dispose() }
    if($targetLock){$targetLock.Dispose()}
    foreach($lock in $locks){$lock.Dispose()}
}
