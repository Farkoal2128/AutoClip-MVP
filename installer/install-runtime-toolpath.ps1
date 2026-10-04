[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleaseRoot,
    [Parameter(Mandatory = $true)][string]$ManagedToolRoot,
    [Parameter(Mandatory = $true)][string]$ManifestPath
)
$ErrorActionPreference = 'Stop'

function Get-SafeRuntimeToolPath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(3) -match '[;:*?"<>|\x00-\x1f]' -or
        @($Path.Substring(3).Split([char[]]'\/') | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' -or $_.EndsWith('.') -or $_.EndsWith(' ') }).Count) {
        throw 'Runtime tool path must be absolute and free of traversal or unsafe characters.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Runtime tool path contains a reparse point.'
        }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    $full
}

$root = Get-SafeRuntimeToolPath $ReleaseRoot
$managed = Get-SafeRuntimeToolPath $ManagedToolRoot
if (-not $managed.Equals((Join-Path $root 'tools\ffmpeg'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'FFmpeg must use the expected managed release tools\ffmpeg directory.'
}
$venv = Join-Path $root '.venv'
$site = Get-SafeRuntimeToolPath (Join-Path $venv 'Lib\site-packages')
$cfg = Get-SafeRuntimeToolPath (Join-Path $venv 'pyvenv.cfg')
foreach ($path in @($site, $cfg, (Join-Path $venv 'Scripts\python.exe'), (Join-Path $venv 'Scripts\pythonw.exe'))) {
    $checked = Get-SafeRuntimeToolPath $path
    if (-not (Test-Path -LiteralPath $checked)) { throw 'Expected release-owned .venv is incomplete.' }
}
$configuration = Get-Content -LiteralPath $cfg -Raw
$identityFields = @([regex]::Matches($configuration, '(?im)^[ \t]*(version|version_info|include-system-site-packages|implementation)[ \t]*=[ \t]*([^\r\n]*?)[ \t]*\r?$'))
$versions = @($identityFields | Where-Object { $_.Groups[1].Value -in @('version', 'version_info') })
$isolation = @($identityFields | Where-Object { $_.Groups[1].Value -ieq 'include-system-site-packages' })
$implementation = @($identityFields | Where-Object { $_.Groups[1].Value -ieq 'implementation' })
$duplicateIdentity = @($identityFields | Group-Object { $_.Groups[1].Value.ToLowerInvariant() } | Where-Object Count -gt 1)
if (-not $versions.Count -or $duplicateIdentity.Count -or
    @($versions | Where-Object { $_.Groups[2].Value -cne '3.11.9' }).Count -or
    $isolation.Count -ne 1 -or $isolation[0].Groups[2].Value -cne 'false' -or
    @($implementation | Where-Object { $_.Groups[2].Value -cne 'CPython' }).Count) {
    throw 'Runtime tool startup requires the expected isolated Python 3.11.9 venv.'
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Unsupported runtime tool dependency manifest.' }
$records = @($manifest.build_prerequisites | Where-Object identity -CEQ 'Gyan FFmpeg')
if ($records.Count -ne 1 -or $records[0].delivery_classification -cne 'DIRECT_RECIPIENT_DOWNLOAD') {
    throw 'FFmpeg registration requires DIRECT_RECIPIENT_DOWNLOAD classification.'
}
$item = $records[0]
$pins = @(
    @{ path = 'ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'; sha256 = '72a489eccd008c2ec2c0a5856c5c75bc3d8bbfa90166c4566865c246445e6aa3' },
    @{ path = 'ffmpeg-9.0.1-essentials_build/bin/ffprobe.exe'; sha256 = '19202b23c0043f15ad1b7bce2344f406fd52bd6efd8f995ce02e7392a1cec52f' }
)
if ($item.version -cne '9.0.1' -or $item.architecture -cne 'x64' -or
    $item.url -cne 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.1/ffmpeg-9.0.1-essentials_build.zip' -or
    @($item.executable_pins).Count -ne 2) { throw 'Exact FFmpeg essentials executable pins are required.' }
foreach ($pin in $pins) {
    $record = @($item.executable_pins | Where-Object { $_.path -ceq $pin.path -and $_.sha256 -ceq $pin.sha256 })
    $executable = Get-SafeRuntimeToolPath (Join-Path $managed $pin.path.Replace('/', '\'))
    if ($record.Count -ne 1) { throw 'Exact FFmpeg essentials executable pins differ.' }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf) -or
        (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ne $pin.sha256) {
        throw 'Managed FFmpeg executable SHA-256 differs.'
    }
}
$bin = Get-SafeRuntimeToolPath (Join-Path $managed 'ffmpeg-9.0.1-essentials_build\bin')
# ASCII source safely carries arbitrary valid Unicode paths; no path text becomes Python syntax.
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$hex = [BitConverter]::ToString($utf8.GetBytes($bin)).Replace('-', '').ToLowerInvariant()
$content = "# AutoClip managed FFmpeg startup v1`nimport os; _autoclip_ffmpeg_bin = bytes.fromhex('$hex').decode('utf-8'); os.environ['PATH'] = os.environ.get('PATH', '') if os.environ.get('PATH', '').split(os.pathsep)[0] == _autoclip_ffmpeg_bin else _autoclip_ffmpeg_bin + os.pathsep + os.environ.get('PATH', '')`n"
$bytes = [Text.Encoding]::ASCII.GetBytes($content)
$sha = [Security.Cryptography.SHA256]::Create()
try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
$pth = Get-SafeRuntimeToolPath (Join-Path $site 'autoclip_ffmpeg_path.pth')
function Assert-OwnedRuntimeToolFile {
    if (-not (Test-Path -LiteralPath $pth -PathType Leaf) -or
        (Get-Item -LiteralPath $pth).Length -ne $bytes.Length -or (Get-FileHash -LiteralPath $pth).Hash -ne $hash) {
        throw 'Refusing to overwrite foreign or different runtime tool startup content.'
    }
}
if (Test-Path -LiteralPath $pth) { Assert-OwnedRuntimeToolFile } else {
    $temporary = Join-Path $site ('autoclip-toolpath-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    try {
        try { [IO.File]::Move($temporary, $pth) } catch {
            if (-not (Test-Path -LiteralPath $pth)) { throw }
            Get-SafeRuntimeToolPath $pth | Out-Null
            Assert-OwnedRuntimeToolFile
        }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
[pscustomobject]@{
    release_root = $root; venv_root = $venv; managed_bin = $bin
    pth_path = $pth; pth_bytes = $bytes.Length; pth_sha256 = $hash
    manifest_sha256 = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    executable_pins = $pins
}
