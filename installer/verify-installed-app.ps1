[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$ManifestSha256,[string]$ResultPath)
$ErrorActionPreference='Stop'
function Get-AppHealthPath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(3) -match '[;:*?"<>|\x00-\x1f]' -or @($Path.Substring(3).Split([char[]]'\/')|Where-Object { !$_ -or $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ') }).Count) {throw 'Health path must be absolute, local and free of traversal/unsafe characters.'}
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while ($cursor) {if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Health path contains a reparse point.'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
    $full
}
function Assert-AppHealthOwner([string]$Path,[switch]$Protected) {
    Get-AppHealthPath $Path|Out-Null
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$acl=Get-Acl -LiteralPath $Path
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $sid -or ($Protected -and !$acl.AreAccessRulesProtected)) {throw 'Health staging/result parent must be recipient-owned and protected.'}
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));if (!$rules.Count) {throw 'Empty health ACL rejected.'}
    foreach ($rule in $rules) {if ($rule.AccessControlType -ne 'Allow' -or $rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544') -or $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl) {throw 'Unexpected health staging write authority.'}}
}
function New-AppHealthStage {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$sid=$identity.User.Value
    $stage=Get-AppHealthPath (Join-Path ([IO.Path]::GetTempPath()) ('ach-'+[guid]::NewGuid().ToString('N')))
    if (Test-Path -LiteralPath $stage) {throw 'Health stage collision.'}
    $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetOwner($identity.User);$acl.SetAccessRuleProtection($true,$false)
    foreach ($allowed in @($sid,'S-1-5-18','S-1-5-32-544')) {$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule([Security.Principal.SecurityIdentifier]$allowed,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
    $null=[IO.Directory]::CreateDirectory($stage,$acl);Assert-AppHealthOwner $stage -Protected
    $stage
}
function Open-AppHealthManifest([string]$Path,[string]$Sha256) {
    $Path=Get-AppHealthPath $Path
    if ($Sha256 -cnotmatch '^[a-f0-9]{64}$' -or !(Test-Path -LiteralPath $Path -PathType Leaf)) {throw 'Exact release manifest pin and regular file required.'}
    $stream=[IO.File]::Open($Path,'Open','Read','Read');$hash=[Security.Cryptography.SHA256]::Create()
    try {
        $actual=([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
        if ($actual -cne $Sha256) {throw 'Installed release manifest SHA-256 differs.'}
        $stream.Position=0;$reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
        try {$manifest=$reader.ReadToEnd()|ConvertFrom-Json} finally {$reader.Dispose()}
        if ($manifest.schema_version -isnot [int] -or $manifest.schema_version -ne 3 -or $manifest.files -isnot [array]) {throw 'Expected source-build release manifest schema 3.'}
        $stream.Position=0;[pscustomobject]@{path=$Path;sha256=$actual;bytes=$stream.Length;stream=$stream}
    } catch {$stream.Dispose();throw} finally {$hash.Dispose()}
}
function Assert-AppHealthConfiguration([string]$Configuration) {
    # Same producer rules as install-runtime-toolpath.ps1; no registration side effects here.
    $identityFields=@([regex]::Matches($Configuration,'(?im)^[ \t]*(version|version_info|include-system-site-packages|implementation)[ \t]*=[ \t]*([^\r\n]*?)[ \t]*\r?$'))
    $versions=@($identityFields|Where-Object {$_.Groups[1].Value -in @('version','version_info')})
    $isolation=@($identityFields|Where-Object {$_.Groups[1].Value -ieq 'include-system-site-packages'})
    $implementation=@($identityFields|Where-Object {$_.Groups[1].Value -ieq 'implementation'})
    $duplicates=@($identityFields|Group-Object {$_.Groups[1].Value.ToLowerInvariant()}|Where-Object Count -gt 1)
    if (!$versions.Count -or $duplicates.Count -or @($versions|Where-Object {$_.Groups[2].Value -cne '3.11.9'}).Count -or $isolation.Count -ne 1 -or $isolation[0].Groups[2].Value -cne 'false' -or @($implementation|Where-Object {$_.Groups[2].Value -cne 'CPython'}).Count) {throw 'Expected unambiguous isolated CPython 3.11.9 venv metadata.'}
}
$script:AppHealthProbe=@'
import json, os, pathlib, platform, struct, sys
expected_venv, result_path = sys.argv[1:]
assert sys.version_info[:3] == (3, 11, 9), sys.version
assert platform.python_implementation() == 'CPython' and struct.calcsize('P') == 8
assert pathlib.Path(sys.prefix).resolve() == pathlib.Path(expected_venv).resolve()
assert sys.flags.isolated == 1 and sys.flags.no_user_site == 1
assert not os.environ.get('PYTHONPATH') and not os.environ.get('PYTHONHOME')
from fastapi.testclient import TestClient
import autoclip.app as app_module
with TestClient(app_module.create_app()) as client:
    health = client.get('/api/health')
    assert health.status_code == 200, f'health HTTP {health.status_code}'
    assert health.json().get('status') == 'ok', 'health status is not ok'
    home = client.get('/')
    assert home.status_code == 200, f'home HTTP {home.status_code}'
result = dict(schema_version=1, status='VERIFIED_HEALTH_HOME', health_status=health.status_code, home_status=home.status_code, python_version=platform.python_version(), python_executable=sys.executable, venv_root=sys.prefix, app_path=app_module.__file__, isolated_home=os.environ['AUTOCLIP_HOME'])
with open(result_path, 'x', encoding='utf-8') as output:
    json.dump(result, output)
'@
function Invoke-AppHealthProcess([string]$Python,[string]$ExpectedVenv,[string]$Stage) {
    $Python=Get-AppHealthPath $Python;$ExpectedVenv=Get-AppHealthPath $ExpectedVenv;$Stage=Get-AppHealthPath $Stage
    Assert-AppHealthOwner $Stage -Protected
    $isolatedHome=Join-Path $Stage 'home';$null=[IO.Directory]::CreateDirectory($isolatedHome)
    $probe=Join-Path $Stage 'probe.py';$receiptPath=Join-Path $Stage 'child-result.json'
    $stdout=Join-Path $Stage 'stdout.log';$stderr=Join-Path $Stage 'stderr.log'
    $writer=[IO.File]::Open($probe,'CreateNew','Write','None');$bytes=[Text.UTF8Encoding]::new($false).GetBytes($script:AppHealthProbe)
    try {$writer.Write($bytes,0,$bytes.Length)} finally {$writer.Dispose()}
    $probeLock=[IO.File]::Open($probe,'Open','Read','Read');$process=$null
    $keys=@('AUTOCLIP_HOME','AUTOCLIP_STORAGE_HOME','PYTHONPATH','PYTHONHOME','PYTHONNOUSERSITE');$saved=@{}
    foreach ($key in $keys) {$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
    try {
        try {
            $env:AUTOCLIP_HOME=$isolatedHome;$env:AUTOCLIP_STORAGE_HOME=$isolatedHome
            [Environment]::SetEnvironmentVariable('PYTHONPATH',$null,'Process');[Environment]::SetEnvironmentVariable('PYTHONHOME',$null,'Process');$env:PYTHONNOUSERSITE='1'
            $arguments=@('-I','-B',('"'+$probe+'"'),('"'+$ExpectedVenv+'"'),('"'+$receiptPath+'"'))
            $process=Start-Process -FilePath $Python -ArgumentList $arguments -WorkingDirectory $isolatedHome -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
            $null=$process.Handle
        } finally {foreach ($key in $keys) {[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}}
        $processRecord=[ordered]@{pid=$process.Id;start_utc=$process.StartTime.ToUniversalTime().ToString('o');python=$Python;stdout=$stdout;stderr=$stderr}
        Write-AppHealthResult (Join-Path $Stage 'process.json') $processRecord
        $process.WaitForExit();$process.Refresh()
        $processRecord.exit_code=$process.ExitCode;$processRecord.terminal_utc=[DateTime]::UtcNow.ToString('o')
        Write-AppHealthResult (Join-Path $Stage 'process-terminal.json') $processRecord
        if ($null -eq $process.ExitCode -or [int]$process.ExitCode -ne 0) {throw ('Installed app health/home child failed: '+$process.ExitCode+'; logs: '+$Stage)}
        Get-AppHealthPath $receiptPath|Out-Null
        if (!(Test-Path $receiptPath -PathType Leaf) -or (Get-Item $receiptPath).Length -gt 65536) {throw 'Bounded actual health/home child receipt missing.'}
        $receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
        if ($receipt.schema_version -ne 1 -or $receipt.status -cne 'VERIFIED_HEALTH_HOME' -or $receipt.health_status -ne 200 -or $receipt.home_status -ne 200 -or $receipt.python_version -cne '3.11.9' -or $receipt.venv_root -ine $ExpectedVenv -or $receipt.isolated_home -ine $isolatedHome) {throw 'Actual child health/home identity/status differs.'}
        [pscustomobject]@{exit_code=[int]$process.ExitCode;pid=$process.Id;receipt=$receipt;receipt_path=$receiptPath;stdout=$stdout;stderr=$stderr;stage=$Stage}
    } finally {if ($process) {if (!$process.HasExited) {$process.WaitForExit()};$process.Dispose()};$probeLock.Dispose()}
}
function Write-AppHealthResult([string]$Path,$Result) {
    $Path=Get-AppHealthPath $Path;Assert-AppHealthOwner (Split-Path -Parent $Path) -Protected
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Result|ConvertTo-Json -Depth 8 -Compress))
    $stream=[IO.File]::Open($Path,'CreateNew','Write','None');try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
}
$locks=New-Object 'System.Collections.Generic.List[System.IDisposable]';$stage=$null
$result=[ordered]@{schema_version=1;status='FAILED_PRESERVED';install_root=$InstallRoot;manifest_sha256=$ManifestSha256;isolated_health_only=$true;desktop_tested=$false;media_tested=$false;model_inference_tested=$false;error=$null}
try {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if (![Environment]::Is64BitProcess -or ![Environment]::Is64BitOperatingSystem -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {throw 'Installed health validation requires an ordinary native64 user token.'}
    $root=Get-AppHealthPath $InstallRoot
    if (!(Test-Path $root -PathType Container)) {throw 'Actual installed release directory required.'}
    $pin=Open-AppHealthManifest (Join-Path $root 'release-manifest.json') $ManifestSha256;$locks.Add($pin.stream)
    $venv=Join-Path $root '.venv';$cfg=Get-AppHealthPath (Join-Path $venv 'pyvenv.cfg');$python=Get-AppHealthPath (Join-Path $venv 'Scripts/python.exe')
    foreach ($path in @($cfg,$python)) {if (!(Test-Path -LiteralPath $path -PathType Leaf)) {throw 'Installed venv regular configuration/interpreter file missing.'};$locks.Add([IO.File]::Open($path,'Open','Read','Read'))}
    Assert-AppHealthConfiguration (Get-Content -LiteralPath $cfg -Raw)
    $signature=Get-AuthenticodeSignature -LiteralPath $python
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Python Software Foundation(,|$)') {throw 'Installed Python must have valid Python Software Foundation Authenticode.'}
    $stage=New-AppHealthStage
    if (!$ResultPath) {$ResultPath=Join-Path $stage 'result.json'}
    $ResultPath=Get-AppHealthPath $ResultPath;Assert-AppHealthOwner (Split-Path -Parent $ResultPath) -Protected
    if (Test-Path -LiteralPath $ResultPath) {throw 'Refusing to overwrite existing health result.'}
    $result.stage=$stage;$result.user_sid=$identity.User.Value;$result.install_root=$root
    $result.venv_inputs=@{configuration_sha256=(Get-FileHash -LiteralPath $cfg).Hash.ToLowerInvariant();python_sha256=(Get-FileHash -LiteralPath $python).Hash.ToLowerInvariant();python_signer=$signature.SignerCertificate.Subject}
    $actual=Invoke-AppHealthProcess $python $venv $stage
    $expectedApp=Get-AppHealthPath (Join-Path $venv 'Lib/site-packages/autoclip/app.py')
    if ($actual.receipt.app_path -ine $expectedApp -or $actual.receipt.python_executable -ine $python) {throw 'Health probe did not import the expected installed app/interpreter.'}
    $result.status='VERIFIED_HEALTH_HOME';$result.manifest_bytes=$pin.bytes;$result.child=$actual;$result.completed_at_utc=[DateTime]::UtcNow.ToString('o')
    Write-AppHealthResult $ResultPath $result
    [pscustomobject]@{status=$result.status;result_path=$ResultPath;stage=$stage}
} catch {
    $result.status='FAILED_PRESERVED'
    $result.error=$_.Exception.Message
    if ($stage) {try {Write-AppHealthResult (Join-Path $stage 'failure.json') $result} catch {Write-Warning 'Failure logs remain in the protected health stage.'}}
    throw
} finally {foreach ($lock in $locks) {$lock.Dispose()}}
