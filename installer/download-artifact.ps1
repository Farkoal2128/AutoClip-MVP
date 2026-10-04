param([string]$ManifestPath, [string]$Identity, [string]$DestinationPath, [string]$CancelPath, [string]$PublisherManifestPath, [switch]$MsysInputs, [string]$ManifestSha256)
# Dot source for function use, or execute this script with all three arguments.
function Wait-InstallerDownloadTask {
    param($Task, [string]$CancelPath, [int]$TimeoutMilliseconds, $Cancellation, [string]$Phase = 'body read')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if ($CancelPath -and [IO.File]::Exists($CancelPath)) {
            $Cancellation.Cancel()
            throw 'Artifact download cancelled.'
        }
        if ($Task.Wait(100)) { return $Task.GetAwaiter().GetResult() }
        if ($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            $Cancellation.Cancel()
            throw "Artifact $Phase timed out."
        }
    }
}

function Get-InstallerDownloadResponse {
    param($Client, [uri]$Uri, [string]$CancelPath)
    $cancellation = New-Object Threading.CancellationTokenSource
    try {
        $request = $Client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancellation.Token)
        return Wait-InstallerDownloadTask $request $CancelPath 300000 $cancellation 'headers'
    } finally { $cancellation.Dispose() }
}

function Assert-InstallerDownloadPath {
    param([string]$Path)
    $cursor = $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Unsafe download path: reparse point.'
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
}

function Assert-InstallerDownloadUri {
    param([uri]$Uri, [string[]]$Hosts)
    if (-not $Uri.IsAbsoluteUri -or $Uri.Scheme -ne 'https' -or $Uri.Port -ne 443 -or
        $Uri.UserInfo -or $Uri.Fragment -or $Uri.HostNameType -ne [UriHostNameType]::Dns) {
        throw 'Unsafe download URL.'
    }
    if ($Hosts -notcontains $Uri.DnsSafeHost) { throw 'Unapproved download redirect host.' }
}

function Resolve-InstallerArtifact {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$Identity,
        [string]$PublisherManifestPath
    )
    $ErrorActionPreference = 'Stop'
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.schema_version -ne 1) { throw 'Unsupported installer dependency manifest.' }
    $matches = @($manifest.build_prerequisites | Where-Object identity -eq $Identity)
    if ($manifest.target_release.id -eq $Identity) { $matches += $manifest.target_release }
    $matches += @($manifest.external_assets | Where-Object { $_.identity -eq $Identity -or $_.filename -eq $Identity })
    $matches += @($manifest.native_build_assets | Where-Object { $_.identity -eq $Identity -or $_.filename -eq $Identity })
    $matches += @($manifest.nvidia_native_artifact | Where-Object { $_ -and ($_.identity -eq $Identity -or $_.filename -eq $Identity) })
    $matches += @($manifest.cpu_native_artifact | Where-Object { $_ -and ($_.identity -eq $Identity -or $_.filename -eq $Identity) })
    foreach ($msys in @($manifest.build_prerequisites | Where-Object identity -eq 'MSYS2')) {
        foreach ($childName in @('signature', 'installer_key')) {
            $child = $msys.$childName
            if (-not $child -or $child.filename -ne $Identity) { continue }
            if ($msys.version -cne '20260611' -or $msys.artifact_kind -cne 'archive' -or
                $msys.archive_format -cne 'tar.xz' -or $msys.filename -cne 'msys2-base-x86_64-20260611.tar.xz' -or
                ($childName -eq 'signature' -and $child.filename -cne ($msys.filename + '.sig')) -or
                ($childName -eq 'installer_key' -and ($child.filename -cne 'installer-signer.asc' -or
                    $child.fingerprint -cne '0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC'))) {
                throw 'Invalid MSYS2 base signature/key metadata.'
            }
            $classification = $child.delivery_classification
            if ($msys.delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD') { $classification = 'BLOCKED' }
            $matches += [pscustomobject]@{
                url = $child.url; bytes = $child.bytes; sha256 = $child.sha256
                delivery_classification = $classification; redirect_hosts = $child.redirect_hosts
            }
        }
        foreach ($package in @($msys.packages)) {
            $isPackage = $package.identity -eq $Identity -or $package.filename -eq $Identity
            $isSignature = $package.signature.filename -eq $Identity
            if (-not $isPackage -and -not $isSignature) { continue }
            if (-not $package.identity -or -not $package.version -or -not $package.architecture -or
                -not [regex]::IsMatch([string]$package.filename, '^[A-Za-z0-9][A-Za-z0-9._+-]*\.pkg\.tar\.zst$') -or
                $package.filename -ne ($package.identity + '-' + $package.version + '-' + $package.architecture + '.pkg.tar.zst') -or
                $package.signature.filename -ne ($package.filename + '.sig')) {
                throw 'Invalid MSYS2 package metadata.'
            }
            $artifact = $package
            if ($isSignature) { $artifact = $package.signature }
            $classification = $artifact.delivery_classification
            if ($msys.delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD' -or
                $package.delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD') { $classification = 'BLOCKED' }
            $matches += [pscustomobject]@{
                url = $artifact.url; bytes = $artifact.bytes; sha256 = $artifact.sha256
                delivery_classification = $classification; redirect_hosts = $artifact.redirect_hosts
            }
        }
    }
    if ($PublisherManifestPath) {
        $route = $manifest.publisher_wheels
        if ($route.delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD') { throw 'Publisher wheel route is unavailable.' }
        Assert-InstallerDownloadPath ([IO.Path]::GetFullPath($PublisherManifestPath))
        $publisherBytes = [IO.File]::ReadAllBytes($PublisherManifestPath)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $publisherHash = [BitConverter]::ToString($hasher.ComputeHash($publisherBytes)).Replace('-', '') }
        finally { $hasher.Dispose() }
        if ($publisherHash -ne [string]$route.sha256) { throw 'Pinned publisher manifest SHA-256 differs.' }
        $publisher = [Text.Encoding]::UTF8.GetString($publisherBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
        if ($publisher.schema_version -ne 1 -or -not $publisher.wheels) { throw 'Unsupported publisher manifest schema.' }
        foreach ($wheel in @($publisher.wheels | Where-Object filename -eq $Identity)) {
            $matches += [pscustomobject]@{
                url = $wheel.url; bytes = $wheel.bytes; sha256 = $wheel.sha256
                delivery_classification = $route.delivery_classification
                redirect_hosts = $route.redirect_hosts
            }
        }
    }
    if ($matches.Count -gt 1) { throw "Ambiguous pinned artifact identity: $Identity" }
    if ($matches.Count -ne 1 -or $matches[0].delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD') {
        throw "Pinned $Identity route is unavailable."
    }
    $pin = $matches[0]
    if ([string]$pin.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$pin.bytes -le 0 -or -not $pin.url) {
        throw 'Invalid pinned artifact identity.'
    }
    $hosts = @($pin.redirect_hosts)
    if (-not $hosts.Count -or @($hosts | Where-Object { $_ -notmatch '^[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$' }).Count) {
        throw 'Missing or invalid exact redirect host policy.'
    }
    $uri = [uri]$pin.url
    Assert-InstallerDownloadUri $uri $hosts
    return $pin
}

function Assert-InstallerArtifactDestination {
    param([string]$DestinationPath, [string]$CancelPath)
    if ($DestinationPath -notmatch '^[A-Za-z]:[\\/]') { throw 'Download destination must be absolute.' }
    $dest = [IO.Path]::GetFullPath($DestinationPath)
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    if (-not $dest.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $DestinationPath -match '(^|[\\/])\.\.?([\\/]|$)' -or $dest.Substring(3).Contains(':') -or
        [IO.Path]::GetFileName($dest) -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        throw 'Unsafe download destination: require a regular file under TEMP.'
    }
    Assert-InstallerDownloadPath $dest
    if ($CancelPath) {
        if ($CancelPath -notmatch '^[A-Za-z]:[\\/]' -or
            $CancelPath -match '(^|[\\/])\.\.?([\\/]|$)' -or
            [IO.Path]::GetFileName($CancelPath) -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { throw 'Unsafe cancellation signal path.' }
        $CancelPath = [IO.Path]::GetFullPath($CancelPath)
        if (-not $CancelPath.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $CancelPath.Substring(3).Contains(':') -or $CancelPath -eq $dest -or
            -not (Test-Path -LiteralPath (Split-Path -Parent $CancelPath) -PathType Container)) { throw 'Unsafe cancellation signal path.' }
        Assert-InstallerDownloadPath $CancelPath
        if ([IO.File]::Exists($CancelPath)) { throw 'Artifact download cancelled.' }
    }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Download destination parent is missing.' }
    return $dest
}

function Get-InstallerAvailableSpace([string]$Path) {
    return [IO.DriveInfo]::new($Path).AvailableFreeSpace
}

function Get-InstallerArtifact {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$CancelPath,
        [string]$PublisherManifestPath
    )
    $ErrorActionPreference = 'Stop'
    $pin = Resolve-InstallerArtifact -ManifestPath $ManifestPath -Identity $Identity -PublisherManifestPath $PublisherManifestPath
    $dest = Assert-InstallerArtifactDestination $DestinationPath $CancelPath
    $hosts = @($pin.redirect_hosts)
    $uri = [uri]$pin.url
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    if (Test-Path -LiteralPath $dest) {
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf) -or
            (Get-Item -LiteralPath $dest).Length -ne [long]$pin.bytes -or
            (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $pin.sha256) {
            throw 'Existing artifact size or SHA-256 differs from the pinned identity.'
        }
        return $dest
    }
    $required = [long]$pin.bytes
    try {
        $available = Get-InstallerAvailableSpace $tempRoot
        if ($available -isnot [long] -or $available -lt 0) { throw 'OS space query did not return nonnegative caller-available bytes.' }
    } catch {
        throw "Artifact transfer space at '$tempRoot': required $required bytes, available unknown; OS query failed: $($_.Exception.Message)"
    }
    if ($available -lt $required) {
        throw "Artifact transfer space at '$tempRoot': required $required bytes, available $available bytes."
    }
    $stage = Join-Path $tempRoot ('autoclip-download-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $partial = Join-Path $stage 'artifact.partial'
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $handler.UseDefaultCredentials = $false
    $client = New-Object Net.Http.HttpClient $handler
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('AutoClip-Installer/1')
    try {
        for ($hop = 0; $hop -le 5; $hop++) {
            Assert-InstallerDownloadUri $uri $hosts
            $response = Get-InstallerDownloadResponse $client $uri $CancelPath
            try {
                $status = [int]$response.StatusCode
                if ($status -in @(301, 302, 303, 307, 308)) {
                    if ($hop -eq 5) { throw 'Download redirect limit exceeded.' }
                    if (-not $response.Headers.Location) { throw 'Download redirect has no location.' }
                    $uri = New-Object uri $uri, $response.Headers.Location
                    Assert-InstallerDownloadUri $uri $hosts
                    continue
                }
                if ($status -ne 200) { throw "Artifact download failed: HTTP $status." }
                if ($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -ne [long]$pin.bytes) {
                    throw 'Artifact size or SHA-256 differs from the pinned identity.'
                }
                $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $outputStream = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $readCancellation = New-Object Threading.CancellationTokenSource
                try {
                    $buffer = New-Object byte[] 65536
                    $total = 0L
                    while ($true) {
                        $read = $inputStream.ReadAsync($buffer, 0, $buffer.Length, $readCancellation.Token)
                        $count = Wait-InstallerDownloadTask $read $CancelPath 30000 $readCancellation
                        if ($count -eq 0) { break }
                        $total += $count
                        if ($total -gt [long]$pin.bytes) { throw 'Artifact size or SHA-256 differs from the pinned identity.' }
                        $outputStream.Write($buffer, 0, $count)
                    }
                } finally { $readCancellation.Dispose(); $outputStream.Dispose(); $inputStream.Dispose() }
                if ((Get-Item -LiteralPath $partial).Length -ne [long]$pin.bytes -or
                    (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $pin.sha256) {
                    throw 'Artifact size or SHA-256 differs from the pinned identity.'
                }
                Assert-InstallerDownloadPath $dest
                [IO.File]::Move($partial, $dest)
                return $dest
            } finally { $response.Dispose() }
        }
    } finally {
        $client.Dispose()
        Assert-InstallerDownloadPath $stage
        if ([IO.File]::Exists($partial)) { [IO.File]::Delete($partial) }
        [IO.Directory]::Delete($stage)
    }
}

function Get-InstallerMsysInputs {
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ManifestSha256,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$CancelPath
    )
    $ErrorActionPreference = 'Stop'
    if ($Identity -cne 'MSYS2' -or $ManifestSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'MSYS2 batch requires exact identity and manifest SHA-256.' }
    $ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
    Assert-InstallerDownloadPath $ManifestPath
    $locked = [IO.File]::Open($ManifestPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($hasher.ComputeHash($locked)).Replace('-', '') }
        finally { $hasher.Dispose() }
        if ($hash -ne $ManifestSha256) { throw 'Pinned MSYS2 manifest SHA-256 differs.' }
        $locked.Position = 0
        $reader = [IO.StreamReader]::new($locked, [Text.Encoding]::UTF8, $true, 1024, $true)
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        $bases = @($manifest.build_prerequisites | Where-Object identity -eq 'MSYS2')
        if ($manifest.schema_version -ne 1 -or $bases.Count -ne 1) { throw 'Ambiguous or unsupported MSYS2 batch manifest.' }
        $base = $bases[0]
        if ($base.version -cne '20260611' -or $base.artifact_kind -cne 'archive' -or $base.archive_format -cne 'tar.xz' -or
            $base.filename -cne 'msys2-base-x86_64-20260611.tar.xz' -or [IO.Path]::GetFileName($DestinationPath) -cne $base.filename -or
            @($base.signature).Count -ne 1 -or @($base.installer_key).Count -ne 1 -or @($base.packages).Count -ne 5) { throw 'Invalid MSYS2 batch metadata or destination.' }
        $artifacts = @($base, $base.signature, $base.installer_key)
        $packageIdentities = @{}
        foreach ($package in $base.packages) {
            if (-not $package.identity -or $packageIdentities.ContainsKey($package.identity) -or @($package.signature).Count -ne 1) { throw 'Duplicate or invalid MSYS2 batch package.' }
            $packageIdentities[$package.identity] = $true
            $artifacts += @($package, $package.signature)
        }
        $names = @{}
        $destinations = @()
        $otherRows = @($manifest.build_prerequisites | Where-Object { $_ -ne $base }) + @($manifest.external_assets) + @($manifest.native_build_assets) + @($manifest.target_release)
        foreach ($artifact in $artifacts) {
            $allowedChildren = @()
            if ($artifact -eq $base) { $allowedChildren = @('signature', 'installer_key', 'packages') }
            elseif ($artifact.identity) { $allowedChildren = @('signature') }
            foreach ($property in $artifact.PSObject.Properties) {
                if ($allowedChildren -contains $property.Name) { continue }
                foreach ($value in @($property.Value)) {
                    if ($value -and $value.url -and $value.filename) { throw 'Invalid extra MSYS2 batch child.' }
                }
            }
            if (-not [regex]::IsMatch([string]$artifact.filename, '^[A-Za-z0-9][A-Za-z0-9._+-]*$') -or $names.ContainsKey($artifact.filename)) { throw 'Duplicate or unsafe MSYS2 batch filename.' }
            $names[$artifact.filename] = $true
            $aliases = @($artifact.identity, $artifact.filename) | Where-Object { $_ }
            if (@($otherRows | Where-Object { $_ -and ($aliases -contains $_.identity -or $aliases -contains $_.id -or $aliases -contains $_.filename) }).Count) { throw 'Ambiguous MSYS2 batch artifact identity.' }
            $selectedIdentity = $artifact.filename
            if ($artifact -eq $base) { $selectedIdentity = 'MSYS2' }
            $pin = Resolve-InstallerArtifact -ManifestPath $ManifestPath -Identity $selectedIdentity
            $destination = Assert-InstallerArtifactDestination (Join-Path (Split-Path -Parent $DestinationPath) $artifact.filename) $CancelPath
            if ((Test-Path -LiteralPath $destination) -and
                (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or (Get-Item -LiteralPath $destination).Length -ne [long]$pin.bytes -or
                    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $pin.sha256)) { throw 'Existing artifact size or SHA-256 differs from the pinned identity.' }
            $destinations += [pscustomobject]@{identity=$selectedIdentity; path=$destination}
        }
        # Keep the read/share-read lock through all ordinary single-artifact calls.
        foreach ($destination in $destinations) {
            Get-InstallerArtifact -ManifestPath $ManifestPath -Identity $destination.identity -DestinationPath $destination.path -CancelPath $CancelPath | Out-Null
        }
        return [IO.Path]::GetFullPath($DestinationPath)
    } finally { $locked.Dispose() }
}

if ($ManifestPath -or $Identity -or $DestinationPath -or $MsysInputs -or $ManifestSha256) {
    if (-not $ManifestPath -or -not $Identity -or -not $DestinationPath) { throw 'ManifestPath, Identity and DestinationPath are required together.' }
    if ($MsysInputs) {
        if ($PublisherManifestPath) { throw 'Publisher manifest is not supported for MSYS2 batch acquisition.' }
        Get-InstallerMsysInputs -ManifestPath $ManifestPath -ManifestSha256 $ManifestSha256 -Identity $Identity -DestinationPath $DestinationPath -CancelPath $CancelPath
    } else {
        if ($ManifestSha256) { throw 'ManifestSha256 requires MsysInputs.' }
        Get-InstallerArtifact -ManifestPath $ManifestPath -Identity $Identity -DestinationPath $DestinationPath -CancelPath $CancelPath -PublisherManifestPath $PublisherManifestPath
    }
}
