# Read-only planning is the default. Base provisioning requires an ordinary-user explicit decision.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseArchivePath,
    [Parameter(Mandatory)][string]$BaseSignaturePath,
    [Parameter(Mandatory)][string]$InstallerKeyPath,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ManifestSha256,
    [Parameter(Mandatory)][string]$PythonPath,
    [Parameter(Mandatory)][string]$ExtractionHelperPath,
    [Parameter(Mandatory)][string]$ExtractionHelperSha256,
    [Parameter(Mandatory)][string]$DestinationParent,
    [Parameter(Mandatory)][string]$LogDirectory,
    [string]$CancelPath,
    [switch]$InstallBase
)
$ErrorActionPreference = 'Stop'
$archiveName = 'msys2-base-x86_64-20260611.tar.xz'
$fingerprint = '0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC'
$extractorHash = '23307cdbcafd03fb0d03b209cb2dceb35a4e2eed99c2ecfccda9571374fc1596'
$pythonHelperHash = '081b312795cc8b038de2ce511d2a8baabd23ffec55f7ef2f7269dbbb105f02e3'

function Assert-BasePath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(3).Split('\') -contains '..') { throw 'Absolute local base path required.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $cursor = $full
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse base path prohibited.' }
        $next = Split-Path -Parent $cursor; if ($next -eq $cursor) { break }; $cursor = $next
    }
    $full
}

function Assert-BasePin([string]$Path, $Pin, [switch]$AllowEmpty) {
    $null = Assert-BasePath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or $Pin.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [long]$Pin.bytes -lt 0 -or (-not $AllowEmpty -and [long]$Pin.bytes -eq 0) -or
        (Get-Item -LiteralPath $Path -Force).Length -ne [long]$Pin.bytes -or
        (Get-FileHash -LiteralPath $Path).Hash -ne $Pin.sha256) { throw "Base file pin differs: $Path" }
}

function ConvertToMsysPath([string]$Path) {
    $full = Assert-BasePath $Path
    '/' + $full.Substring(0,1).ToLowerInvariant() + $full.Substring(2).Replace('\','/')
}

function Get-BaseElevation {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BasePlatform {
    if (-not [Environment]::Is64BitProcess -or -not [Environment]::Is64BitOperatingSystem) { throw 'Native Windows x64 PowerShell required.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (Get-BaseElevation) { throw 'Elevated base provisioning is prohibited.' }
    [pscustomobject]@{ sid = $identity.User.Value; allowed_sids = @($identity.User.Value,'S-1-5-18','S-1-5-32-544') }
}

function Assert-BaseVolume([string]$Path) {
    $drive = [IO.Path]::GetPathRoot($Path).TrimEnd('\')
    $volumes = @(Get-CimInstance Win32_Volume -Filter ("DriveLetter='" + $drive + "'"))
    # A substituted drive has no independently mounted volume with that drive letter.
    if ($volumes.Count -ne 1 -or $volumes[0].DriveType -ne 3 -or $volumes[0].FileSystem -cne 'NTFS') { throw 'Fixed local NTFS nonsubstituted volume required.' }
}

function New-ProtectedBaseDirectory([string]$Path) {
    $null = Assert-BasePath $Path
    if (Test-Path -LiteralPath $Path) { throw 'Fresh owned base directory already exists; preserve it for manual review.' }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $Path) -PathType Container)) { throw 'Existing destination ancestor required.' }
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true,$false)
    $security.SetOwner([Security.Principal.SecurityIdentifier]::new($platform.sid))
    foreach ($sid in $platform.allowed_sids) {
        $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    [IO.Directory]::CreateDirectory($Path,$security) | Out-Null
    Assert-BaseAcl $Path -RequireProtected
}

function Assert-BaseAcl([string]$Path, [switch]$RequireProtected) {
    $null = Assert-BasePath $Path
    $item = Get-Item -LiteralPath $Path -Force
    $acl = $item.GetAccessControl([Security.AccessControl.AccessControlSections]'Access,Owner')
    if (($RequireProtected -and -not $acl.AreAccessRulesProtected) -or
        $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $platform.allowed_sids) { throw 'Owned base ACL/owner differs.' }
    $writers = 278 -bor 64 -bor 65536 -bor 262144 -bor 524288 -bor 268435456 -bor 1073741824
    $rules = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if (-not $rules.Count) { throw 'Owned base has no qualifying DACL rules.' }
    foreach ($rule in $rules) {
        if ($rule.AccessControlType -eq 'Allow' -and ([long]$rule.FileSystemRights -band $writers) -and $rule.IdentityReference.Value -notin $platform.allowed_sids) { throw 'Foreign base writer prohibited.' }
    }
}

function Write-BaseJson([string]$Path, $Value) {
    if ($Value.status -ceq 'VERIFIED_PINNED_BASE') { Assert-BaseCancellation }
    $null = Assert-BasePath $Path
    Assert-BaseAcl (Split-Path -Parent $Path) -RequireProtected
    if (Test-Path -LiteralPath $Path) { throw 'Existing receipt/state must be preserved.' }
    $temp = Join-Path (Split-Path -Parent $Path) ('.base-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 30))
    $stream = [IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    try { if ($Value.status -ceq 'VERIFIED_PINNED_BASE') { Assert-BaseCancellation }; [IO.File]::Move($temp,$Path) } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Assert-BaseCancellation {
    if ($CancelPath -and (Test-Path -LiteralPath $CancelPath)) { throw 'Base provisioning cancelled; owned partial state preserved.' }
}

function ConvertTo-BaseArgument([string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}

function Invoke-BaseNative([string]$Executable, [string[]]$Arguments) {
    Assert-BaseCancellation
    $null = Assert-BasePath $Executable
    if ($initialCode -and $Executable.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { Assert-BaseCodeFiles $initialCode }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable; $start.Arguments = (@($Arguments | ForEach-Object { ConvertTo-BaseArgument $_ }) -join ' ')
    $start.WorkingDirectory = $nativeWorkingDirectory; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Native base launch failed.' }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(250)) {
            if (($CancelPath -and (Test-Path -LiteralPath $CancelPath)) -or $watch.Elapsed.TotalSeconds -gt 600) {
                # Stop only descendants of this exact launched process, never a shared MSYS/GPG process by name.
                $pending = @($process.Id); $children = @()
                while ($pending.Count) { $next = @(); foreach ($pidValue in $pending) { $next += @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $pidValue) | ForEach-Object ProcessId) }; $children += $next; $pending = $next }
                foreach ($pidValue in @($children | Sort-Object -Descending)) { Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue }
                $process.Kill(); $process.WaitForExit(); throw 'Native base provisioning cancelled or timed out; partial state preserved.'
            }
        }
        $out = $stdout.Result; $err = $stderr.Result
        if ($nativeLogDirectory) { Write-BaseJson (Join-Path $nativeLogDirectory ('native-' + [guid]::NewGuid().ToString('N') + '.json')) @{executable=$Executable;arguments=$Arguments;exit_code=$process.ExitCode;stdout=$out;stderr=$err} }
        if ($process.ExitCode -ne 0) { $failure = [Exception]::new('Native base exit ' + $process.ExitCode + ': ' + $err); $failure.Data['stdout']=$out; throw $failure }
        @(($out + "`n" + $err) -split '\r?\n' | Where-Object { $_ -ne '' })
    } finally { $process.Dispose() }
}

function Assert-BaseInventory($Receipt, [switch]$BeforeInitialization) {
    if ($Receipt.schema_version -ne 1 -or $Receipt.status -cne 'VERIFIED_ARCHIVE_EXTRACTION' -or $Receipt.extraction_state -cne 'COMPLETE' -or
        $Receipt.manifest_sha256 -cne $ManifestSha256 -or $Receipt.archive_sha256 -cne $base.sha256 -or $Receipt.archive_bytes -ne $base.bytes -or
        $Receipt.owned_root -cne $root -or $Receipt.file_count -ne 15529 -or $Receipt.directory_count -ne 1052 -or @($Receipt.inventory).Count -ne 16581) { throw 'Full pinned extraction receipt differs.' }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Receipt.inventory) {
        if ($row.path -cnotmatch '^msys64(?:/[^<>:"\\|?*\x00-\x1f]+)*$' -or
            @($row.path -split '/' | Where-Object { $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ') }).Count -or -not $seen.Add($row.path)) { throw 'Invalid or duplicate extraction receipt path.' }
        $path = Join-Path $parent $row.path
        Assert-BaseAcl $path
        if ($row.type -ceq 'file') { Assert-BasePin $path $row -AllowEmpty }
        elseif ($row.type -cne 'directory' -or -not (Test-Path -LiteralPath $path -PathType Container)) { throw 'Extraction inventory kind differs.' }
    }
    if (@($Receipt.inventory | Where-Object type -CEQ file).Count -ne 15529 -or @($Receipt.inventory | Where-Object type -CEQ directory).Count -ne 1052) { throw 'Extraction inventory counts differ.' }
    if ($BeforeInitialization -and @(Get-ChildItem -LiteralPath $parent -Recurse -Force).Count -ne 16581) { throw 'Extraction contains unexpected files.' }
}

function Get-BaseTreeItems([string]$Path, [switch]$AllowMtab) {
    $pending = @($Path)
    while ($pending.Count) {
        $directory = $pending[0]; $pending = @($pending | Select-Object -Skip 1)
        Assert-BaseAcl $directory
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            if ($AllowMtab -and $item.FullName -ceq (Join-Path $root 'etc/mtab')) { continue }
            Assert-BaseAcl $item.FullName
            $item
            if ($item.PSIsContainer) { $pending += $item.FullName }
        }
    }
}

function Get-BaseCodeFiles {
    $records = @()
    foreach ($relative in @('usr/bin','etc/profile.d','etc/post-install','etc/msystem.d')) {
        $directory = Join-Path $root $relative; $null = Assert-BasePath $directory
        foreach ($file in Get-BaseTreeItems $directory) {
            Assert-BaseAcl $file.FullName
            if (-not $file.PSIsContainer) { $records += [pscustomobject]@{path=$file.FullName.Substring($root.Length+1).Replace('\','/');bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()} }
        }
    }
    foreach ($relative in @('etc/profile','etc/msystem','etc/bash.bashrc','msys2_shell.cmd')) {
        $file = Get-Item -LiteralPath (Join-Path $root $relative) -Force; Assert-BaseAcl $file.FullName
        $records += [pscustomobject]@{path=$relative;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()}
    }
    @($records | Sort-Object path)
}

function Assert-BaseCodeFiles($Records) {
    $actual = @(Get-BaseCodeFiles)
    if ($actual.Count -ne @($Records).Count -or (($actual | ConvertTo-Json -Depth 5 -Compress) -cne ($Records | ConvertTo-Json -Depth 5 -Compress))) { throw 'Pinned base code/DLL closure changed.' }
}

function Save-BaseEnvironment {
    $saved = @{}
    $names = @('PATH','BASH_ENV','ENV','GNUPGHOME','HOME','MSYSTEM','MSYS2_PATH_TYPE','SYSCONFDIR','CHERE_INVOKING','SHELLOPTS','BASHOPTS','CDPATH','GLOBIGNORE','PS1','XDG_CONFIG_HOME','ORIGINAL_PATH','CYG_SYS_BASHRC','MSYS2_PS1','MSYS2_ARG_CONV_EXCL','MSYS2_ENV_CONV_EXCL','MSYS_NO_PATHCONV')
    $names += @([Environment]::GetEnvironmentVariables('Process').Keys | Where-Object { $_ -like 'BASH_FUNC_*' })
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
    $saved
}

function Set-BaseEnvironment {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $env:PATH = "$root\usr\bin;$env:SystemRoot\System32"; $env:HOME='/home/autoclip-base'; $env:MSYSTEM='MSYS'; $env:MSYS2_PATH_TYPE='strict'; $env:CHERE_INVOKING='1'
}

function Restore-BaseEnvironment {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
}

function Assert-BaseKeyringTrust([string[]]$Output) {
    $keys = @{}; $primary = $false; $validity = ''; $capabilities = ''; $keyId = ''
    foreach ($line in $Output) {
        $fields = $line.Split(':')
        if ($fields[0] -ceq 'pub') {
            if ($primary -or $fields.Length -lt 12 -or $fields[4] -cnotmatch '^[A-F0-9]{16}$') { throw 'Default primary key identity malformed.' }
            $primary=$true; $validity=$fields[1]; $capabilities=$fields[11]; $keyId=$fields[4]
        }
        elseif ($fields[0] -ceq 'sub') { $primary=$false }
        elseif ($fields[0] -ceq 'fpr' -and $primary) {
            if ($fields.Length -lt 10 -or $fields[9] -cnotmatch '^[A-F0-9]{40}$' -or -not $fields[9].EndsWith($keyId,[StringComparison]::Ordinal) -or $keys.ContainsKey($fields[9])) { throw 'Default primary fingerprint/identity differs.' }
            $keys[$fields[9]]=@{validity=$validity;capabilities=$capabilities}; $primary=$false
        }
    }
    $trusted = @(Get-Content -LiteralPath (Join-Path $root 'usr/share/pacman/keyrings/msys2-trusted') | Where-Object { $_.Trim() } | ForEach-Object { $_.Split(':')[0] })
    if (-not $trusted.Count) { throw 'Default trusted master inventory absent.' }
    foreach ($id in $trusted) { if (-not $keys.ContainsKey($id) -or $keys[$id].validity -cnotin @('f','u') -or $keys[$id].capabilities.Contains('D')) { throw 'Default trusted master key missing or not fully valid.' } }
    foreach ($id in @(Get-Content -LiteralPath (Join-Path $root 'usr/share/pacman/keyrings/msys2-revoked') | Where-Object { $_.Trim() })) {
        if (-not $keys.ContainsKey($id) -or ($keys[$id].validity -cne 'r' -and -not $keys[$id].capabilities.Contains('D'))) { throw 'Default revoked key is not revoked or disabled.' }
    }
}

# Authentication and read-only platform checks precede every owned mutation/native child.
$platform = Get-BasePlatform
$parent = Assert-BasePath $DestinationParent; $logs = Assert-BasePath $LogDirectory
if ($DestinationParent -cnotmatch '^[A-Za-z]:\\[A-Za-z0-9_\\-]+$' -or
    $parent.Substring(3).Split('\') -contains '' -or
    [Text.Encoding]::UTF8.GetByteCount((ConvertToMsysPath $parent) + '/msys64/etc/pacman.d/ac-' + ('0'*32) + '/S.gpg-agent.browser') + 1 -gt 108) { throw 'Short ASCII base parent required.' }
if ($logs.Equals($parent,[StringComparison]::OrdinalIgnoreCase) -or $logs.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -or $parent.StartsWith($logs+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Receipt directory must be separate from extraction parent.' }
foreach ($path in @($parent,$logs)) { Assert-BaseVolume $path; if (Test-Path -LiteralPath $path) { throw 'Fresh base/receipt directory already exists; never overwrite or delete.' } }
$root = Join-Path $parent 'msys64'
$null = Assert-BasePath $ManifestPath
if ($ManifestSha256 -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $ManifestPath).Hash -ne $ManifestSha256) { throw 'Setup-bound base manifest hash differs.' }
$raw = [IO.File]::ReadAllText($ManifestPath)
$manifest = $raw | ConvertFrom-Json
# ConvertFrom-Json accepts repeated exact keys; reject them before any provisioning mutation.
$tokens = [regex]::Matches($raw,'"(?:\\.|[^"\\])*"|[{}\[\]:]')
$objects = New-Object Collections.Stack
for ($index=0; $index -lt $tokens.Count; $index++) {
    $token = $tokens[$index].Value
    if ($token -eq '{') { $objects.Push((New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase))) }
    elseif ($token -eq '[') { $objects.Push($null) }
    elseif ($token -in @('}',']')) { $null = $objects.Pop() }
    elseif ($token.StartsWith('"') -and $index+1 -lt $tokens.Count -and $tokens[$index+1].Value -eq ':') {
        $key = $token | ConvertFrom-Json
        if (-not $objects.Peek().Add($key)) { throw 'Duplicate dependency manifest field.' }
    }
}
if ($manifest.schema_version -isnot [int] -or $manifest.schema_version -ne 1 -or $manifest.build_prerequisites -isnot [array] -or
    @($manifest.build_prerequisites | Where-Object { $_ -isnot [pscustomobject] }).Count) { throw 'Unsupported base manifest schema.' }
$rows = @($manifest.build_prerequisites | Where-Object identity -IEQ MSYS2)
if ($rows.Count -ne 1) { throw 'Exactly one base identity required.' }
$base = $rows[0]
if ($base.identity -cne 'MSYS2' -or $base.version -cne '20260611' -or $base.architecture -cne 'x64' -or
    $base.artifact_kind -cne 'archive' -or $base.archive_format -cne 'tar.xz' -or $base.filename -cne $archiveName -or
    $base.url -cne ('https://github.com/msys2/msys2-installer/releases/download/2026-06-11/'+$archiveName) -or
    $base.bytes -ne 53555380 -or $base.sha256 -cne 'a2d047e8ee213c3c6a49a8de427eb1069df12207c0422ff1b3cbb5c905c34221') { throw 'Exact official base archive required.' }
if ($base.signature.filename -cne ($archiveName+'.sig') -or $base.signature.bytes -ne 566 -or $base.signature.sha256 -cne '076f5623b702d5016cf0253e1d14a6bd4870a90243243e96409b227f0d5bf70f' -or
    $base.installer_key.filename -cne 'installer-signer.asc' -or $base.installer_key.bytes -ne 52107 -or $base.installer_key.sha256 -cne 'a247a92716ab322770e800793c10136dd22a6ea4691fdd2b9c72d4cfc5221082' -or $base.installer_key.fingerprint -cne $fingerprint) { throw 'Exact detached signature/installer key pins required.' }
foreach ($pair in @(@($BaseArchivePath,$base),@($BaseSignaturePath,$base.signature),@($InstallerKeyPath,$base.installer_key))) {
    if ($pair[1].delivery_classification -cne 'DIRECT_RECIPIENT_DOWNLOAD' -or [IO.Path]::GetFileName($pair[0]) -cne $pair[1].filename) { throw 'Exact DIRECT base input required.' }
    Assert-BasePin $pair[0] $pair[1]
}
if ($ExtractionHelperSha256 -cne $extractorHash -or [IO.Path]::GetFileName($ExtractionHelperPath) -cne 'extract-msys2-base.py') { throw 'Frozen extractor identity required.' }
Assert-BasePin $ExtractionHelperPath @{bytes=(Get-Item -LiteralPath $ExtractionHelperPath).Length;sha256=$extractorHash}
$pythonHelper = Join-Path $PSScriptRoot 'install-python.ps1'
Assert-BasePin $pythonHelper @{bytes=(Get-Item -LiteralPath $pythonHelper).Length;sha256=$pythonHelperHash}
$null = Assert-BasePath $PythonPath
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'Verified full Python input is missing.' }
if ($CancelPath) { $CancelPath = Assert-BasePath $CancelPath }; Assert-BaseCancellation
if (-not $InstallBase) { [pscustomobject]@{schema_version=1;status='PLANNED_PINNED_BASE';execution_performed=$false;root=$root;manifest_sha256=$ManifestSha256;archive_sha256=$base.sha256;archive_bytes=$base.bytes;private_home=Join-Path $root 'home/autoclip-base'}; return }

$locked = @(); $savedEnvironment = @{}; $savedLocation = Get-Location
$nativeLogDirectory = $null; $nativeWorkingDirectory = Split-Path -Parent $PythonPath
$phase = 'input locks'; $ownsLogs = $false; $initialCode = $null
try {
    foreach ($path in @($ManifestPath,$BaseArchivePath,$BaseSignaturePath,$InstallerKeyPath,$ExtractionHelperPath,$pythonHelper,$PythonPath)) { $locked += [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read) }
    Assert-BasePin $ManifestPath @{bytes=(Get-Item -LiteralPath $ManifestPath).Length;sha256=$ManifestSha256}
    foreach ($pair in @(@($BaseArchivePath,$base),@($BaseSignaturePath,$base.signature),@($InstallerKeyPath,$base.installer_key))) { Assert-BasePin $pair[0] $pair[1] }
    Assert-BasePin $ExtractionHelperPath @{bytes=(Get-Item -LiteralPath $ExtractionHelperPath).Length;sha256=$extractorHash}
    Assert-BasePin $pythonHelper @{bytes=(Get-Item -LiteralPath $pythonHelper).Length;sha256=$pythonHelperHash}
    $savedEnvironment = Save-BaseEnvironment
    $phase = 'Python capability'
    $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $selected = @(Invoke-BaseNative $powershell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$pythonHelper,'-CheckOnly'))
    if ($selected.Count -ne 1 -or -not $selected[0].Equals([IO.Path]::GetFullPath($PythonPath),[StringComparison]::OrdinalIgnoreCase)) { throw 'Selected Python does not match existing exact full capability.' }
    Assert-BaseCancellation
    $phase = 'own protected directories'
    New-ProtectedBaseDirectory $logs; $ownsLogs = $true; $nativeLogDirectory = $logs
    Write-BaseJson (Join-Path $logs 'ownership.json') @{schema_version=1;status='OWNED_BASE_PENDING';manifest_sha256=$ManifestSha256;archive_sha256=$base.sha256;root=$root;owner_sid=$platform.sid}
    New-ProtectedBaseDirectory $parent
    $phase = 'full Python extraction'
    $extraction = @(Invoke-BaseNative $PythonPath @('-I','-B',$ExtractionHelperPath,'--manifest',$ManifestPath,'--manifest-sha256',$ManifestSha256,'--archive',$BaseArchivePath,'--parent',$parent)) -join "`n"
    $extractionReceipt = $extraction | ConvertFrom-Json
    $extractionPath = Join-Path $logs 'extraction-receipt.json'; Write-BaseJson $extractionPath $extractionReceipt
    Assert-BaseInventory $extractionReceipt -BeforeInitialization
    $initialCode = @(Get-BaseCodeFiles)
    # The entire verified usr/bin closure includes both OpenPGP executables and all archive DLLs.
    Assert-BaseCodeFiles $initialCode
    Set-BaseEnvironment
    $nativeWorkingDirectory = Join-Path $root 'usr/bin'; Set-Location -LiteralPath $nativeWorkingDirectory
    $keyHome = Join-Path $logs 'signature-home'; New-ProtectedBaseDirectory $keyHome
    $binaryKey = Join-Path $keyHome 'installer-signer.gpg'
    $gpg = Join-Path $root 'usr/bin/gpg.exe'; $gpgv = Join-Path $root 'usr/bin/gpgv.exe'; $bash = Join-Path $root 'usr/bin/bash.exe'
    $phase = 'detached signature before bash'
    Assert-BaseCodeFiles $initialCode
    $keyOutput = @(Invoke-BaseNative $gpg @('--no-options','--batch','--homedir',(ConvertToMsysPath $keyHome),'--with-colons','--show-keys',(ConvertToMsysPath $InstallerKeyPath)))
    $primary = @($keyOutput | Where-Object { $_ -match '^fpr:' } | ForEach-Object { $_.Split(':')[9] })
    if (-not $primary.Count -or $primary[0] -cne $fingerprint -or @($keyOutput | Where-Object { $_ -match '^pub:' }).Count -ne 1) { throw 'Installer primary fingerprint differs.' }
    Invoke-BaseNative $gpg @('--no-options','--batch','--yes','--homedir',(ConvertToMsysPath $keyHome),'--output',(ConvertToMsysPath $binaryKey),'--dearmor',(ConvertToMsysPath $InstallerKeyPath)) | Out-Null
    $signature = @(Invoke-BaseNative $gpgv @('--homedir',(ConvertToMsysPath $keyHome),'--keyring',(ConvertToMsysPath $binaryKey),'--status-fd','1',(ConvertToMsysPath $BaseSignaturePath),(ConvertToMsysPath $BaseArchivePath)))
    if (@($signature | Where-Object { $_ -match '^\[GNUPG:\] VALIDSIG E0AA0F031DBD80FFBA57B06D5A62D0CAB6264964 .* 0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC$' }).Count -ne 1 -or
        @($signature | Where-Object { $_ -match '^\[GNUPG:\] (BADSIG|ERRSIG|REVKEYSIG|EXPKEYSIG|EXPSIG)' }).Count) { throw 'Exact detached base signature rejected before bash.' }
    $phase = 'local default keyring'
    Assert-BaseCodeFiles $initialCode
    Invoke-BaseNative $bash @('--noprofile','--norc','-c','/usr/bin/pacman-key --gpgdir /etc/pacman.d/gnupg --init') | Out-Null
    Invoke-BaseNative $bash @('--noprofile','--norc','-c','/usr/bin/pacman-key --gpgdir /etc/pacman.d/gnupg --populate-from /usr/share/pacman/keyrings --populate msys2') | Out-Null
    foreach ($name in @('pubring.gpg','trustdb.gpg')) { $path=Join-Path $root ('etc/pacman.d/gnupg/'+$name); Assert-BaseAcl $path; if ((Get-Item $path).Length -eq 0) { throw 'Default local keyring incomplete.' } }
    $trust = @(Invoke-BaseNative $gpg @('--no-options','--batch','--homedir','/etc/pacman.d/gnupg','--with-colons','--list-keys'))
    Assert-BaseKeyringTrust $trust
    Invoke-BaseNative (Join-Path $root 'usr/bin/gpgconf.exe') @('--homedir','/etc/pacman.d/gnupg','--kill','all') | Out-Null
    $phase = 'one upstream login'
    $privateHome = Join-Path $root 'home/autoclip-base'
    if (Test-Path -LiteralPath $privateHome) { throw 'Private HOME must be created by the one first login.' }
    Assert-BaseCodeFiles $initialCode
    $login = @(Invoke-BaseNative $bash @('--login','-c','printf AUTOCLIP_FIRST_LOGIN_RETURNED'))
    if (($login -join "`n") -notmatch 'AUTOCLIP_FIRST_LOGIN_RETURNED' -or ($login -join "`n") -match 'keyserver|refreshing|hkps://') { throw 'First login failed or attempted key refresh.' }
    $phase = 'post-install effects and mode'
    $effects = @(Invoke-BaseNative $bash @('--noprofile','--norc','-c','test -d /dev/shm && test -d /dev/mqueue && test "$HOME" = /home/autoclip-base && test -d "$HOME" && test -L /etc/mtab && test "$(/usr/bin/readlink /etc/mtab)" = /proc/mounts && test -x /usr/bin/pacman-key && test -x /usr/bin/bash.exe && test -x /usr/bin/gpgv.exe && printf AUTOCLIP_BASE_EFFECTS_OK'))
    if (($effects -join "`n") -notmatch 'AUTOCLIP_BASE_EFFECTS_OK') { throw 'Post-install effects/modes missing.' }
    foreach ($name in @('hosts','protocols','services','networks')) {
        $source = Join-Path $env:SystemRoot ('System32/drivers/etc/'+$name.Substring(0,[Math]::Min(8,$name.Length)))
        if (Test-Path -LiteralPath $source) { $target=Join-Path $root ('etc/'+$name); Assert-BasePin $target @{bytes=(Get-Item $source).Length;sha256=(Get-FileHash $source).Hash.ToLowerInvariant()} }
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'etc/skel') -Recurse -File -Force) {
        $relative=$file.FullName.Substring((Join-Path $root 'etc/skel').Length+1); $target=Join-Path $privateHome $relative
        Assert-BasePin $target @{bytes=$file.Length;sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant()}
    }
    $skel = Join-Path $root 'etc/skel'
    $expectedHome = @(Get-BaseTreeItems $skel | ForEach-Object { $_.FullName.Substring($skel.Length+1) })
    $actualHome = @(Get-BaseTreeItems $privateHome | ForEach-Object { $_.FullName.Substring($privateHome.Length+1) })
    if (@(Compare-Object $expectedHome $actualHome -CaseSensitive).Count) { throw 'Private HOME contains unexpected startup/output files.' }
    Assert-BaseInventory $extractionReceipt
    # The only documented post-extraction link is mtab; inspect it natively above, never follow it here.
    $archivePaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $extractionReceipt.inventory) { $null = $archivePaths.Add($row.path.Substring('msys64'.Length).TrimStart('/')) }
    foreach ($item in Get-BaseTreeItems $root -AllowMtab) {
        $relative = $item.FullName.Substring($root.Length+1).Replace('\','/')
        if (-not $archivePaths.Contains($relative) -and $relative -cnotmatch '^(?:dev/(?:shm|mqueue)|home/autoclip-base(?:/.*)?|etc/(?:hosts|protocols|services|networks)|etc/pacman.d/gnupg(?:/.*)?)$') { throw "Unexpected initialization output: $relative" }
    }
    Assert-BaseAcl $parent -RequireProtected; Assert-BaseAcl $logs -RequireProtected; Assert-BaseCodeFiles $initialCode; Assert-BaseCancellation
    $receiptPath = Join-Path $logs 'base-receipt.json'
    $receipt = [ordered]@{schema_version=1;status='VERIFIED_PINNED_BASE';manifest_sha256=$ManifestSha256;archive_sha256=$base.sha256;archive_bytes=$base.bytes;root=$root;signature_verified=$true;signer_fingerprint=$fingerprint;init_verified=$true;first_login_verified=$true;protected_root_verified=$true;extraction_inventory=@{receipt_sha256=(Get-FileHash $extractionPath).Hash.ToLowerInvariant();file_count=15529;directory_count=1052};code_files=@(Get-BaseCodeFiles);private_home=$privateHome;private_home_msys='/home/autoclip-base'}
    Write-BaseJson $receiptPath $receipt
    [pscustomobject]@{status=$receipt.status;root=$root;receipt_path=$receiptPath;receipt_sha256=(Get-FileHash $receiptPath).Hash.ToLowerInvariant();private_home=$privateHome}
} catch {
    if ($ownsLogs -and $phase -eq 'full Python extraction' -and $_.Exception.Data['stdout'] -and -not (Test-Path -LiteralPath (Join-Path $logs 'extraction-receipt.json'))) {
        $partial = $_.Exception.Data['stdout'] | ConvertFrom-Json
        Write-BaseJson (Join-Path $logs 'extraction-receipt.json') $partial
    }
    if ($ownsLogs) { Write-BaseJson (Join-Path $logs 'failure.json') @{schema_version=1;status='FAILED_BASE_PRESERVED';phase=$phase;root=$root;manifest_sha256=$ManifestSha256;error=$_.Exception.Message} }
    throw
} finally {
    if ($ownsLogs -and (Test-Path -LiteralPath $root)) {
        # Pacman-key may leave a detached agent. Stop only agents whose executable is in this fresh owned root.
        $agentPath = Join-Path $root 'usr/bin/gpg-agent.exe'
        foreach ($agent in @(Get-CimInstance Win32_Process -Filter "Name='gpg-agent.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.Equals($agentPath,[StringComparison]::OrdinalIgnoreCase) })) { Stop-Process -Id $agent.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Restore-BaseEnvironment
    Set-Location -LiteralPath $savedLocation.Path
    foreach ($stream in $locked) { $stream.Dispose() }
}
