[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Install')][string]$InstallerPath,
    [Parameter(Mandatory, ParameterSetName = 'Install')][string]$ManifestPath,
    [Parameter(Mandatory, ParameterSetName = 'Install')][string]$LogDirectory,
    [Parameter(ParameterSetName = 'Install')][switch]$AcceptPythonTerms,
    [Parameter(Mandatory, ParameterSetName = 'Check')][switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'

function Assert-AutoClipPythonPath {
    param([string]$Path)
    if ($Path.Contains('"') -or -not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\')) {
        throw 'Python prerequisite paths must be absolute local paths without quotes.'
    }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Python prerequisite path contains a reparse point.'
        }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
}

function Get-AutoClipPythonTarget {
    Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311'
}

function Get-AutoClipPythonCandidates {
    foreach ($hive in @('HKCU:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
        foreach ($tag in @('3.11', '3.11-32', '3.11-64')) {
            $key = Join-Path $hive ($tag + '\InstallPath')
            if (Test-Path -LiteralPath $key) {
                $path = (Get-Item -LiteralPath $key).GetValue('')
                if (-not $path) { throw 'Existing Python registration has no install path.' }
                Join-Path $path 'python.exe'
            }
        }
    }
    $target = Get-AutoClipPythonTarget
    if (Test-Path -LiteralPath $target) { Join-Path $target 'python.exe' }
}

function Test-AutoClipPython {
    param([string]$PythonPath)
    try {
        Assert-AutoClipPythonPath $PythonPath
        if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { return $false }
        $signature = Get-AuthenticodeSignature -LiteralPath $PythonPath
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Python Software Foundation(,|$)') { return $false }
        $probe = @'
import sys, os, struct, ssl, sqlite3, bz2, lzma, ctypes, venv, ensurepip, sysconfig, pathlib
assert sys.version_info[:3] == (3, 11, 9) and struct.calcsize('P') == 8 and os.name == 'nt'
root = pathlib.Path(sys.executable).parent
assert pathlib.Path(sys.base_prefix).resolve() == root.resolve()
assert (root / 'include' / 'Python.h').is_file() and (root / 'include' / 'pyconfig.h').is_file()
assert (root / 'libs' / 'python311.lib').is_file()
assert ssl.OPENSSL_VERSION and sqlite3.connect(':memory:').execute('select 1').fetchone() == (1,)
assert bz2.decompress(bz2.compress(b'check')) == b'check' and lzma.decompress(lzma.compress(b'check')) == b'check'
print('AUTOCLIP_PYTHON_3.11.9_X64_OK')
'@
        $output = & $PythonPath -I -B -c $probe 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0 -and $output.Trim() -eq 'AUTOCLIP_PYTHON_3.11.9_X64_OK')
    } catch { return $false }
}

function Install-AutoClipPython {
    param([string]$InstallerPath, [string]$ManifestPath, [string]$LogDirectory, [switch]$AcceptPythonTerms)
    $code = 21
    $receipt = [ordered]@{
        schema_version = 1; identity = 'Python 3.11.9 x64'; timestamp_utc = [DateTime]::UtcNow.ToString('o')
        terms_url = 'https://raw.githubusercontent.com/python/cpython/v3.11.9/LICENSE'
        terms_sha256 = '3b2f81fe21d181c499c59a256c8e1968455d6689d269aa85373bfb6af41da3bf'
        recipient_terms_declared = [bool]$AcceptPythonTerms; vendor_exit_code = $null
        status = 'failed'; python_path = $null; vendor_log = $null; arguments = @()
        manifest_sha256 = $null; installer_sha256 = $null; message = $null
    }
    Assert-AutoClipPythonPath $LogDirectory
    [IO.Directory]::CreateDirectory($LogDirectory) | Out-Null
    $id = 'python-' + [guid]::NewGuid().ToString('N')
    $receiptPath = Join-Path $LogDirectory ($id + '.json')
    try {
        $code = 20
        if (-not $AcceptPythonTerms) { throw 'Explicit recipient Python 3.11.9 terms declaration required.' }
        $code = 21
        if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw 'Python setup requires Windows x64 PowerShell.' }
        Assert-AutoClipPythonPath $ManifestPath
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $receipt.manifest_sha256 = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $items = @($manifest.build_prerequisites | Where-Object identity -eq 'Python')
        if ($manifest.schema_version -ne 1 -or $items.Count -ne 1) { throw 'Unsupported Python dependency manifest.' }
        $pin = $items[0]
        if ($pin.delivery_classification -ne 'DIRECT_RECIPIENT_DOWNLOAD' -or $pin.version -ne '3.11.9' -or
            $pin.architecture -ne 'x64' -or $pin.url -ne 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe' -or
            $pin.bytes -le 0 -or $pin.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Exact Python direct-recipient pin unavailable.' }
        $code = 24
        $candidates = @(Get-AutoClipPythonCandidates | Select-Object -Unique)
        foreach ($candidate in $candidates) {
            if (Test-AutoClipPython $candidate) {
                $receipt.python_path = [IO.Path]::GetFullPath($candidate)
                $receipt.status = 'reused'; $code = 0; break
            }
        }
        if ($code -ne 0) {
            if ($candidates.Count) { throw 'Existing Python 3.11 installation requires manual resolution; it will not be modified.' }
            $target = Get-AutoClipPythonTarget
            Assert-AutoClipPythonPath $target
            if (Test-Path -LiteralPath $target) { throw 'Python target already exists.' }
            $receipt.vendor_log = Join-Path $LogDirectory ($id + '.log')
            $receipt.arguments = @('/passive', '/norestart', '/log', ('"' + $receipt.vendor_log + '"'),
                'InstallAllUsers=0', ('TargetDir="' + $target + '"'), 'PrependPath=0', 'AppendPath=0',
                'Include_exe=1', 'Include_lib=1', 'Include_dev=1', 'Include_pip=1', 'Include_launcher=0',
                'InstallLauncherAllUsers=0', 'AssociateFiles=0', 'Shortcuts=0', 'Include_doc=0', 'Include_test=0',
                'Include_tcltk=0', 'Include_tools=0', 'Include_debug=0', 'Include_symbols=0', 'CompileAll=0')
            $code = 22
            Assert-AutoClipPythonPath $InstallerPath
            if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $InstallerPath) 'unattend.xml')) {
                throw 'Adjacent unattend.xml could override fixed Python installer options.'
            }
            $installer = Get-Item -LiteralPath $InstallerPath
            $receipt.installer_sha256 = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($installer.PSIsContainer -or $installer.Length -ne [long]$pin.bytes -or $receipt.installer_sha256 -ne $pin.sha256) {
                throw 'Python installer size or SHA-256 differs from manifest.'
            }
            $code = 23
            $signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Python Software Foundation(,|$)') {
                throw 'Python installer signature or PSF publisher differs.'
            }
            $code = 25
            $process = Start-Process -FilePath ([IO.Path]::GetFullPath($InstallerPath)) -ArgumentList $receipt.arguments -Wait -PassThru -WindowStyle Hidden
            $receipt.vendor_exit_code = $process.ExitCode
            if ($process.ExitCode -eq 3010) { $code = 3010; $receipt.status = 'pending_reboot'; throw 'Restart required; reverify after reboot.' }
            if ($process.ExitCode -eq 1602 -or $process.ExitCode -eq -2147023294) { $code = 1602; $receipt.status = 'cancelled'; throw 'Python installation cancelled.' }
            if ($process.ExitCode -ne 0) { throw "Python installer failed: $($process.ExitCode)." }
            $code = 26
            $python = Join-Path $target 'python.exe'
            if (-not (Test-AutoClipPython $python)) { throw 'Python exact identity or native capability check failed.' }
            $receipt.python_path = [IO.Path]::GetFullPath($python)
            $receipt.status = 'installed'; $code = 0
        }
        $receipt.message = 'Exact Python 3.11.9 x64 capability verified.'
    } catch {
        $receipt.message = $_.Exception.Message
        if ($code -eq 20) { $receipt.status = 'declined' }
    }
    $receipt['exit_code'] = $code
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    [pscustomobject]@{ ExitCode = $code; PythonPath = $receipt.python_path; ReceiptPath = $receiptPath; Message = $receipt.message }
}

if ($PSCmdlet.ParameterSetName -eq 'Check') {
    try {
        if ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) {
            foreach ($candidate in @(Get-AutoClipPythonCandidates | Select-Object -Unique)) {
                if (Test-AutoClipPython $candidate) { Write-Output ([IO.Path]::GetFullPath($candidate)); exit 0 }
            }
        }
    } catch { }
    exit 2
}
$result = Install-AutoClipPython @PSBoundParameters
if ($result.ExitCode -eq 0) { Write-Output $result.PythonPath }
else { [Console]::Error.WriteLine($result.Message + ' Receipt: ' + $result.ReceiptPath) }
exit $result.ExitCode
