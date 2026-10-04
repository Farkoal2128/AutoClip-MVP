param(
    [Parameter(Mandatory)][ValidateSet('Git for Windows', 'uv', 'Gyan FFmpeg')][string]$Identity,
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$DestinationRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Unsupported installer dependency manifest.' }
$expected = switch ($Identity) {
    'Git for Windows' { @{ version = '2.55.0.3'; executable = 'cmd\git.exe'; signer = 'Johannes Schindelin'; output = '^git version 2\.55\.0\.windows\.3$' } }
    'uv' { @{ version = '0.12.19'; executable = 'uv.exe'; signer = 'OpenAI OpCo, LLC'; output = '^uv 0\.12\.19\b' } }
    'Gyan FFmpeg' { @{ version = '9.0.1'; executable = 'ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe'; output = '^ffmpeg version 9\.0\.1-essentials_build-www\.gyan\.dev(?:\s|$)' } }
}
$item = @($manifest.build_prerequisites | Where-Object identity -eq $Identity)
if ($item.Count -ne 1 -or $item[0].delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD' -or
    $item[0].version -ne $expected.version) { throw "Pinned $Identity route is unavailable." }
$item = $item[0]
if ($Identity -eq 'Gyan FFmpeg') {
    $ffmpegPins = @(
        @{ path = 'ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'; sha256 = '72a489eccd008c2ec2c0a5856c5c75bc3d8bbfa90166c4566865c246445e6aa3' },
        @{ path = 'ffmpeg-9.0.1-essentials_build/bin/ffprobe.exe'; sha256 = '19202b23c0043f15ad1b7bce2344f406fd52bd6efd8f995ce02e7392a1cec52f' }
    )
    if ($item.architecture -ne 'x64' -or
        $item.url -ne 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.1/ffmpeg-9.0.1-essentials_build.zip' -or
        @($item.executable_pins).Count -ne 2) { throw 'Exact FFmpeg essentials executable pins are required.' }
    foreach ($pin in $ffmpegPins) {
        $selected = @($item.executable_pins | Where-Object { $_.path -eq $pin.path -and $_.sha256 -eq $pin.sha256 })
        if ($selected.Count -ne 1) { throw 'Exact FFmpeg essentials executable pins differ.' }
    }
}
$archive = [IO.Path]::GetFullPath($ArchivePath)
$dest = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
$temp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
if (-not $dest.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $dest)) { throw 'Tool staging must be a new directory under TEMP.' }
if ((Get-Item -LiteralPath $archive).Length -ne [long]$item.bytes -or
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne [string]$item.sha256) {
    throw "$Identity archive size or SHA-256 differs from the pinned manifest."
}

$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        $parts = $name.TrimEnd('/').Split('/')
        if (-not $name -or $name.StartsWith('/') -or $name.Contains(':') -or
            $name -match '[<>"|?*\x00-\x1f]' -or
            (($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960 -or
            @($parts | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' }).Count -or
            -not $seen.Add($name.TrimEnd('/'))) {
            throw "Unsafe tool ZIP entry: $name"
        }
        if ($Identity -eq 'Gyan FFmpeg' -and $parts[0] -ne 'ffmpeg-9.0.1-essentials_build') {
            throw 'FFmpeg ZIP has an unexpected top-level directory.'
        }
    }
    $parent = Split-Path -Parent $dest
    $cursor = $parent
    while ($cursor -and (Test-Path -LiteralPath $cursor)) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Tool staging parent is a reparse point.'
        }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    [IO.Directory]::CreateDirectory($dest) | Out-Null
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $target = [IO.Path]::GetFullPath((Join-Path $dest $name.Replace('/', '\')))
            if (-not $target.StartsWith($dest + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Tool ZIP entry escaped staging: $name"
            }
            if ($name.EndsWith('/')) {
                [IO.Directory]::CreateDirectory($target) | Out-Null
            } else {
                [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
                $inputStream = $entry.Open()
                $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
            }
        }
        $executable = Join-Path $dest $expected.executable
        if ($Identity -eq 'Gyan FFmpeg') {
            # The exact upstream EXEs are unsigned; recorded executable hashes establish identity.
            foreach ($pin in $item.executable_pins) {
                $selected = Join-Path $dest $pin.path.Replace('/', '\')
                if (-not (Test-Path -LiteralPath $selected -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $selected -Algorithm SHA256).Hash -ne $pin.sha256) {
                    throw 'FFmpeg extracted executable SHA-256 differs.'
                }
            }
            $version = & $executable -version | Out-String
        } else {
            $signature = Get-AuthenticodeSignature -LiteralPath $executable
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch [regex]::Escape($expected.signer)) {
                throw "$Identity executable signature or publisher differs."
            }
            $version = & $executable --version | Out-String
        }
        if ($LASTEXITCODE -ne 0 -or $version.Trim() -notmatch $expected.output) {
            throw "$Identity executable version differs."
        }
        if ($Identity -eq 'Gyan FFmpeg') {
            $ffprobe = Join-Path (Split-Path -Parent $executable) 'ffprobe.exe'
            $probeVersion = & $ffprobe -version | Out-String
            if ($LASTEXITCODE -ne 0 -or $probeVersion -notmatch '^ffprobe version 9\.0\.1-essentials_build-www\.gyan\.dev(?:\s|$)') {
                throw 'FFprobe executable version differs.'
            }
            $filters = & $executable -hide_banner -filters | Out-String
            if ($LASTEXITCODE -ne 0 -or $filters -notmatch '(?m)^\s*\S+\s+ass\s' -or $filters -notmatch '(?m)^\s*\S+\s+subtitles\s') {
                throw 'FFmpeg ASS/subtitles filters are unavailable.'
            }
            $encoders = & $executable -hide_banner -encoders | Out-String
            if ($LASTEXITCODE -ne 0 -or $encoders -notmatch '(?m)^\s*V\S*\s+libx264\s') {
                throw 'FFmpeg libx264 encoder is unavailable.'
            }
        }
    } catch {
        if ((Test-Path -LiteralPath $dest -PathType Container) -and
            -not ((Get-Item -LiteralPath $dest -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $dest -Recurse -Force
        }
        throw
    }
} finally { $zip.Dispose() }
Write-Output (Join-Path $dest $expected.executable)
