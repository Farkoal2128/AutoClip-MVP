param(
    [string]$BaseRoot,
    [string]$InstallerPath,
    [string]$InstallerSha256,
    [string]$ArchivePath,
    [string]$ExternalCache,
    [string]$NativeBuildRoot,
    [string]$MsysBash,
    [string]$CudaRoot,
    [switch]$InstallNvidiaGpu,
    [switch]$AcceptNvidiaTerms,
    [switch]$AcceptMicrosoftTerms,
    [switch]$NonInteractive,
    [switch]$CpuOnly,
    [string]$ShortcutPath,
    [string]$PreviousReleaseId,
    [switch]$Rollback,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
if ($InstallNvidiaGpu -and $CpuOnly) {
    throw 'Choose either -InstallNvidiaGpu or -CpuOnly.'
}
if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    throw 'This updater supports Windows x64 only.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This updater requires 64-bit Windows.'
}
if (-not $BaseRoot) {
    $BaseRoot = Join-Path $env:LOCALAPPDATA 'AutoClip'
}
$baseFull = [IO.Path]::GetFullPath($BaseRoot).TrimEnd('\')
$statePath = Join-Path $baseFull 'active.json'
$launcherPath = Join-Path $baseFull 'Start-AutoClip.ps1'

function Open-AuthenticatedInstaller([string]$Path, [string]$Pin) {
    if (-not $Path -or -not $Pin) { throw 'Full update requires an explicit trusted local -InstallerPath and independently trusted -InstallerSha256. Native Maintenance supports routine app updates.' }
    if ($Pin -notmatch '^[a-fA-F0-9]{64}$') { throw 'InstallerSha256 must be an independently trusted SHA-256.' }
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(3) -match '[:*?"<>|\x00-\x1f]' -or
        @($Path.Substring(3).Split([char[]]'\/') | Where-Object { !$_ -or $_ -in @('.', '..') -or $_.EndsWith('.') -or $_.EndsWith(' ') }).Count -or
        [IO.Path]::GetExtension($Path) -ine '.ps1') { throw 'InstallerPath must be an absolute local regular .ps1 path without aliases or alternate streams.' }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not ('AutoClipInstallerPathV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class AutoClipInstallerPathV1 {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint length, uint flags);
    public static FileStream OpenFile(string path) {
        var handle = CreateFileW(path, 0x80000000, 1, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        if (handle.IsInvalid) { handle.Dispose(); throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
        try { return new FileStream(handle, FileAccess.Read); }
        catch { handle.Dispose(); throw; }
    }
    public static SafeFileHandle HoldDirectory(string path) {
        var handle = CreateFileW(path, 1, 1, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
        if (handle.IsInvalid) { handle.Dispose(); throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
        try {
            var buffer = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0 || length >= buffer.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if (!String.Equals(buffer.ToString(), @"\\?\" + path, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Installer directory is not its canonical local path.");
            return handle;
        } catch { handle.Dispose(); throw; }
    }
}
'@
    }
    $locks = [Collections.Generic.List[IDisposable]]::new()
    try {
        $parents = @(); $cursor = [IO.Path]::GetDirectoryName($full)
        while ($cursor) { $parents = @($cursor) + $parents; $cursor = [IO.Path]::GetDirectoryName($cursor) }
        # List-directory/Read-sharing handles allow child-file use but
        # deny ancestor write/reparse and deletion/rename handles. A file lock
        # alone does not protect its ancestor directory names.
        foreach ($parent in $parents) {
            $locks.Add([AutoClipInstallerPathV1]::HoldDirectory($parent))
            if ([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) { throw 'InstallerPath contains a reparse point.' }
        }
        $file = Get-Item -LiteralPath $full -Force
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'InstallerPath must be a regular file without reparse points.' }
        # Open the leaf itself without following a newly substituted reparse
        # point; validate its attributes again while its name is held.
        $stream = [AutoClipInstallerPathV1]::OpenFile($full); $locks.Add($stream)
        if ([IO.File]::GetAttributes($full) -band [IO.FileAttributes]::ReparsePoint) { throw 'InstallerPath contains a reparse point.' }
        $acl = Get-Acl -LiteralPath $full
        $trusted = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'InstallerPath owner is foreign.' }
        $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        $writes = 278 -bor 64 -bor 65536 -bor 262144 -bor 524288 -bor 268435456 -bor 1073741824
        if (-not $rules.Count -or @($rules | Where-Object { $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin $trusted -and ([long]$_.FileSystemRights -band $writes) }).Count) { throw 'InstallerPath permits foreign writes.' }
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-', '') } finally { $hash.Dispose() }
        if ($actual -ine $Pin) { throw 'InstallerSha256 differs from the held installer bytes.' }
        $stream.Position = 0
        return [pscustomobject]@{ Path = $full; Locks = $locks }
    } catch { foreach ($held in $locks) { $held.Dispose() }; throw }
}

function Acquire-SelectionMutex([string]$Base) {
    $full = [IO.Path]::GetFullPath($Base.Replace('/', '\')).TrimEnd('\')
    if ($full -notmatch '^[A-Za-z]:\\' -or $full -match '[*?]' -or
        @($full.Substring(3).Split('\') | Where-Object { $_ -match '[. ]$' }).Count) {
        throw 'Selection requires an unambiguous local directory path.'
    }
    $ancestor = $full
    $suffix = @()
    while (-not [IO.Directory]::Exists($ancestor)) {
        if ([IO.File]::Exists($ancestor)) { throw 'Selection base is not a directory.' }
        $suffix = @([IO.Path]::GetFileName($ancestor)) + $suffix
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
        if (-not $ancestor) { throw 'Selection base has no existing local ancestor.' }
    }
    $check = $ancestor
    while ($check) {
        if ([IO.File]::GetAttributes($check) -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Selection base contains a reparse alias.'
        }
        $check = [IO.Path]::GetDirectoryName($check.TrimEnd('\'))
    }
    if (-not ('AutoClipSelectionPathV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class AutoClipSelectionPathV1 {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint length, uint flags);
    public static string Resolve(string path) {
        using (var handle = CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            var buffer = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0 || length >= buffer.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            return buffer.ToString();
        }
    }
}
'@
    }
    $canonical = [AutoClipSelectionPathV1]::Resolve($ancestor)
    if ($canonical -notmatch '^\\\\\?\\[A-Za-z]:\\') { throw 'Selection base is not a canonical local path.' }
    $canonical = $canonical.Substring(4).TrimEnd('\')
    foreach ($part in $suffix) { $canonical = Join-Path $canonical $part }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $ids = @($sid.Value, 'S-1-5-18', 'S-1-5-32-544')
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $key = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($sid.Value + "`n" + $canonical.ToUpperInvariant()))).Replace('-', '').ToLowerInvariant()
    } finally { $hash.Dispose() }
    $name = 'Global\AutoClip.Selection.v1.' + $key
    $security = New-Object Security.AccessControl.MutexSecurity
    $security.SetOwner($sid)
    $security.SetAccessRuleProtection($true, $false)
    foreach ($id in $ids) {
        $security.AddAccessRule([Security.AccessControl.MutexAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id), 'FullControl', 'Allow'))
    }
    $created = $false
    $mutex = $null
    $held = $false
    try {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            Add-Type -AssemblyName System.Threading.AccessControl
            $mutex = [Threading.MutexAcl]::Create($false, $name, [ref]$created, $security)
            $actual = [Threading.ThreadingAclExtensions]::GetAccessControl($mutex)
        } else {
            $mutex = [Threading.Mutex]::new($false, $name, [ref]$created, $security)
            $actual = $mutex.GetAccessControl()
        }
        $rules = @($actual.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        if ($actual.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $ids -or
            -not $actual.AreAccessRulesProtected -or $rules.Count -ne 3 -or
            @($rules | Where-Object {
                $_.IdentityReference.Value -notin $ids -or $_.IsInherited -or
                $_.AccessControlType -ne 'Allow' -or $_.MutexRights -ne 'FullControl'
            }).Count -or @($rules.IdentityReference.Value | Select-Object -Unique).Count -ne 3) {
            throw 'Unsafe AutoClip selection mutex authority.'
        }
        try { $held = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw 'AutoClip selection is busy. Retry after the other updater or cleanup completes.' }
        return $mutex
    } catch {
        if ($held) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
        throw
    }
}

function Show-UpdateProgress {
    param([Parameter(Mandatory)][string]$Stage, [Parameter(Mandatory)][int]$Percent)
    Write-Progress -Id 0 -Activity 'Updating AutoClip' -Status $Stage -PercentComplete $Percent
}

function Complete-UpdateProgress {
    Write-Progress -Id 0 -Activity 'Updating AutoClip' -Completed
}

function Assert-AppStopped {
    $client = New-Object Net.Sockets.TcpClient
    $busy = $false
    try {
        $attempt = $client.BeginConnect('127.0.0.1', 8000, $null, $null)
        if ($attempt.AsyncWaitHandle.WaitOne(500)) {
            try {
                $client.EndConnect($attempt)
                $busy = $true
            } catch [Net.Sockets.SocketException] {
                # Connection refused: no app is listening on the default port.
            }
        }
    } finally {
        $client.Close()
    }
    if ($busy) {
        throw 'Local port 8000 is in use. Quit AutoClip (or the other service using that port), then rerun the updater.'
    }
}

Assert-AppStopped

function Assert-ReleaseId([string]$ReleaseId) {
    if ($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid release identifier: $ReleaseId"
    }
}

function Get-ReleaseRoot([string]$ReleaseId) {
    Assert-ReleaseId $ReleaseId
    return Join-Path $baseFull $ReleaseId
}

function Write-AtomicText([string]$Path, [string]$Value) {
    $temporary = Join-Path (Split-Path -Parent $Path) ('.autoclip-write-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $Value, (New-Object System.Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) {
            $backup = $Path + '.backup-' + [guid]::NewGuid().ToString('N')
            [IO.File]::Replace($temporary, $Path, $backup)
            try { [IO.File]::Delete($backup) } catch {
                Write-Warning "Could not remove updater backup ${backup}: $($_.Exception.Message)"
            }
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Write-StableLauncher {
    $source = @'
$ErrorActionPreference = 'Stop'
$oldBytecodeSuppression = [Environment]::GetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', 'Process')
try {
    $env:PYTHONDONTWRITEBYTECODE = '1'
$statePath = Join-Path $PSScriptRoot 'active.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw 'No active AutoClip runtime is selected. Run update.ps1 first.'
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$releaseId = [string]$state.current.release_id
if ($releaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw 'The active AutoClip release identifier is invalid.'
}
$runtimeRoot = Join-Path $PSScriptRoot $releaseId
$appStatePath = Join-Path $PSScriptRoot 'app-active.json'
if (Test-Path -LiteralPath $appStatePath -PathType Leaf) {
    $appState = Get-Content -LiteralPath $appStatePath -Raw | ConvertFrom-Json
    $appId = [string]$appState.current.app_id
    if ($appState.schema_version -ne 1 -or $appId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw 'The active AutoClip app state is invalid.'
    }
    if ($appState.current.required_runtime -eq $releaseId) {
        $site = Join-Path (Join-Path (Join-Path $PSScriptRoot 'apps') $appId) 'site'
        if (-not (Test-Path -LiteralPath (Join-Path $site 'autoclip\app.py') -PathType Leaf)) {
            throw 'The active AutoClip app layer is missing.'
        }
        $env:PYTHONPATH = $site
        $env:AUTOCLIP_MANAGED_DESKTOP_LAUNCHER = Join-Path $PSScriptRoot 'Start-AutoClip-Desktop.ps1'
        & (Join-Path $runtimeRoot '.venv\Scripts\python.exe') -m autoclip.cli serve
        return
    }
}
$launcher = Join-Path $runtimeRoot 'Start-AutoClip.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "The active AutoClip runtime is missing: $launcher"
}
& $launcher
} finally {
    [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', $oldBytecodeSuppression, 'Process')
}
'@
    Write-AtomicText $launcherPath $source
}

function Read-ActiveState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.schema_version -ne 1 -or -not $state.current) {
        throw "Unsupported or incomplete active runtime state: $statePath"
    }
    Assert-ReleaseId ([string]$state.current.release_id)
    return $state
}

function Test-InstalledRelease($Release) {
    $releaseId = [string]$Release.release_id
    $expectedManifest = [string]$Release.manifest_sha256
    Assert-ReleaseId $releaseId
    if ($expectedManifest -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Invalid manifest hash for $releaseId"
    }
    $root = Get-ReleaseRoot $releaseId
    $manifest = Join-Path $root 'release-manifest.json'
    $python = Join-Path $root '.venv\Scripts\python.exe'
    $versionLauncher = Join-Path $root 'Start-AutoClip.ps1'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $python -PathType Leaf) -or
        -not (Test-Path -LiteralPath $versionLauncher -PathType Leaf)) {
        throw "The $releaseId runtime is incomplete: $root"
    }
    $actualManifest = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    if ($actualManifest -ne $expectedManifest) {
        throw "The $releaseId release manifest does not match its pinned hash."
    }
    $manifestData = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($manifestData.native_build) {
        $receiptPath = Join-Path $root 'native-build-receipt.json'
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
            throw "The $releaseId native build receipt is missing."
        }
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        $installedFiles = @($receipt.installed_files)
        if ($installedFiles.Count -ne 8) { throw "The $releaseId native build receipt is incomplete." }
        $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $installedFiles) {
            $relative = [string]$entry.path
            if ($relative -notmatch '^\.venv/Lib/site-packages/(av\.libs/[^/]+\.dll|ctranslate2/ctranslate2\.dll)$' -or
                -not $seen.Add($relative)) {
                throw "The $releaseId native build receipt has an invalid path: $relative"
            }
            $file = [IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $file.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $file -PathType Leaf) -or
                (Get-Item -LiteralPath $file).Length -ne [long]$entry.bytes -or
                (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$entry.sha256) {
                throw "The $releaseId installed native file differs from its build receipt: $relative"
            }
        }
        if (-not $seen.Contains('.venv/Lib/site-packages/ctranslate2/ctranslate2.dll')) {
            throw "The $releaseId native build receipt lacks CTranslate2."
        }
    }

    $smokeHome = Join-Path ([IO.Path]::GetTempPath()) ('autoclip-update-check-' + [guid]::NewGuid().ToString('N'))
    $oldHome = [Environment]::GetEnvironmentVariable('AUTOCLIP_HOME', 'Process')
    try {
        $env:AUTOCLIP_HOME = $smokeHome
        & $python -B -c "import sys; from fastapi.testclient import TestClient; from autoclip.app import create_app; assert sys.version_info[:2] == (3, 11); c = TestClient(create_app()); c.__enter__(); assert c.get('/api/health').status_code == 200; assert c.get('/').status_code == 200; c.__exit__(None, None, None)"
        if ($LASTEXITCODE -ne 0) {
            throw "The $releaseId runtime failed its isolated health/home check."
        }
    } finally {
        [Environment]::SetEnvironmentVariable('AUTOCLIP_HOME', $oldHome, 'Process')
        if (Test-Path -LiteralPath $smokeHome) {
            $tempFull = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            $smokeFull = [IO.Path]::GetFullPath($smokeHome)
            if (-not $smokeFull.StartsWith($tempFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove a smoke directory outside the temporary folder.'
            }
            Remove-Item -LiteralPath $smokeFull -Recurse -Force
        }
    }
    return $root
}

function Assert-UserDatabaseCompatible([string]$Python, [string]$ReleaseId) {
    $site = $null
    $appStatePath = Join-Path $baseFull 'app-active.json'
    if (Test-Path -LiteralPath $appStatePath -PathType Leaf) {
        $appState = Get-Content -LiteralPath $appStatePath -Raw | ConvertFrom-Json
        if ($appState.schema_version -ne 1 -or -not $appState.current) {
            throw 'The active app state is invalid; runtime selection was aborted.'
        }
        if ($appState.current.required_runtime -eq $ReleaseId) {
            Assert-ReleaseId ([string]$appState.current.app_id)
            $site = Join-Path (Join-Path (Join-Path $baseFull 'apps') ([string]$appState.current.app_id)) 'site'
            if (-not (Test-Path -LiteralPath (Join-Path $site 'autoclip\app.py') -PathType Leaf)) {
                throw 'The app layer selected for this runtime is missing; runtime selection was aborted.'
            }
        }
    }

    $oldPythonPath = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    try {
        if ($site) { $env:PYTHONPATH = $site }
        else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
    $probe = @'
import sqlite3
import sys
from autoclip import paths
from autoclip.db.schema import SCHEMA_VERSION

database = paths.db_path()
if database.is_file():
    connection = sqlite3.connect(database.as_uri() + sys.argv[1], uri=True)
    version = connection.execute(sys.argv[2]).fetchone()[0]
    connection.close()
    sys.exit(42 if version > SCHEMA_VERSION else 0)
'@
        & $Python -B -c $probe '?mode=ro' 'PRAGMA user_version'
        if ($LASTEXITCODE -eq 42) {
            throw 'The user database schema is newer than the selected AutoClip app supports. Rollback would not start; keep the current release.'
        }
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not verify user database compatibility; the active release was not changed.'
        }
    } finally {
        [Environment]::SetEnvironmentVariable('PYTHONPATH', $oldPythonPath, 'Process')
    }
}

function Get-PreviousRelease([string]$NewReleaseId) {
    $priorId = $PreviousReleaseId
    if (-not $priorId) {
        $path = $ShortcutPath
        if (-not $path) {
            $desktop = [Environment]::GetFolderPath('DesktopDirectory')
            if ($desktop) { $path = Join-Path $desktop 'AutoClip.lnk' }
        }
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $null
        }
        $shell = New-Object -ComObject WScript.Shell
        $target = [IO.Path]::GetFullPath([string]$shell.CreateShortcut($path).TargetPath)
        $prefix = $baseFull + '\'
        if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
        $relative = $target.Substring($prefix.Length)
        $parts = $relative.Split('\')
        if ($parts.Length -ne 4 -or
            $parts[1] -ne '.venv' -or $parts[2] -ne 'Scripts' -or
            $parts[3] -ne 'pythonw.exe') {
            return $null
        }
        $priorId = $parts[0]
    }
    Assert-ReleaseId $priorId
    if ($priorId -eq $NewReleaseId) { return $null }
    $manifest = Join-Path (Get-ReleaseRoot $priorId) 'release-manifest.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        if ($PreviousReleaseId) { throw "Previous release manifest is missing: $manifest" }
        Write-Warning "The prior desktop runtime has no release manifest: $manifest. It will remain installed but cannot be selected by automatic rollback."
        return $null
    }
    $prior = [ordered]@{
        release_id = $priorId
        archive_sha256 = $null
        manifest_sha256 = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    try {
        [void](Test-InstalledRelease $prior)
    } catch {
        if ($PreviousReleaseId) { throw }
        Write-Warning "The prior desktop runtime did not pass an isolated check: $($_.Exception.Message). Its files remain in place."
        return $null
    }
    return $prior
}

function Update-DesktopShortcut($Release) {
    if ($NoShortcut) { return $null }
    $shortcutPath = $ShortcutPath
    if (-not $shortcutPath) {
        $desktop = [Environment]::GetFolderPath('DesktopDirectory')
        if (-not $desktop) { return $null }
        $shortcutPath = Join-Path $desktop 'AutoClip.lnk'
    }
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { return $null }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $target = [IO.Path]::GetFullPath([string]$shortcut.TargetPath)
    $managedDesktopLauncher = Join-Path $baseFull 'Start-AutoClip-Desktop.ps1'
    if (([string]$shortcut.Arguments).Contains($managedDesktopLauncher) -and
        (Test-Path -LiteralPath $managedDesktopLauncher -PathType Leaf)) {
        return $null
    }
    $managedPrefix = $baseFull + '\'
    if (-not $target.StartsWith($managedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "The existing AutoClip desktop shortcut points outside $baseFull. It was not changed; recreate it from the new app's Settings."
        return $null
    }
    $backup = Join-Path ([IO.Path]::GetTempPath()) ('autoclip-shortcut-' + [guid]::NewGuid().ToString('N') + '.lnk')
    Copy-Item -LiteralPath $shortcutPath -Destination $backup
    try {
        $newRoot = Get-ReleaseRoot ([string]$Release.release_id)
        $pythonw = Join-Path $newRoot '.venv\Scripts\pythonw.exe'
        if (-not (Test-Path -LiteralPath $pythonw -PathType Leaf)) {
            throw "The selected runtime has no desktop launcher: $pythonw"
        }
        $oldIcon = [string]$shortcut.IconLocation
        $shortcut.TargetPath = $pythonw
        $shortcut.Arguments = '-B -c "import os,runpy;os.environ[''PYTHONDONTWRITEBYTECODE'']=''1'';runpy.run_module(''autoclip.desktop'',run_name=''__main__'')"'
        $shortcut.WorkingDirectory = $newRoot
        if ($oldIcon.StartsWith($managedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $shortcut.IconLocation = (Join-Path $newRoot '.venv\Scripts\autoclip.exe') + ',0'
        }
        $shortcut.Save()
        $newTarget = [IO.Path]::GetFullPath([string]$shell.CreateShortcut($shortcutPath).TargetPath)
        $newPrefix = $newRoot.TrimEnd('\') + '\'
        if (-not $newTarget.StartsWith($newPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The refreshed desktop shortcut does not target the selected runtime.'
        }
        return $backup
    } catch {
        Copy-Item -LiteralPath $backup -Destination $shortcutPath -Force
        Remove-Item -LiteralPath $backup
        throw
    }
}

function Select-Release($Release, $Previous) {
    $selectedRoot = Test-InstalledRelease $Release
    Assert-UserDatabaseCompatible (Join-Path $selectedRoot '.venv\Scripts\python.exe') ([string]$Release.release_id)
    New-Item -ItemType Directory -Path $baseFull -Force | Out-Null
    $launcherBytes = if ([IO.File]::Exists($launcherPath)) { ,([IO.File]::ReadAllBytes($launcherPath)) } else { $null }
    $shortcutBackup = $null
    $retainShortcutBackup = $false
    try {
        Write-StableLauncher
        $shortcutBackup = Update-DesktopShortcut $Release
        $next = [ordered]@{
            schema_version = 1
            current = $Release
            previous = $Previous
        }
        Write-AtomicText $statePath ($next | ConvertTo-Json -Depth 5)
    } catch {
        $failure = $_
        $recoveryErrors = @()
        try {
            if ($null -ne $launcherBytes) {
                if (-not [IO.File]::Exists($launcherPath) -or
                    [Convert]::ToBase64String([IO.File]::ReadAllBytes($launcherPath)) -cne [Convert]::ToBase64String($launcherBytes)) {
                    [IO.File]::WriteAllBytes($launcherPath, $launcherBytes)
                }
            } elseif ([IO.File]::Exists($launcherPath)) { [IO.File]::Delete($launcherPath) }
        } catch { $recoveryErrors += "${launcherPath}: $($_.Exception.Message)" }
        if ($shortcutBackup) {
            try {
                $restorePath = $ShortcutPath
                if (-not $restorePath) {
                    $restorePath = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'AutoClip.lnk'
                }
                Copy-Item -LiteralPath $shortcutBackup -Destination $restorePath -Force
            } catch {
                $retainShortcutBackup = $true
                $recoveryErrors += "Shortcut backup ${shortcutBackup}: $($_.Exception.Message)"
            }
        }
        if ($recoveryErrors.Count) { throw "Activation failed: $($failure.Exception.Message) Recovery incomplete: $($recoveryErrors -join '; ')" }
        throw $failure
    } finally {
        if ($shortcutBackup -and -not $retainShortcutBackup -and (Test-Path -LiteralPath $shortcutBackup)) {
            try { Remove-Item -LiteralPath $shortcutBackup } catch {
                Write-Warning "Could not remove updater shortcut backup ${shortcutBackup}: $($_.Exception.Message)"
            }
        }
    }
    Write-Host "Active AutoClip runtime: $(Get-ReleaseRoot ([string]$Release.release_id))"
    Write-Host "Start with: & '$launcherPath'"
    if ($Previous) { Write-Host 'The previous runtime is retained. Run update.ps1 -Rollback to select it again.' }
}

$selectionMutex = Acquire-SelectionMutex $baseFull
try {
$state = Read-ActiveState
Show-UpdateProgress -Stage 'Checking installed release' -Percent 5
if ($Rollback) {
    try {
        if (-not $state -or -not $state.previous) { throw 'No previous AutoClip runtime is recorded for rollback.' }
        Select-Release $state.previous $state.current
    } finally {
        Complete-UpdateProgress
    }
    return
}

$authenticatedInstaller = $null
try {
    $authenticatedInstaller = Open-AuthenticatedInstaller $InstallerPath $InstallerSha256
    $InstallerPath = $authenticatedInstaller.Path
    $info = & $InstallerPath -ReleaseInfo -PrerequisitesOnly
    Show-UpdateProgress -Stage 'Preparing exact release' -Percent 15
    if (@($info).Count -ne 1) { throw 'The current installer did not report one release identity.' }
    $releaseId = [string]$info.ReleaseId
    Assert-ReleaseId $releaseId
    if ([string]$info.ArchiveSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [string]$info.ManifestSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'The current installer did not report pinned archive and manifest hashes.'
    }
    $release = [ordered]@{
        release_id = $releaseId
        archive_sha256 = [string]$info.ArchiveSha256
        manifest_sha256 = [string]$info.ManifestSha256
    }
    $targetRoot = Get-ReleaseRoot $releaseId
    $preserveNvidiaGpu = $false
    if (-not $CpuOnly -and $state -and $state.current) {
        $activeReceiptPath = Join-Path (Get-ReleaseRoot ([string]$state.current.release_id)) 'native-build-receipt.json'
        if (Test-Path -LiteralPath $activeReceiptPath -PathType Leaf) {
            $activeReceipt = Get-Content -LiteralPath $activeReceiptPath -Raw | ConvertFrom-Json
            $preserveNvidiaGpu = [string]$activeReceipt.profile -eq 'nvidia'
        }
    }
    $wantNvidiaGpu = [bool]($InstallNvidiaGpu -or $preserveNvidiaGpu)
    $targetReceiptPath = Join-Path $targetRoot 'native-build-receipt.json'
    if (Test-Path -LiteralPath $targetReceiptPath -PathType Leaf) {
        $targetReceipt = Get-Content -LiteralPath $targetReceiptPath -Raw | ConvertFrom-Json
        $expectedProfile = if ($wantNvidiaGpu) { 'nvidia' } else { 'cpu' }
        if ([string]$targetReceipt.profile -ne $expectedProfile) {
            throw "The existing source-build runtime has profile $($targetReceipt.profile), but this update requires $expectedProfile. Use a distinct release identity for a different profile."
        }
    }
    if ($state -and $state.current.release_id -eq $releaseId -and
        $state.current.archive_sha256 -eq $release.archive_sha256) {
        try {
            [void](Test-InstalledRelease $state.current)
            Write-StableLauncher
            $shortcutBackup = Update-DesktopShortcut $state.current
            if ($shortcutBackup) { Remove-Item -LiteralPath $shortcutBackup }
            Write-Host "AutoClip is already up to date: $releaseId"
            return
        } catch {
            Write-Warning "The active $releaseId runtime needs repair: $($_.Exception.Message)"
        }
    }
    $validExisting = $false
    if (Test-Path -LiteralPath (Join-Path $targetRoot '.venv\Scripts\python.exe')) {
        try {
            [void](Test-InstalledRelease $release)
            $validExisting = $true
        } catch {
            Write-Warning "The existing $releaseId runtime did not pass verification; attempting a safe installer retry: $($_.Exception.Message)"
        }
    }
    if (-not $validExisting) {
        Show-UpdateProgress -Stage 'Installing and verifying new runtime' -Percent 25
        $arguments = @{ InstallRoot = $targetRoot }
        if ($ArchivePath) { $arguments.ArchivePath = $ArchivePath }
        if ($ExternalCache) { $arguments.ExternalCache = $ExternalCache }
        if ($NativeBuildRoot) { $arguments.NativeBuildRoot = $NativeBuildRoot }
        if ($MsysBash) { $arguments.MsysBash = $MsysBash }
        if ($CudaRoot) { $arguments.CudaRoot = $CudaRoot }
        foreach ($name in @('AcceptNvidiaTerms', 'AcceptMicrosoftTerms', 'NonInteractive')) {
            if (Get-Variable -Name $name -ValueOnly) {
                if (-not (Get-Command -Name $InstallerPath).Parameters.ContainsKey($name)) { throw "Selected installer does not support -$name." }
                $arguments[$name] = $true
            }
        }
        if ($wantNvidiaGpu) {
            if (-not (Get-Command -Name $InstallerPath).Parameters.ContainsKey('InstallNvidiaGpu')) {
                if ($InstallNvidiaGpu) { throw 'The selected installer does not support -InstallNvidiaGpu.' }
                throw 'The selected installer cannot preserve the active NVIDIA profile. Select a compatible source-build installer or pass -CpuOnly.'
            }
            $arguments.InstallNvidiaGpu = $true
        }
        & $InstallerPath @arguments
    }
    Show-UpdateProgress -Stage 'Activating verified release' -Percent 90
    $previous = if ($state -and $state.current.release_id -eq $releaseId) {
        $state.previous
    } elseif ($state) {
        $state.current
    } else {
        Get-PreviousRelease $releaseId
    }
    Select-Release $release $previous
} finally {
    try { Complete-UpdateProgress }
    finally { if ($authenticatedInstaller) { foreach ($held in $authenticatedInstaller.Locks) { $held.Dispose() } } }
}
} finally {
    try { $selectionMutex.ReleaseMutex() }
    finally { $selectionMutex.Dispose() }
}
