param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [ValidateSet('cpu', 'nvidia')][string]$Profile = 'cpu',
    [string]$ReportPath,
    [switch]$RequireReady,
    [switch]$RequireNoBlocked,
    [string]$CheckIdentity,
    [string]$MsysRoot = 'C:\msys64'
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Unsupported installer dependency manifest.' }
$platformSupported = $false
try {
    $operatingSystem = @(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop)
    $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
    $nativeBuild = 0
    $platformSupported = $operatingSystem.Count -eq 1 -and
        [string]$operatingSystem[0].ProductType -ceq '1' -and
        [regex]::IsMatch([string]$operatingSystem[0].BuildNumber, '^[0-9]+$') -and
        [int]::TryParse([string]$operatingSystem[0].BuildNumber, [ref]$nativeBuild) -and
        $nativeBuild -ge 10240 -and $processors.Count -gt 0 -and
        @($processors | Where-Object { [string]$_.Architecture -cne '9' }).Count -eq 0
} catch { $platformSupported = $false }
if (-not $platformSupported) {
    $reason = 'AutoClip setup requires native Windows 10 or 11 x64 desktop. This platform is unsupported or could not be verified.'
    if ($ReportPath) { [IO.File]::WriteAllLines($ReportPath, @($reason), [Text.Encoding]::UTF8) }
    [pscustomobject]@{
        profile = $Profile; ready = $false; blocked = $true
        missing = @([pscustomobject]@{identity = 'Windows platform'; delivery_classification = 'BLOCKED'; reason = $reason})
    } | ConvertTo-Json -Depth 8 -Compress
    exit 2
}
if ($CheckIdentity -and @($manifest.build_prerequisites | Where-Object identity -eq $CheckIdentity).Count -ne 1) {
    throw 'Requested prerequisite is absent or ambiguous.'
}

function Find-Tool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Test-BuildCapability([string]$Identity, [string]$Version, $Entry = $null, [string]$MsysRoot = 'C:\msys64') {
    try {
    switch ($Identity) {
        'uv' {
            $uv = Find-Tool 'uv.exe'
            if (-not $uv) { return $false }
            $signature = Get-AuthenticodeSignature -LiteralPath $uv
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'OpenAI OpCo, LLC') { return $false }
            $found = & $uv --version | Out-String
            return ($LASTEXITCODE -eq 0 -and $found -match ('^uv ' + [regex]::Escape($Version) + '\b'))
        }
        'Gyan FFmpeg' {
            $ffmpeg = Find-Tool 'ffmpeg.exe'; $ffprobe = Find-Tool 'ffprobe.exe'
            if (-not $ffmpeg -or -not $ffprobe) { return $false }
            $versionLine = & $ffmpeg -version | Select-Object -First 1
            $filters = & $ffmpeg -hide_banner -filters 2>&1 | Out-String
            $encoders = & $ffmpeg -hide_banner -encoders 2>&1 | Out-String
            return ($LASTEXITCODE -eq 0 -and $versionLine -match ('^ffmpeg version ' + [regex]::Escape($Version) + '\b') -and
                $filters -match '(?m)^\s*\.\.\s+ass\s' -and $encoders -match '\blibx264\b')
        }
        'Git for Windows' {
            $git = Find-Tool 'git.exe'
            if (-not $git) { return $false }
            $signature = Get-AuthenticodeSignature -LiteralPath $git
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Johannes Schindelin') { return $false }
            $version = & $git --version | Out-String
            # The winget package version is not Git's --version text; use the existing install.ps1 compatibility range.
            return ($LASTEXITCODE -eq 0 -and $version -match 'git version 2\.(4[5-9]|5[0-9])\.')
        }
        'MSYS2' {
            # Legacy metadata cannot prove the selected versions or native provenance.
            if (-not $Entry.packages -or -not $Entry.installed_files) { return $false }
            if ($MsysRoot -notmatch '^[A-Za-z]:\\[A-Za-z0-9_\\~-]+$') { return $false }
            $msysRoot = [IO.Path]::GetFullPath($MsysRoot).TrimEnd('\')
            $bash = Join-Path $msysRoot 'usr/bin/bash.exe'
            $expected = @{}
            foreach ($package in $Entry.packages) {
                if (-not [regex]::IsMatch([string]$package.identity, '^[a-z0-9][a-z0-9+._-]*$') -or
                    -not [regex]::IsMatch([string]$package.version, '^[0-9][A-Za-z0-9.+~:_-]*$') -or
                    -not [regex]::IsMatch([string]$package.architecture, '^[a-z0-9_]+$') -or
                    $package.filename -ne ($package.identity + '-' + $package.version + '-' + $package.architecture + '.pkg.tar.zst') -or
                    $expected.ContainsKey($package.identity)) { return $false }
                $expected[$package.identity] = $package.version
            }
            $provenance = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($file in $Entry.installed_files) {
                if (-not [regex]::IsMatch([string]$file.path, '^[A-Za-z0-9][A-Za-z0-9._~/-]*$') -or
                    @($file.path.Split('/') | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -or
                    -not [regex]::IsMatch([string]$file.sha256, '^[A-Fa-f0-9]{64}$') -or
                    [long]$file.bytes -le 0 -or -not $provenance.Add($file.path)) { return $false }
                $path = Join-Path $msysRoot $file.path
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
                $cursor = $path
                while ($cursor) {
                    if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
                    $cursor = Split-Path -Parent $cursor
                }
                if ((Get-Item -LiteralPath $path).Length -ne [long]$file.bytes -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { return $false }
            }
            if (-not $provenance.Contains('usr/bin/bash.exe') -or -not $provenance.Contains('usr/bin/pacman.exe')) { return $false }
            $query = '/usr/bin/pacman -Q -- ' + (($Entry.packages | ForEach-Object identity) -join ' ')
            $previousBashEnv = $env:BASH_ENV
            try {
                $env:BASH_ENV = $null
                $found = @(& $bash --noprofile --norc -c $query)
            } finally { $env:BASH_ENV = $previousBashEnv }
            if ($LASTEXITCODE -ne 0 -or $found.Count -ne $expected.Count) { return $false }
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($line in $found) {
                $fields = $line.Trim() -split '\s+'
                if ($fields.Count -ne 2 -or @($expected.Keys) -cnotcontains $fields[0] -or
                    -not $seen.Add($fields[0]) -or $fields[1] -cne $expected[$fields[0]]) { return $false }
            }
            return $true
        }
        'Visual Studio 2022 Build Tools' {
            $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
            if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { return $false }
            $vsRoot = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
            return [bool]($vsRoot -and (Test-Path -LiteralPath (Join-Path $vsRoot 'VC/Auxiliary/Build/vcvars64.bat') -PathType Leaf))
        }
        'Windows SDK' {
            $include = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Include'
            return [bool]@(Get-ChildItem -LiteralPath $include -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'um/Windows.h') -PathType Leaf }).Count
        }
        'Python' {
            if ($Version -ne '3.11.9') { return $false }
            $powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
            $pythonHelper = Join-Path $PSScriptRoot 'install-python.ps1'
            if (-not (Test-Path -LiteralPath $pythonHelper -PathType Leaf)) { return $false }
            $found = & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $pythonHelper -CheckOnly | Out-String
            return ($LASTEXITCODE -eq 0 -and [IO.Path]::IsPathRooted($found.Trim()))
        }
        'NVIDIA GPU and driver' {
            $nvidiaSmi = Find-Tool 'nvidia-smi.exe'
            if (-not $nvidiaSmi) { return $false }
            $devices = & $nvidiaSmi -L 2>&1 | Out-String
            return ($LASTEXITCODE -eq 0 -and $devices -match '(?m)^GPU [0-9]+:')
        }
        'NVIDIA CUDA Toolkit build components' {
            $root = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit/CUDA/v12.8'
            return (Test-Path -LiteralPath (Join-Path $root 'bin/nvcc.exe') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $root 'include/cuda.h') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $root 'lib/x64/cublas.lib') -PathType Leaf)
        }
    }
    return $false
    } catch {
        # A broken installed tool is missing capability, not a reason to abort inspection.
        return $false
    }
}

$publisherNative = if ($Profile -eq 'nvidia') { $manifest.nvidia_native_artifact } else { $manifest.cpu_native_artifact }
if ($publisherNative -and $publisherNative.profile -cne $Profile) { throw 'Publisher native preflight profile differs.' }
$developerTools = @('Git for Windows','MSYS2','Visual Studio 2022 Build Tools','Windows SDK','NVIDIA CUDA Toolkit build components')
$missing = @()
foreach ($item in $manifest.build_prerequisites) {
    if ($publisherNative -and $item.identity -in $developerTools) { continue }
    if ($item.profile -eq 'nvidia' -and $Profile -ne 'nvidia') { continue }
    if ($CheckIdentity -and $item.identity -ne $CheckIdentity) { continue }
    if (-not (Test-BuildCapability $item.identity $item.version $item -MsysRoot $MsysRoot)) { $missing += $item }
}
if ($Profile -eq 'nvidia' -and -not $CheckIdentity) {
    $missing += @($manifest.external_assets | Where-Object { $_.profile -eq 'nvidia' -and $_.delivery_classification -eq 'BLOCKED' })
}
$blocked = @($missing | Where-Object { $_.delivery_classification -in @('BLOCKED', 'SYSTEM_PROVIDED') }).Count -gt 0
function Format-DownloadSize($Bytes) {
    if (-not $Bytes) { return 'not recorded' }
    $mib = ([double]$Bytes / 1MB).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    return "$mib MiB ($Bytes bytes)"
}
$lines = @("AutoClip $Profile prerequisite check")
if ($manifest.target_release) {
    $lines += '', 'AutoClip'
    $lines += "  Version: $($manifest.target_release.id)"
    $lines += '  Publisher: AutoClip'
    $lines += "  Download: $(Format-DownloadSize $manifest.target_release.bytes)"
    $lines += "  Source: $($manifest.target_release.url)"
}
$additional = @($manifest.external_assets | Where-Object {
    ($_.profile -ne 'nvidia' -or $Profile -eq 'nvidia') -and $_.identity -notin @($missing.identity)
})
foreach ($group in @(@{title='Missing prerequisites';items=@($missing)}, @{title='Additional components';items=$additional})) {
    if (-not $group.items.Count) { continue }
    $lines += '', $group.title
    foreach ($item in $group.items) {
        $source = if ($item.url) { $item.url } elseif ($item.winget_id) { "winget: $($item.winget_id)" } else { 'No pinned source' }
        $lines += '', $item.identity
        $lines += "  Version: $($item.version)"
        $lines += "  Publisher: $(if ($item.publisher) { $item.publisher } elseif ($item.signature_publisher) { $item.signature_publisher } else { 'not recorded' })"
        $lines += "  Purpose: $(if ($item.purpose) { $item.purpose } else { 'not recorded' })"
        $lines += "  Download: $(Format-DownloadSize $item.bytes)"
        $lines += "  Source: $source"
        $lines += "  Elevation: $(if ($item.elevation) { $item.elevation } else { 'not recorded' })"
        $lines += "  Reboot: $(if ($item.reboot_behavior) { $item.reboot_behavior } else { 'not recorded' })"
        if ($item.delivery_classification -eq 'DIRECT_RECIPIENT_DOWNLOAD') {
            $lines += '  Setup can download this component after consent.'
        } elseif ($item.reason) { $lines += "  $($item.reason)" }
    }
}
if (-not $missing.Count) { $lines += '', 'All preflight capabilities found.' }
if ($ReportPath) { [IO.File]::WriteAllLines($ReportPath, $lines, [Text.Encoding]::UTF8) }
[pscustomobject]@{
    profile = $Profile
    ready = ($missing.Count -eq 0)
    blocked = $blocked
    missing = @($missing)
} | ConvertTo-Json -Depth 8 -Compress
if ($RequireReady -and $missing.Count) { exit 2 }
if ($RequireNoBlocked -and $blocked) { exit 2 }
if ($CheckIdentity -and $missing.Count) { exit 2 }
exit 0
