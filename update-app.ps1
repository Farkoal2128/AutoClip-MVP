param(
    [string]$BaseRoot,
    [string]$ManifestPath,
    [string]$WheelPath,
    [string]$ShortcutPath,
    [switch]$Rollback,
    [switch]$NoShortcut,
    [scriptblock]$StopOwnedApp
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    throw 'The app-only updater supports Windows x64 only.'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'The app-only updater requires 64-bit Windows.'
}
if (-not $BaseRoot) { $BaseRoot = Join-Path $env:LOCALAPPDATA 'AutoClip' }
$baseFull = [IO.Path]::GetFullPath($BaseRoot).TrimEnd('\')
$runtimeStatePath = Join-Path $baseFull 'active.json'
$appStatePath = Join-Path $baseFull 'app-active.json'
$launcherPath = Join-Path $baseFull 'Start-AutoClip.ps1'
$desktopLauncherPath = Join-Path $baseFull 'Start-AutoClip-Desktop.ps1'
$manifestUrl = 'https://raw.githubusercontent.com/Farkoal2128/AutoClip-MVP/main/app-release.json'
$expectedManifestSha256 = '9648d4bce76f2ea2f0c3c0782cdfd868f96d6aabce64d1c30a48d8aa2667d236'

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

function Assert-Id([string]$Value) {
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Invalid release identifier: $Value" }
}

function Assert-Sha([string]$Value) {
    if ($Value -notmatch '^[0-9a-fA-F]{64}$') { throw "Invalid SHA-256: $Value" }
}

function Assert-AppStopped {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $attempt = $client.BeginConnect('127.0.0.1', 8000, $null, $null)
        if ($attempt.AsyncWaitHandle.WaitOne(500)) {
            try {
                $client.EndConnect($attempt)
                throw 'Local port 8000 is in use. Quit AutoClip before updating.'
            } catch [Net.Sockets.SocketException] { }
        }
    } finally { $client.Close() }
}

function Write-AtomicText([string]$Path, [string]$Value) {
    $temporary = Join-Path (Split-Path -Parent $Path) ('.autoclip-write-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, $Value, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) {
            $backup = $Path + '.backup-' + [guid]::NewGuid().ToString('N')
            [IO.File]::Replace($temporary, $Path, $backup)
            try { [IO.File]::Delete($backup) } catch {
                Write-Warning "Could not remove updater backup ${backup}: $($_.Exception.Message)"
            }
        } else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Read-RuntimeState {
    if (-not (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf)) {
        throw 'No verified runtime is selected. Use the full Windows installer first.'
    }
    $state = Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
    if ($state.schema_version -ne 1 -or -not $state.current) {
        throw 'The installed runtime state is unsupported.'
    }
    Assert-Id ([string]$state.current.release_id)
    Assert-Sha ([string]$state.current.manifest_sha256)
    $root = Join-Path $baseFull ([string]$state.current.release_id)
    $manifest = Join-Path $root 'release-manifest.json'
    $python = Join-Path $root '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $python -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $root '.install-complete') -PathType Leaf)) {
        throw 'The selected runtime is incomplete. Use the full updater to repair it.'
    }
    if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ne $state.current.manifest_sha256) {
        throw 'The selected runtime manifest hash does not match active.json.'
    }
    return [pscustomobject]@{ state = $state; root = $root; python = $python }
}

function Read-AppManifest([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "App manifest is missing: $Path" }
    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($manifest.schema_version -ne 1) { throw 'Unsupported app manifest schema.' }
    Assert-Id ([string]$manifest.app_id)
    Assert-Id ([string]$manifest.required_runtime)
    Assert-Sha ([string]$manifest.runtime_manifest_sha256)
    if ($manifest.PSObject.Properties.Name -contains 'compatible_runtimes') {
        foreach ($compatible in @($manifest.compatible_runtimes)) {
            Assert-Id ([string]$compatible.release_id)
            Assert-Sha ([string]$compatible.manifest_sha256)
        }
    }
    Assert-Sha ([string]$manifest.wheel_sha256)
    if ([long]$manifest.wheel_size -le 0) { throw 'Invalid app wheel size.' }
    return $manifest
}

function Test-AppLayer($App) {
    Assert-Id ([string]$App.app_id)
    Assert-Sha ([string]$App.wheel_sha256)
    $root = Join-Path (Join-Path $baseFull 'apps') ([string]$App.app_id)
    $wheel = Join-Path $root 'autoclip.whl'
    $site = Join-Path $root 'site'
    if (-not (Test-Path -LiteralPath $wheel -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $site 'autoclip\app.py') -PathType Leaf)) {
        throw 'The app layer is incomplete.'
    }
    if ((Get-FileHash -LiteralPath $wheel -Algorithm SHA256).Hash -ne $App.wheel_sha256) {
        throw 'The app layer wheel hash does not match its manifest.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($wheel)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            $file = Join-Path $site $entry.FullName.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'The app layer content differs from its wheel.' }
            $stream = $entry.Open()
            try { $expected = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash }
            finally { $stream.Dispose() }
            if ((Get-Item -LiteralPath $file).Length -ne $entry.Length -or
                (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $expected) {
                throw 'The app layer content differs from its wheel.'
            }
        }
    } finally { $zip.Dispose() }
    return $site
}

function Test-AppHealth($Python, [string]$Site) {
    $oldHome = [Environment]::GetEnvironmentVariable('AUTOCLIP_HOME', 'Process')
    $oldPythonPath = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    $smokeHome = Join-Path ([IO.Path]::GetTempPath()) ('autoclip-app-check-' + [guid]::NewGuid().ToString('N'))
    try {
        $env:AUTOCLIP_HOME = $smokeHome
        $env:PYTHONPATH = $Site
        $dependencyCheck = @'
import importlib.metadata as metadata
import sys

from packaging.requirements import Requirement

site = sys.argv[1]
apps = [dist for dist in metadata.distributions(path=[site])
        if dist.metadata.get('Name', '').lower() == 'autoclip']
if len(apps) != 1:
    raise SystemExit('Expected one staged AutoClip distribution.')
missing = []
for raw in apps[0].requires or []:
    requirement = Requirement(raw)
    if requirement.marker and not requirement.marker.evaluate({'extra': ''}):
        continue
    try:
        installed = metadata.version(requirement.name)
    except metadata.PackageNotFoundError:
        missing.append(f'{requirement.name} (absent)')
        continue
    if requirement.specifier and installed not in requirement.specifier:
        missing.append(f'{requirement.name} {installed} (requires {requirement.specifier})')
if missing:
    raise SystemExit('Missing or incompatible runtime dependencies: ' + ', '.join(missing))
'@
        & $Python -B -c $dependencyCheck $Site
        if ($LASTEXITCODE -ne 0) { throw 'The staged app has a missing runtime dependency.' }
        & $Python -B -c "import pathlib; from fastapi.testclient import TestClient; from autoclip.app import create_app; import autoclip; assert pathlib.Path(autoclip.__file__).resolve().is_relative_to(pathlib.Path(r'$Site').resolve()); c = TestClient(create_app()); c.__enter__(); assert c.get('/api/health').status_code == 200; assert c.get('/').status_code == 200; c.__exit__(None, None, None)"
        if ($LASTEXITCODE -ne 0) { throw 'The staged app failed isolated health/home.' }
    } finally {
        [Environment]::SetEnvironmentVariable('AUTOCLIP_HOME', $oldHome, 'Process')
        [Environment]::SetEnvironmentVariable('PYTHONPATH', $oldPythonPath, 'Process')
        if (Test-Path -LiteralPath $smokeHome) {
            $tempFull = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            $smokeFull = [IO.Path]::GetFullPath($smokeHome)
            if (-not $smokeFull.StartsWith($tempFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove smoke data outside the temporary directory.'
            }
            Remove-Item -LiteralPath $smokeFull -Recurse -Force
        }
    }
}

function Assert-AppDatabaseCompatible($Python, [string]$Site) {
    $oldPythonPath = [Environment]::GetEnvironmentVariable('PYTHONPATH', 'Process')
    try {
        if ($Site) { $env:PYTHONPATH = $Site }
        else { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue }
        $probe = @'
from pathlib import Path
import sqlite3
import sys

from autoclip import paths
from autoclip.db.schema import SCHEMA_VERSION

database = Path(paths.db_path())
if database.is_file():
    with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as connection:
        version = int(connection.execute('PRAGMA user_version').fetchone()[0])
    if version > SCHEMA_VERSION:
        raise SystemExit(42)
'@
        & $Python -B -c $probe
        if ($LASTEXITCODE -eq 42) {
            throw 'The user database schema is newer than this app supports. Rollback was aborted and the selected app was kept.'
        }
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not verify user database compatibility; app rollback was aborted.'
        }
    } finally {
        [Environment]::SetEnvironmentVariable('PYTHONPATH', $oldPythonPath, 'Process')
    }
}

function Write-StableLauncher {
    $source = @'
$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$base = $PSScriptRoot
$runtimeState = Get-Content -LiteralPath (Join-Path $base 'active.json') -Raw | ConvertFrom-Json
$releaseId = [string]$runtimeState.current.release_id
if ($releaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Invalid active runtime identifier.' }
$runtimeRoot = Join-Path $base $releaseId
$appStatePath = Join-Path $base 'app-active.json'
if (Test-Path -LiteralPath $appStatePath -PathType Leaf) {
    $appState = Get-Content -LiteralPath $appStatePath -Raw | ConvertFrom-Json
    $appId = [string]$appState.current.app_id
    if ($appId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw 'The selected app identifier is invalid.'
    }
    if ($appState.current.required_runtime -eq $releaseId) {
        $site = Join-Path (Join-Path (Join-Path $base 'apps') $appId) 'site'
        if (-not (Test-Path -LiteralPath (Join-Path $site 'autoclip\app.py') -PathType Leaf)) {
            throw 'The selected app layer is missing.'
        }
        $env:PYTHONPATH = $site
        $env:AUTOCLIP_MANAGED_DESKTOP_LAUNCHER = Join-Path $base 'Start-AutoClip-Desktop.ps1'
        & (Join-Path $runtimeRoot '.venv\Scripts\python.exe') -m autoclip.cli serve
        return
    }
}
& (Join-Path $runtimeRoot 'Start-AutoClip.ps1')
'@
    Write-AtomicText $launcherPath $source
}

function Write-DesktopLauncher {
    $source = @'
$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$base = $PSScriptRoot
$runtimeState = Get-Content -LiteralPath (Join-Path $base 'active.json') -Raw | ConvertFrom-Json
$releaseId = [string]$runtimeState.current.release_id
if ($releaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Invalid active runtime identifier.' }
$runtimeRoot = Join-Path $base $releaseId
$appStatePath = Join-Path $base 'app-active.json'
if (Test-Path -LiteralPath $appStatePath -PathType Leaf) {
    $appState = Get-Content -LiteralPath $appStatePath -Raw | ConvertFrom-Json
    $appId = [string]$appState.current.app_id
    if ($appId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Invalid active app identifier.' }
    if ($appState.current.required_runtime -eq $releaseId) {
        $site = Join-Path (Join-Path (Join-Path $base 'apps') $appId) 'site'
        if (-not (Test-Path -LiteralPath (Join-Path $site 'autoclip\app.py') -PathType Leaf)) {
            throw 'The active app layer is missing.'
        }
        $env:PYTHONPATH = $site
        $env:AUTOCLIP_MANAGED_DESKTOP_LAUNCHER = $PSCommandPath
    }
}
& (Join-Path $runtimeRoot '.venv\Scripts\pythonw.exe') -m autoclip.desktop
'@
    Write-AtomicText $desktopLauncherPath $source
}

function Update-DesktopShortcut {
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
    $managed = $target.StartsWith(($baseFull + '\'), [StringComparison]::OrdinalIgnoreCase) -or
        ([string]$shortcut.Arguments).Contains($desktopLauncherPath)
    if (-not $managed) {
        Write-Warning 'The existing desktop shortcut points outside the managed runtime. Recreate it from Settings.'
        return $null
    }
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $backup = Join-Path ([IO.Path]::GetTempPath()) ('autoclip-app-shortcut-' + [guid]::NewGuid().ToString('N') + '.lnk')
    Copy-Item -LiteralPath $shortcutPath -Destination $backup
    try {
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + $desktopLauncherPath + '"'
        $shortcut.WorkingDirectory = $baseFull
        $shortcut.Save()
        return $backup
    } catch {
        Copy-Item -LiteralPath $backup -Destination $shortcutPath -Force
        Remove-Item -LiteralPath $backup
        throw
    }
}

function Commit-AppState([string]$Value, [switch]$Remove) {
    $launcherBackups = @(@($launcherPath, $desktopLauncherPath) | ForEach-Object {
        [pscustomobject]@{ path = $_; bytes = $(if ([IO.File]::Exists($_)) { ,([IO.File]::ReadAllBytes($_)) } else { $null }) }
    })
    $shortcutBackup = $null
    $retainShortcutBackup = $false
    try {
        Write-StableLauncher
        Write-DesktopLauncher
        $shortcutBackup = Update-DesktopShortcut
        if ($Remove) { Remove-Item -LiteralPath $appStatePath }
        else { Write-AtomicText $appStatePath $Value }
    } catch {
        $failure = $_
        $recoveryErrors = @()
        foreach ($backup in $launcherBackups) {
            try {
                if ($null -ne $backup.bytes) {
                    if (-not [IO.File]::Exists($backup.path) -or
                        [Convert]::ToBase64String([IO.File]::ReadAllBytes($backup.path)) -cne [Convert]::ToBase64String($backup.bytes)) {
                        [IO.File]::WriteAllBytes($backup.path, $backup.bytes)
                    }
                } elseif ([IO.File]::Exists($backup.path)) { [IO.File]::Delete($backup.path) }
            } catch { $recoveryErrors += "$($backup.path): $($_.Exception.Message)" }
        }
        if ($shortcutBackup) {
            try {
                $path = $ShortcutPath
                if (-not $path) { $path = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'AutoClip.lnk' }
                Copy-Item -LiteralPath $shortcutBackup -Destination $path -Force
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
}

$selectionMutex = Acquire-SelectionMutex $baseFull
try {
$runtime = Read-RuntimeState
if ($StopOwnedApp) { & $StopOwnedApp $runtime.root }
Assert-AppStopped
$existing = $null
if (Test-Path -LiteralPath $appStatePath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $appStatePath -Raw | ConvertFrom-Json
    if ($existing.schema_version -ne 1 -or -not $existing.current) { throw 'Unsupported app activation state.' }
}

if ($Rollback) {
    if (-not $existing) { throw 'No app-only update is selected for rollback.' }
    if ($existing.previous) {
        if ($existing.previous.required_runtime -ne $runtime.state.current.release_id) {
            throw 'The previous app requires another runtime; use the full updater.'
        }
        $site = Test-AppLayer $existing.previous
        Assert-AppDatabaseCompatible $runtime.python $site
        Test-AppHealth $runtime.python $site
        $next = [ordered]@{ schema_version = 1; current = $existing.previous; previous = $existing.current }
        Commit-AppState ($next | ConvertTo-Json -Depth 5)
    } else {
        Assert-AppDatabaseCompatible $runtime.python $null
        Test-AppHealth $runtime.python (Join-Path $runtime.root '.venv/Lib/site-packages')
        Commit-AppState '' -Remove
    }
    Write-Host 'Previous AutoClip app selected.'
    return
}

$downloadedManifest = $null
if (-not $ManifestPath) {
    if ($expectedManifestSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'The app release manifest is not pinned yet.'
    }
    $downloadedManifest = Join-Path ([IO.Path]::GetTempPath()) ('autoclip-app-manifest-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $manifestUrl -OutFile $downloadedManifest
        $ManifestPath = $downloadedManifest
    } catch {
        if (Test-Path -LiteralPath $downloadedManifest) { Remove-Item -LiteralPath $downloadedManifest }
        throw
    }
}
try {
    if ($downloadedManifest -and
        (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash -ne $expectedManifestSha256) {
        throw 'The downloaded app manifest SHA-256 does not match the pinned release.'
    }
$manifest = Read-AppManifest $ManifestPath
$runtimeMatches = ($manifest.required_runtime -eq $runtime.state.current.release_id -and
    $manifest.runtime_manifest_sha256 -eq $runtime.state.current.manifest_sha256)
foreach ($compatible in @($manifest.compatible_runtimes)) {
    if ($compatible -and $compatible.release_id -eq $runtime.state.current.release_id -and
        $compatible.manifest_sha256 -eq $runtime.state.current.manifest_sha256) {
        $runtimeMatches = $true
    }
}
if (-not $runtimeMatches) {
    throw 'The app requires a different runtime. Use the full updater.'
}
$app = [ordered]@{
    app_id = [string]$manifest.app_id
    required_runtime = [string]$runtime.state.current.release_id
    wheel_sha256 = [string]$manifest.wheel_sha256
}
if ($existing -and $existing.current.app_id -eq $app.app_id) {
    $site = Test-AppLayer $existing.current
    Test-AppHealth $runtime.python $site
    Write-StableLauncher
    Write-DesktopLauncher
    $shortcutBackup = Update-DesktopShortcut
    if ($shortcutBackup) { Remove-Item -LiteralPath $shortcutBackup }
    Write-Host "AutoClip app is already up to date: $($app.app_id)"
    return
}
if (-not $WheelPath -or -not (Test-Path -LiteralPath $WheelPath -PathType Leaf)) {
    if ($WheelPath) { throw 'The pinned app wheel is missing.' }
    $wheelUrl = [string]$manifest.wheel_url
    if ($wheelUrl -notmatch '^https://github\.com/Farkoal2128/AutoClip-MVP/releases/download/[^/]+/autoclip-[^/]+\.whl$') {
        throw 'The pinned app wheel URL is missing or invalid.'
    }
    $WheelPath = Join-Path ([IO.Path]::GetTempPath()) ('autoclip-app-wheel-' + [guid]::NewGuid().ToString('N') + '.whl')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $wheelUrl -OutFile $WheelPath
    } catch {
        if (Test-Path -LiteralPath $WheelPath) { Remove-Item -LiteralPath $WheelPath }
        throw
    }
    $downloadedWheel = $WheelPath
}
try {
if ((Get-Item -LiteralPath $WheelPath).Length -ne [long]$manifest.wheel_size -or
    (Get-FileHash -LiteralPath $WheelPath -Algorithm SHA256).Hash -ne $manifest.wheel_sha256) {
    throw 'The app wheel size or SHA-256 does not match its manifest.'
}
$appsRoot = Join-Path $baseFull 'apps'
New-Item -ItemType Directory -Path $appsRoot -Force | Out-Null
$target = Join-Path $appsRoot $app.app_id
if (Test-Path -LiteralPath $target) {
    $site = Test-AppLayer $app
    Test-AppHealth $runtime.python $site
    Assert-AppDatabaseCompatible $runtime.python $site
} else {
    $staging = Join-Path $appsRoot ('.staging-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        $site = Join-Path $staging 'site'
        New-Item -ItemType Directory -Path $site | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($WheelPath)
        try {
            foreach ($entry in $zip.Entries) {
                $name = $entry.FullName.Replace('\', '/')
                if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name -match '^[A-Za-z]:') {
                    throw 'The app wheel contains an unsafe path.'
                }
            }
        } finally { $zip.Dispose() }
        [IO.Compression.ZipFile]::ExtractToDirectory($WheelPath, $site)
        Copy-Item -LiteralPath $WheelPath -Destination (Join-Path $staging 'autoclip.whl')
        Test-AppHealth $runtime.python $site
        Assert-AppDatabaseCompatible $runtime.python $site
        Move-Item -LiteralPath $staging -Destination $target
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
}
$previous = if ($existing) { $existing.current } else { $null }
$next = [ordered]@{ schema_version = 1; current = $app; previous = $previous }
Commit-AppState ($next | ConvertTo-Json -Depth 5)
Write-Host "Active AutoClip app: $($app.app_id)"
Write-Host "Start with: & '$launcherPath'"
} finally {
    if ($downloadedWheel -and (Test-Path -LiteralPath $downloadedWheel)) {
        Remove-Item -LiteralPath $downloadedWheel
    }
}
} finally {
    if ($downloadedManifest -and (Test-Path -LiteralPath $downloadedManifest)) {
        Remove-Item -LiteralPath $downloadedManifest
    }
}
} finally {
    try { $selectionMutex.ReleaseMutex() }
    finally { $selectionMutex.Dispose() }
}
