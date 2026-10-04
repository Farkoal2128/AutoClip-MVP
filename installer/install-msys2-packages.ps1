# Default is validation/plan only. Explicit execution requires the exact delivered base snapshot.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseArchivePath,
    [Parameter(Mandatory = $true)][string]$PackageDirectory,
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$MsysRoot,
    [string]$BaseReceiptPath,
    [string]$BaseReceiptSha256,
    [switch]$InstallPinnedPackages
)
$ErrorActionPreference = 'Stop'

function Assert-Msys2Transaction([string[]]$Actual, [string[]]$Expected) {
    if ($Actual.Count -ne 5 -or $Expected.Count -ne 5 -or
        @($Actual | Select-Object -Unique).Count -ne 5 -or
        @(Compare-Object $Actual $Expected -CaseSensitive).Count) {
        throw 'MSYS2 transaction contains packages or versions outside the exact five-package set.'
    }
}

function Assert-PinnedMsys2File([string]$Path, $Pin) {
    if ($Pin.delivery_classification -cne 'DIRECT_RECIPIENT_DOWNLOAD') {
        throw 'MSYS2 inputs require DIRECT_RECIPIENT_DOWNLOAD classification.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        $Pin.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [long]$Pin.bytes -le 0) {
        throw "Missing or incomplete MSYS2 file pin: $Path"
    }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'MSYS2 input path is a reparse point.'
        }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    if ((Get-Item -LiteralPath $Path).Length -ne [long]$Pin.bytes -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne [string]$Pin.sha256) {
        throw "MSYS2 file size or SHA-256 differs from the pinned manifest: $Path"
    }
}

function ConvertTo-Msys2Path([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[A-Za-z]:\\' -or $full -match '[\x00-\x1f]') { throw 'MSYS2 requires a local drive path.' }
    '/' + $full.Substring(0, 1).ToLowerInvariant() + $full.Substring(2).Replace('\', '/')
}

function Invoke-PinnedMsys2([string]$Executable, [string[]]$Arguments) {
    $output = @(& $Executable @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 native exit $LASTEXITCODE from $Executable" }
    $output
}

function Get-Msys2Elevation {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ProtectedMsys2Path([string]$Path, [switch]$RequireProtected) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'MSYS2 protected path is a reparse point.'
        }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    $acl = Get-Acl -LiteralPath $Path
    $trusted = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted -or
        ($RequireProtected -and -not $acl.AreAccessRulesProtected)) { throw 'MSYS2 path must have recipient ownership and protected DACL.' }
    $writes = 278 -bor 64 -bor 65536 -bor 262144 -bor 524288 -bor 268435456 -bor 1073741824
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if (-not $rules.Count) { throw 'MSYS2 protected path has no qualifying DACL rules.' }
    foreach ($rule in $rules) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and
            ([long]$rule.FileSystemRights -band $writes)) { throw 'MSYS2 protected path grants untrusted write access.' }
    }
}

function Get-Msys2CodePaths([switch]$PostInstall) {
    $result = @('etc/profile', 'etc/msystem', 'etc/bash.bashrc', 'msys2_shell.cmd')
    $pending = @('usr/bin', 'etc/profile.d', 'etc/post-install', 'etc/msystem.d')
    if ($PostInstall) { $pending += 'ucrt64/bin' }
    while ($pending.Count) {
        $directory = $pending[0]
        $pending = @($pending | Select-Object -Skip 1)
        Assert-ProtectedMsys2Path (Join-Path $root $directory)
        foreach ($item in Get-ChildItem -LiteralPath (Join-Path $root $directory) -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'MSYS2 code closure contains a reparse point.' }
            $name = $directory + '/' + $item.Name
            if ($item.PSIsContainer) { $pending += $name } else { $result += $name }
        }
    }
    $result
}

if ($MsysRoot -notmatch '^[A-Za-z]:\\[A-Za-z0-9_\\-]+$' -or $MsysRoot.Split('\') -contains '..') {
    throw 'MSYS2 root must be a short ASCII local path without spaces or traversal.'
}
$root = [IO.Path]::GetFullPath($MsysRoot).TrimEnd('\')
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Unsupported MSYS2 dependency manifest schema.' }
$matches = @($manifest.build_prerequisites | Where-Object identity -CEQ 'MSYS2')
if ($matches.Count -ne 1) { throw 'Exactly one MSYS2 base manifest entry is required.' }
$base = $matches[0]
if ($base.version -cne '20260611' -or $base.filename -cne 'msys2-base-x86_64-20260611.tar.xz' -or
    $base.artifact_kind -cne 'archive' -or $base.archive_format -cne 'tar.xz' -or
    [IO.Path]::GetFileName($BaseArchivePath) -cne $base.filename) { throw 'Unexpected pinned MSYS2 base identity.' }
Assert-PinnedMsys2File $BaseArchivePath $base
$expected = @(
    @('diffutils', '3.12-1', 'x86_64'), @('make', '4.4.1-3', 'x86_64'),
    @('mingw-w64-ucrt-x86_64-nasm', '3.02-1', 'any'),
    @('mingw-w64-ucrt-x86_64-zlib', '1.3.2-2', 'any'), @('pkgconf', '3.0.7-1', 'x86_64')
)
if (@($base.packages).Count -ne 5) { throw 'MSYS2 manifest must contain the exact five package records.' }
$paths = @(); $transaction = @()
foreach ($row in $expected) {
    $name, $version, $arch = $row
    $records = @($base.packages | Where-Object identity -CEQ $name)
    if ($records.Count -ne 1) { throw 'MSYS2 manifest must contain the exact five package identities.' }
    $package = $records[0]
    $filename = "$name-$version-$arch.pkg.tar.zst"
    if ($package.version -cne $version -or $package.filename -cne $filename -or
        $package.signature.filename -cne ($filename + '.sig')) { throw 'Unexpected pinned MSYS2 package identity.' }
    $path = Join-Path $PackageDirectory $filename
    Assert-PinnedMsys2File $path $package
    Assert-PinnedMsys2File ($path + '.sig') $package.signature
    $paths += ConvertTo-Msys2Path $path
    $transaction += "$name $version"
}
$msysPath = ConvertTo-Msys2Path $root
$configPath = "$msysPath/etc/autoclip-pinned-packages.conf"
$arguments = @('-U', '--config', $configPath, '--noconfirm') + $paths
$plan = [pscustomobject]@{
    execution_allowed = $false
    blocker = 'Exact installed pinned-base/keyring provenance and trusted signature verification are required for explicit execution; validation mode never installs packages.'
    executable = Join-Path $root 'usr/bin/pacman.exe'
    config_path = $configPath
    # No repositories or Include directives: missing dependencies must fail, never resolve online.
    config = "[options]`nRootDir = $msysPath/`nDBPath = $msysPath/var/lib/pacman/`nGPGDir = $msysPath/etc/pacman.d/gnupg/`nArchitecture = x86_64`nSigLevel = Required TrustedOnly`nLocalFileSigLevel = Required TrustedOnly`n"
    preview_arguments = $arguments + @('--print', '--print-format', '%n %v')
    install_arguments = $arguments
    expected_transaction = $transaction
    version_arguments = @('-Q') + @($expected | ForEach-Object { $_[0] })
    capability_checks = @(
        @{ executable = 'usr/bin/make.exe'; arguments = @('--version'); expected = '^GNU Make 4\.4\.1(?:\s|$)' },
        @{ executable = 'usr/bin/diff.exe'; arguments = @('--version'); expected = '^diff \(GNU diffutils\) 3\.12(?:\s|$)' },
        @{ executable = 'usr/bin/pkg-config.exe'; arguments = @('--version'); expected = '^3\.0\.7\s*$' },
        @{ executable = 'ucrt64/bin/nasm.exe'; arguments = @('-v'); expected = '^NASM version 3\.02(?:\s|$)' }
    )
}
if (-not $InstallPinnedPackages) { $plan; return }
if (Get-Msys2Elevation) { throw 'MSYS2 per-user package execution rejects an elevated token.' }

# These delivered-file pins come from the authenticated same-release base in IM-MS-02.
$requiredFiles = @(
    @('usr/share/pacman/keyrings/msys2.gpg',54878,'79cc43bd8b8a4e8c952340adc0ae93d3ff8e50c40f244321cf58fa014282f4ea'),
    @('usr/share/pacman/keyrings/msys2-trusted',220,'a8d39040a7b6cc14bf4394b5d9c838443925c32b00a7d34e8729c972392dca04'),
    @('usr/share/pacman/keyrings/msys2-revoked',164,'62b67ba0217745c7df189092a70d6b7a5781577f6428a5391dccd897edb5756a'),
    @('usr/bin/bash.exe',2452446,'41b09f0a9c1c68fd65253a7e8087b3775f0af245b729ade74ca4425d14392c2d'),
    @('usr/bin/pacman.exe',10765942,'209b2d527f359608cdb092515d3d99f46ac9d2209d130adced81a8cdd79057d8'),
    @('usr/bin/gpg.exe',1130330,'a5140c85353e8399da8d6bd7e3741524cd76a4e69be88af12042b1c9ef022984'),
    @('usr/bin/gpgv.exe',514306,'f4d13204d77fdf63c02b0e6742230f83a833128c28f7b715709c2c63a96c427b'),
    @('usr/bin/pacman-conf.exe',10713395,'12f4d59306fc83366a950923c9a70fa3c045fc0a6aa706e622ea30acff918726'),
    @('usr/bin/pacman-key',23497,'5d2e5e67ca59e49e84d5f0b2f7e4166e3783f707cd2292c09ce61a79c7cc149f'),
    @('etc/profile',5475,'3368d6f88af0daf8f3df1eb563e6c351bf9e336f40b826bd94486c18183602ff'),
    @('etc/post-install/07-pacman-key.post',300,'19badd8d5d7e0052028c466fc1eb7fcf8f7e1fb50cb832be389922047897ef3e'),
    @('var/lib/pacman/local/msys2-keyring-1~20260214-1/desc',342,'a72e90c5db7abb1280f295f51cc6c6d35c837d10f39d72d0379122bd9518014e')
)
function Assert-InstalledMsys2Files {
    if (@($base.installed_files).Count -ne $requiredFiles.Count) { throw "Incomplete exact installed-base provenance records: supplied $(@($base.installed_files).Count), required $($requiredFiles.Count)." }
    foreach ($row in $requiredFiles) {
        $record = @($base.installed_files | Where-Object path -CEQ $row[0])
        if ($record.Count -ne 1 -or $record[0].bytes -ne $row[1] -or $record[0].sha256 -cne $row[2]) {
            throw "Installed-base provenance differs from IM-MS-02: $($row[0])"
        }
        Assert-PinnedMsys2File (Join-Path $root $row[0]) @{
            delivery_classification = $base.delivery_classification; bytes = $row[1]; sha256 = $row[2]
        }
    }
}
Assert-InstalledMsys2Files
$manifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
function Assert-QualifiedMsys2Base {
    if ($base.sha256 -cne 'a2d047e8ee213c3c6a49a8de427eb1069df12207c0422ff1b3cbb5c905c34221' -or $base.bytes -ne 53555380 -or
        -not $BaseReceiptPath -or $BaseReceiptSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Exact TAR and qualified base receipt are required for execution.' }
    if ((Get-FileHash -LiteralPath $ManifestPath).Hash -ne $manifestHash) { throw 'MSYS2 manifest changed before native execution.' }
    Assert-ProtectedMsys2Path (Split-Path -Parent $root) -RequireProtected
    Assert-ProtectedMsys2Path $root
    Assert-ProtectedMsys2Path (Split-Path -Parent ([IO.Path]::GetFullPath($BaseReceiptPath))) -RequireProtected
    Assert-ProtectedMsys2Path $BaseReceiptPath
    if ((Get-FileHash -LiteralPath $BaseReceiptPath).Hash.ToLowerInvariant() -cne $BaseReceiptSha256) { throw 'MSYS2 base receipt SHA-256 differs.' }
    $receipt = Get-Content -LiteralPath $BaseReceiptPath -Raw | ConvertFrom-Json
    if ($receipt.schema_version -ne 1 -or $receipt.status -cne 'VERIFIED_PINNED_BASE' -or
        $receipt.root -cne $root -or $receipt.manifest_sha256 -cne $manifestHash.ToLowerInvariant() -or
        $receipt.archive_sha256 -cne $base.sha256 -or $receipt.archive_bytes -ne $base.bytes -or
        $receipt.signer_fingerprint -cne '0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC' -or
        $receipt.extraction_inventory.receipt_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $receipt.extraction_inventory.file_count -ne 15529 -or $receipt.extraction_inventory.directory_count -ne 1052) { throw 'MSYS2 base receipt identity or extraction qualification differs.' }
    foreach ($flag in @('signature_verified','init_verified','first_login_verified','protected_root_verified')) {
        if ($receipt.$flag -isnot [bool] -or -not $receipt.$flag) { throw 'MSYS2 base receipt lacks successful signature/init/login/protection qualification.' }
    }
    if ($receipt.private_home -cne (Join-Path $root 'home/autoclip-base')) { throw 'MSYS2 base receipt private HOME differs.' }
    Assert-ProtectedMsys2Path (Join-Path $root 'home')
    Assert-ProtectedMsys2Path $receipt.private_home
    $paths = @(Get-Msys2CodePaths)
    $records = @($receipt.code_files)
    if ($records.Count -ne $paths.Count -or @($records.path | Select-Object -Unique).Count -ne $paths.Count -or
        @(Compare-Object $paths @($records.path) -CaseSensitive).Count) { throw 'MSYS2 base receipt code closure is incomplete or differs.' }
    foreach ($record in $records) {
        $file = Join-Path $root $record.path
        Assert-ProtectedMsys2Path $file
        Assert-PinnedMsys2File $file @{ delivery_classification = $base.delivery_classification; bytes = $record.bytes; sha256 = $record.sha256 }
    }
    $receipt
}
$qualifiedBase = Assert-QualifiedMsys2Base
$keyParent = Join-Path $root 'etc/pacman.d'
$cursor = $keyParent
while ($cursor) {
    if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'MSYS2 keyring parent is a reparse point.'
    }
    $next = Split-Path -Parent $cursor
    if ($next -eq $cursor) { break }
    $cursor = $next
}
$identity = [guid]::NewGuid().ToString('N')
$keyDirectory = Join-Path $keyParent ('ac-' + $identity)
$gpgPath = ConvertTo-Msys2Path $keyDirectory
# MSYS UNIX sockets have 108 bytes including NUL; browser is the longest agent suffix.
if ([Text.Encoding]::UTF8.GetByteCount($gpgPath + '/S.gpg-agent.browser') + 1 -gt 108) {
    throw 'MSYS2 isolated keyring socket path exceeds 108 bytes; choose a shorter MSYS2 root.'
}
$configFile = Join-Path $root ('etc/autoclip-pinned-' + $identity + '.conf')
if (Test-Path -LiteralPath $keyDirectory) { throw 'MSYS2 keyring staging already exists.' }
[IO.Directory]::CreateDirectory($keyDirectory) | Out-Null
$configPath = ConvertTo-Msys2Path $configFile
$config = $plan.config.Replace("GPGDir = $msysPath/etc/pacman.d/gnupg/", "GPGDir = $gpgPath/")
$stream = [IO.File]::Open($configFile, [IO.FileMode]::CreateNew)
try { $bytes = [Text.Encoding]::ASCII.GetBytes($config); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
$configHash = (Get-FileHash -LiteralPath $configFile).Hash
$savedEnvironment = @{}
$environmentNames = @('PATH','BASH_ENV','ENV','GNUPGHOME','HOME','MSYSTEM','MSYS2_PATH_TYPE','SYSCONFDIR','CHERE_INVOKING','SHELLOPTS','BASHOPTS','CDPATH','GLOBIGNORE','PS1','XDG_CONFIG_HOME','ORIGINAL_PATH','CYG_SYS_BASHRC','MSYS2_PS1','MSYS2_ARG_CONV_EXCL','MSYS2_ENV_CONV_EXCL','MSYS_NO_PATHCONV')
$environmentNames += @([Environment]::GetEnvironmentVariables('Process').Keys | Where-Object { $_ -like 'BASH_FUNC_*' })
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    [Environment]::SetEnvironmentVariable('PATH', "$root\usr\bin;$root\ucrt64\bin;$env:SystemRoot\System32", 'Process')
    [Environment]::SetEnvironmentVariable('HOME', (ConvertTo-Msys2Path $qualifiedBase.private_home), 'Process')
    [Environment]::SetEnvironmentVariable('MSYS2_PATH_TYPE', 'strict', 'Process')
    [Environment]::SetEnvironmentVariable('CHERE_INVOKING', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GNUPGHOME', $gpgPath, 'Process')
    [Environment]::SetEnvironmentVariable('MSYSTEM', 'MSYS', 'Process')
    $bash = Join-Path $root 'usr/bin/bash.exe'
    $keyArguments = "/usr/bin/pacman-key --gpgdir $gpgPath --populate-from $msysPath/usr/share/pacman/keyrings"
    Invoke-PinnedMsys2 $bash @('--noprofile','--norc','-c',"$keyArguments --init") | Out-Null
    Invoke-PinnedMsys2 $bash @('--noprofile','--norc','-c',"$keyArguments --populate msys2") | Out-Null
    foreach ($path in $paths) {
        $status = @(Invoke-PinnedMsys2 (Join-Path $root 'usr/bin/gpg.exe') @('--no-options','--homedir',$gpgPath,'--batch','--no-auto-key-retrieve','--status-fd','1','--verify',($path + '.sig'),$path))
        if (-not @($status | Where-Object { $_ -match '^\[GNUPG:\] VALIDSIG 5F944B027F7FE2091985AA2EFA11531AA0AA7F57(?:\s|$)' }).Count -or
            -not @($status | Where-Object { $_ -match '^\[GNUPG:\] TRUST_(FULLY|ULTIMATE)(?:\s|$)' }).Count -or
            @($status | Where-Object { $_ -match '^\[GNUPG:\] (BADSIG|ERRSIG|REVKEYSIG|EXPKEYSIG|EXPSIG)(?:\s|$)' }).Count) {
            throw 'MSYS2 package signature must be valid and trusted for the pinned developer.'
        }
    }
    $pacman = $plan.executable
    $before = @(Invoke-PinnedMsys2 $pacman @('--config',$configPath,'-Q'))
    if ($before -cnotcontains 'msys2-keyring 1~20260214-1' -or
        @($before | Where-Object { $_ -notmatch '^\S+ \S+$' }).Count) { throw 'Installed MSYS2 keyring version or package snapshot differs.' }
    $install = @('-U','--config',$configPath,'--noconfirm') + $paths
    $preview = @(Invoke-PinnedMsys2 $pacman ($install + @('--print','--print-format','%n %v')))
    Assert-Msys2Transaction $preview $transaction
    Assert-InstalledMsys2Files
    $qualifiedBase = Assert-QualifiedMsys2Base
    Assert-PinnedMsys2File $BaseArchivePath $base
    foreach ($package in $base.packages) {
        $path = Join-Path $PackageDirectory $package.filename
        Assert-PinnedMsys2File $path $package
        Assert-PinnedMsys2File ($path + '.sig') $package.signature
    }
    if ((Get-FileHash -LiteralPath $ManifestPath).Hash -ne $manifestHash -or (Get-FileHash -LiteralPath $configFile).Hash -ne $configHash) {
        throw 'Pinned MSYS2 manifest or trusted configuration changed before installation.'
    }
    Invoke-PinnedMsys2 $pacman $install | Out-Null
    Assert-InstalledMsys2Files
    $versions = @(Invoke-PinnedMsys2 $pacman (@('--config',$configPath) + $plan.version_arguments))
    Assert-Msys2Transaction $versions $transaction
    $after = @(Invoke-PinnedMsys2 $pacman @('--config',$configPath,'-Q'))
    $names = @($expected | ForEach-Object { $_[0] })
    $beforeExtra = @($before | Where-Object { ($_ -split ' ')[0] -cnotin $names })
    $afterExtra = @($after | Where-Object { ($_ -split ' ')[0] -cnotin $names })
    if (@($after | Where-Object { $_ -notmatch '^\S+ \S+$' }).Count -or
        @(Compare-Object $beforeExtra $afterExtra -CaseSensitive).Count) { throw 'MSYS2 installation changed unrelated package versions.' }
    foreach ($check in $plan.capability_checks) {
        $output = @(Invoke-PinnedMsys2 (Join-Path $root $check.executable) $check.arguments) -join "`n"
        if ($output -notmatch $check.expected) { throw "MSYS2 capability version differs: $($check.executable)" }
    }
    if ((Get-FileHash -LiteralPath $ManifestPath).Hash -ne $manifestHash -or
        (Get-FileHash -LiteralPath $BaseReceiptPath).Hash.ToLowerInvariant() -cne $BaseReceiptSha256) {
        throw 'Pinned MSYS2 manifest or base receipt changed before package snapshot.'
    }
    # Packages may legitimately add or replace code; snapshot the verified installed state.
    $postCodeFiles = @(foreach ($relative in Get-Msys2CodePaths -PostInstall) {
        $file = Join-Path $root $relative
        Assert-ProtectedMsys2Path $file
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'MSYS2 post-install code path is not a regular file.' }
        [pscustomobject]@{ path = $relative; bytes = (Get-Item -LiteralPath $file).Length;
            sha256 = (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() }
    })
    [pscustomobject]@{ schema_version = 1; status = 'VERIFIED_PINNED_PACKAGES'; root = $root; keyring_directory = $keyDirectory;
        config_path = $configFile; manifest_sha256 = $manifestHash.ToLowerInvariant(); base_receipt_sha256 = $BaseReceiptSha256;
        private_home = $qualifiedBase.private_home; post_install_code_files = $postCodeFiles; packages = $transaction }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
