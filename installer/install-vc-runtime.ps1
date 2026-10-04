[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ManifestSha256,
    [Parameter(Mandatory)][string]$StateDirectory,
    [Parameter(Mandatory, ParameterSetName = 'Check')][switch]$CheckOnly,
    [Parameter(Mandatory, ParameterSetName = 'Install')][string]$InstallerPath,
    [Parameter(ParameterSetName = 'Install')][switch]$AcceptMicrosoftTerms
)
$ErrorActionPreference = 'Stop'

function Get-AutoClipVcContext {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'VC helper must run with an ordinary recipient token.' }
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw 'VC preparation requires Windows x64 PowerShell.' }
    $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    if (-not $boot) { throw 'Verified boot identity unavailable.' }
    [pscustomobject]@{ Sid = $identity.User.Value; Boot = $boot.ToUniversalTime().ToString('o') }
}

function Assert-AutoClipVcPath {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path -match '["\x00-\x1f]' -or $Path.Substring(2).Contains(':')) { throw 'VC paths must be absolute local paths.' }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'VC path contains a reparse point.' }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
}

function Assert-AutoClipVcAuthority {
    param([string]$Path, [string]$Sid, [switch]$SystemFile)
    Assert-AutoClipVcPath $Path
    $acl = Get-Acl -LiteralPath $Path
    $allowed = @('S-1-5-18', 'S-1-5-32-544')
    if ($SystemFile) { $allowed += 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' } else { $allowed += $Sid }
    if ($allowed -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { throw 'VC path has foreign ownership.' }
    $write = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $write) -and $allowed -notcontains $rule.IdentityReference.Value) { throw 'VC path permits foreign modification.' }
    }
}

function Open-AutoClipVcInput {
    param([string]$Path, [string]$Sid)
    Assert-AutoClipVcAuthority $Path $Sid
    Assert-AutoClipVcAuthority (Split-Path -Parent $Path) $Sid
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'VC input must be a regular file.' }
    [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
}

function Get-AutoClipVcHash {
    param([IO.Stream]$Stream)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $Stream.Position = 0; ([BitConverter]::ToString($hash.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $Stream.Position = 0; $hash.Dispose() }
}

function Assert-AutoClipVcSignature {
    param([string]$Path, [string]$Publisher, [switch]$SystemFile)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($SystemFile) {
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft (Corporation|Windows Software Compatibility Publisher)(,|$)' -or
            $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'VC system DLL signature or publisher differs.' }
        return
    }
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch ('(^|,\s*)CN=' + [regex]::Escape($Publisher) + '(,|$)')) { throw 'VC signature or publisher differs.' }
}

function Get-AutoClipVcVersion {
    param([string]$Path)
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    [version]::new($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
}

function Test-AutoClipVcCapability {
    param([version]$MinimumVersion)
    $script:AutoClipVcCapabilityFailure = $null
    try {
        if (-not ('AutoClipVcLoader' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AutoClipVcLoader {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
 [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr module);
}
'@
        }
        foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'vcomp140.dll')) {
            $path = Join-Path ([Environment]::SystemDirectory) $name
            Assert-AutoClipVcAuthority $path '' -SystemFile
            $stream = [IO.File]::Open($path, 'Open', 'Read', 'Read')
            try {
                $reader = New-Object IO.BinaryReader $stream
                if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'VC DLL DOS header differs.' }
                $stream.Position = 0x3c; $pe = $reader.ReadInt32()
                if ($pe -lt 64 -or $pe -gt $stream.Length - 6) { throw 'VC DLL PE offset differs.' }
                $stream.Position = $pe
                if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'VC DLL PE architecture differs.' }
                Assert-AutoClipVcSignature $path 'Microsoft Corporation' -SystemFile
                if ((Get-AutoClipVcVersion $path) -lt $MinimumVersion) { throw 'VC DLL version is below minimum.' }
                $module = [AutoClipVcLoader]::LoadLibraryEx($path, [IntPtr]::Zero, 0x1100)
                if ($module -eq [IntPtr]::Zero) { throw 'VC DLL native load failed.' }
                if (-not [AutoClipVcLoader]::FreeLibrary($module)) { throw 'VC loader cleanup failed.' }
            } finally { $stream.Dispose() }
        }
        return $true
    } catch { $script:AutoClipVcCapabilityFailure = "$path`: $($_.Exception.Message)"; return $false }
}

function Initialize-AutoClipVcStateDirectory {
    param([string]$Path, [string]$Sid)
    Assert-AutoClipVcPath $Path
    Assert-AutoClipVcAuthority (Split-Path -Parent $Path) $Sid
    if (-not (Test-Path -LiteralPath $Path)) {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($Sid))
        foreach ($id in @($Sid, 'S-1-5-18', 'S-1-5-32-544')) {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        [IO.Directory]::CreateDirectory($Path, $acl) | Out-Null
    }
    Assert-AutoClipVcAuthority $Path $Sid
}

function Write-AutoClipVcRecord {
    param([string]$Path, $Record)
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Record | ConvertTo-Json -Depth 8))
    $stream = [IO.File]::Open($temp, 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($temp, $Path) }
}

function Start-AutoClipVcVendor {
    param([string]$Path, [string[]]$Arguments)
    # Start-Process discards the native error code, including UAC cancellation.
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Path
    $startInfo.Arguments = $Arguments -join ' '
    $startInfo.UseShellExecute = $true
    $startInfo.Verb = 'runas'
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
    [Diagnostics.Process]::Start($startInfo)
}

function Invoke-AutoClipVcRuntime {
    param([string]$ManifestPath, [string]$ManifestSha256, [string]$StateDirectory, [switch]$CheckOnly, [string]$InstallerPath, [switch]$AcceptMicrosoftTerms)
    $result = [ordered]@{ schema_version = 1; status = 'failed'; exit_code = 21; vendor_exit_code = $null; receipt_path = $null; message = $null }
    $manifestStream = $null; $vendorStream = $null; $lock = $null; $process = $null; $handle = [IntPtr]::Zero
    $record = $null; $ownedAttempt = $false; $terminal = $false
    try {
        $context = Get-AutoClipVcContext
        $manifestStream = Open-AutoClipVcInput $ManifestPath $context.Sid
        if ((Get-AutoClipVcHash $manifestStream) -ne $ManifestSha256 -or $ManifestSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Setup-bound manifest SHA-256 differs.' }
        $reader = New-Object IO.StreamReader $manifestStream
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
        $pins = @($manifest.external_assets | Where-Object kind -eq 'microsoft_vc_redist_x64')
        if ($manifest.schema_version -ne 1 -or $pins.Count -ne 1) { throw 'Exact VC manifest row required.' }
        $pin = $pins[0]
        if ($pin.delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD' -or $pin.architecture -ne 'x64' -or
            $pin.signature_publisher -ne 'Microsoft Corporation' -or $pin.bytes -le 0 -or $pin.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            ($pin.installer_arguments -join '|') -cne '/install|/norestart' -or ($pin.success_exit_codes -join '|') -ne '0|3010') { throw 'Reviewed VC route unavailable.' }
        $minimum = [version]$pin.version
        Assert-AutoClipVcPath $StateDirectory
        $statePath = Join-Path $StateDirectory 'vc-state.json'
        if (Test-Path -LiteralPath $StateDirectory) {
            Assert-AutoClipVcAuthority $StateDirectory $context.Sid
            Assert-AutoClipVcAuthority (Split-Path -Parent $StateDirectory) $context.Sid
            $lockPath = Join-Path $StateDirectory 'vc.lock'
            if (-not (Test-Path -LiteralPath $lockPath)) { throw 'Existing VC state directory has no owned lock.' }
            Assert-AutoClipVcAuthority $lockPath $context.Sid
            try { $lock = [IO.File]::Open($lockPath, 'Open', 'ReadWrite', 'None') } catch { $result.status = 'busy'; $result.exit_code = 1618; throw 'VC preparation already active or lock unavailable.' }
        } elseif (-not $CheckOnly) {
            Initialize-AutoClipVcStateDirectory $StateDirectory $context.Sid
            $lock = [IO.File]::Open((Join-Path $StateDirectory 'vc.lock'), 'CreateNew', 'ReadWrite', 'None')
        }
        if (Test-Path -LiteralPath $statePath) {
            Assert-AutoClipVcAuthority $statePath $context.Sid
            $record = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($record.schema_version -ne 1 -or $record.recipient_sid -ne $context.Sid -or
                $record.manifest_sha256 -ne $ManifestSha256 -or $record.installer_sha256 -ne $pin.sha256 -or
                $record.version -ne $pin.version -or -not $record.boot_identity -or
                $record.attempt_id -notmatch '^[a-f0-9]{32}$' -or $record.status -notin @('in_progress', 'pending_reboot', 'ready', 'failed', 'cancelled') -or
                ($record.status -eq 'pending_reboot' -and $record.vendor_exit_code -ne 3010) -or
                ($record.status -eq 'in_progress' -and $null -ne $record.vendor_exit_code)) { throw 'Foreign or conflicting VC state preserved.' }
            if ($record.status -in @('in_progress', 'pending_reboot')) {
                if ($record.boot_identity -eq $context.Boot) {
                    if ($record.status -eq 'pending_reboot') { $result.status = 'pending_reboot'; $result.exit_code = 3010; $result.vendor_exit_code = $record.vendor_exit_code }
                    else { $result.status = 'unresolved'; $result.exit_code = 23 }
                    throw 'VC attempt requires reboot before fresh capability verification.'
                }
                if (-not (Test-AutoClipVcCapability $minimum)) { $result.status = 'unresolved'; $result.exit_code = 23; throw 'Post-reboot VC capability remains unresolved.' }
                # CheckOnly never retires state; install mode retires only after fresh capability succeeds.
                if (-not $CheckOnly) { Remove-Item -LiteralPath $statePath }
            }
        }
        if (Test-AutoClipVcCapability $minimum) { $result.status = 'ready'; $result.exit_code = 0; $result.message = 'System VC DLL capability verified.'; return [pscustomobject]$result }
        if ($CheckOnly) { $result.status = 'missing'; $result.exit_code = 2; $result.message = 'System VC DLL capability missing.'; return [pscustomobject]$result }
        if (-not $AcceptMicrosoftTerms) { $result.status = 'declined'; $result.exit_code = 20; throw 'Explicit recipient Microsoft terms declaration required; vendor agreement remains interactive.' }
        $vendorStream = Open-AutoClipVcInput $InstallerPath $context.Sid
        if ($vendorStream.Length -ne [long]$pin.bytes -or (Get-AutoClipVcHash $vendorStream) -ne $pin.sha256) { throw 'VC installer size or SHA-256 differs.' }
        Assert-AutoClipVcSignature $InstallerPath $pin.signature_publisher
        if ((Get-AutoClipVcVersion $InstallerPath) -ne $minimum) { throw 'VC installer exact file version differs.' }
        $record = [ordered]@{ schema_version = 1; recipient_sid = $context.Sid; manifest_sha256 = $ManifestSha256.ToLowerInvariant(); installer_sha256 = $pin.sha256; version = $pin.version; boot_identity = $context.Boot; attempt_id = [guid]::NewGuid().ToString('N'); status = 'in_progress'; vendor_exit_code = $null; timestamp_utc = [DateTime]::UtcNow.ToString('o') }
        $result.receipt_path = Join-Path $StateDirectory ($record.attempt_id + '.json')
        Write-AutoClipVcRecord $statePath $record
        $ownedAttempt = $true
        try { $process = Start-AutoClipVcVendor ([IO.Path]::GetFullPath($InstallerPath)) $pin.installer_arguments }
        catch [ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -eq 1223) { $result.status = 'cancelled'; $result.exit_code = 1223; $record.status = 'cancelled'; $terminal = $true }
            throw
        }
        if (-not $process) { $result.status = 'unresolved'; $result.exit_code = 23; throw 'Vendor launch returned no owned process handle.' }
        # Hold the native process handle, artifact and transaction lock through terminal observation.
        $handle = $process.Handle
        if (-not $handle -or $handle -eq [IntPtr]::Zero) { throw 'Vendor native process handle unavailable.' }
        $process.WaitForExit()
        $result.vendor_exit_code = $process.ExitCode
        $record.vendor_exit_code = $process.ExitCode
        $terminal = $true
        if ($process.ExitCode -eq 3010) { $result.status = 'pending_reboot'; $result.exit_code = 3010; $record.status = 'pending_reboot' }
        elseif ($process.ExitCode -in @(1602, -2147023294, 1223, -2147023673)) { $result.status = 'cancelled'; $result.exit_code = 1602; $record.status = 'cancelled' }
        elseif ($process.ExitCode -ne 0) { $record.status = 'failed'; throw "VC vendor failed: $($process.ExitCode)." }
        elseif (-not (Test-AutoClipVcCapability $minimum)) { $record.status = 'failed'; throw ('VC vendor returned zero but DLL capability failed: ' + $script:AutoClipVcCapabilityFailure) }
        else { $result.status = 'ready'; $result.exit_code = 0; $record.status = 'ready' }
        $result.message = 'VC vendor terminal result observed.'
    } catch { $result.message = $_.Exception.Message }
    finally {
        # Observation/receipt failures must never release serialization over a live owned vendor child.
        if ($process) {
            try { $process.WaitForExit() } catch {
                $terminal = $false
                $result.status = 'unresolved'; $result.exit_code = 23; $result.message = 'Vendor observation failed; durable in-progress state preserved.'
                if ($handle -ne [IntPtr]::Zero) {
                    # Wait on the already-owned native handle when Process observation fails.
                    # No PID lookup, timeout, termination or restart grants replacement authority.
                    $wait = New-Object Threading.ManualResetEvent $false
                    $original = $wait.SafeWaitHandle
                    try {
                        $wait.SafeWaitHandle = [Microsoft.Win32.SafeHandles.SafeWaitHandle]::new($handle, $false)
                        $wait.WaitOne() | Out-Null
                    } catch { $result.message = 'Owned native handle wait failed; unresolved state requires manual resolution.' }
                    finally { $wait.Dispose(); $original.Dispose() }
                }
            }
            try { $process.Dispose() } catch { $result.status = 'unresolved'; $result.exit_code = 23; $terminal = $false }
        }
        if ($ownedAttempt) {
            try {
                if (-not $terminal) { $record.status = 'in_progress'; $record.vendor_exit_code = $null; $result.status = 'unresolved'; $result.exit_code = 23 }
                Write-AutoClipVcRecord $result.receipt_path $record
                Write-AutoClipVcRecord $statePath $record
            } catch { $result.status = 'unresolved'; $result.exit_code = 23; $result.message = 'VC outcome publication failed; preserve state and require resolution: ' + $_.Exception.Message }
        }
        if ($vendorStream) { $vendorStream.Dispose() }
        if ($manifestStream) { $manifestStream.Dispose() }
        if ($lock) { $lock.Dispose() }
    }
    [pscustomobject]$result
}

$result = Invoke-AutoClipVcRuntime -ManifestPath $ManifestPath -ManifestSha256 $ManifestSha256 -StateDirectory $StateDirectory -CheckOnly:$CheckOnly -InstallerPath $InstallerPath -AcceptMicrosoftTerms:$AcceptMicrosoftTerms
$result | ConvertTo-Json -Compress
exit $result.exit_code
