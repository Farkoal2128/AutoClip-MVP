#ifndef ReleaseUrl
  #error ReleaseUrl is required
#endif
#ifndef ReleaseSha256
  #error ReleaseSha256 is required
#endif
#ifndef ReleaseManifestSha256
  #error ReleaseManifestSha256 is required
#endif
#ifndef ReleaseId
  #error ReleaseId is required
#endif
#ifndef DependencyManifestSha256
  #error DependencyManifestSha256 is required
#endif
#ifndef BootstrapScriptPath
  #error BootstrapScriptPath is required
#endif
#ifndef DependencyManifestPath
  #error DependencyManifestPath is required
#endif
#ifndef MinGitUrl
  #error MinGitUrl is required
#endif
#ifndef MinGitSha256
  #error MinGitSha256 is required
#endif
#ifndef UvUrl
  #error UvUrl is required
#endif
#ifndef UvSha256
  #error UvSha256 is required
#endif
#ifndef BootstrapSha256
  #error BootstrapSha256 is required
#endif
#ifndef SourceBuildHelperSha256
  #error SourceBuildHelperSha256 is required
#endif
#ifndef AppHealthHelperSha256
  #error AppHealthHelperSha256 is required
#endif
#ifndef SetupReceiptHelperSha256
  #error SetupReceiptHelperSha256 is required
#endif
#ifndef SetupNoticeRows
  #error SetupNoticeRows is required
#endif
#ifndef SetupHelperRows
  #error SetupHelperRows is required
#endif
#ifndef UninstallHelperSha256
  #error UninstallHelperSha256 is required
#endif
#ifndef RemovalHelperSha256
  #error RemovalHelperSha256 is required
#endif
#ifndef UpdaterSha256
  #error UpdaterSha256 is required
#endif
#ifndef PreflightSha256
  #error PreflightSha256 is required
#endif
#ifndef ToolArchiveHelperSha256
  #error ToolArchiveHelperSha256 is required
#endif
#ifndef SecureDownloaderSha256
  #error SecureDownloaderSha256 is required
#endif
#ifndef PythonHelperSha256
  #error PythonHelperSha256 is required
#endif
#ifndef MsysBaseHelperSha256
  #error MsysBaseHelperSha256 is required
#endif
#ifndef MsysExtractorSha256
  #error MsysExtractorSha256 is required
#endif
#ifndef MsysPackagesHelperSha256
  #error MsysPackagesHelperSha256 is required
#endif
#ifndef MsysArchiveSha256
  #error MsysArchiveSha256 is required
#endif
#ifndef PythonSha256
  #error PythonSha256 is required
#endif
#ifndef PythonTermsUrl
  #error PythonTermsUrl is required
#endif
#ifndef RuntimeToolPathHelperSha256
  #error RuntimeToolPathHelperSha256 is required
#endif
#ifndef FfmpegSha256
  #error FfmpegSha256 is required
#endif
#ifndef NativeCpuEnabled
  #define NativeCpuEnabled 0
#endif
#ifndef NativeNvidiaEnabled
  #define NativeNvidiaEnabled 0
#endif

[Setup]
SetupLogging=yes
AppId={{D7451842-48F4-487B-80E0-5C7E9E326342}
AppName=AutoClip
AppVersion=1.0.0
DefaultDirName={localappdata}\AutoClip\Setup
DefaultGroupName=AutoClip
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
SetupArchitecture=x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
WizardStyle=modern dynamic
DisableDirPage=yes
UsePreviousAppDir=no
OutputBaseFilename=AutoClip-Setup-v1
UninstallDisplayName=AutoClip Setup
Uninstallable=IsInstallMode

[Files]
Source: "{#BootstrapScriptPath}"; DestDir: "{app}"; DestName: "install.ps1"; Flags: ignoreversion; Check: IsInstallMode
Source: "{#DependencyManifestPath}"; DestDir: "{app}"; DestName: "installer-dependencies-v1.json"; Flags: ignoreversion; Check: IsInstallMode
Source: "preflight.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "install-tool-archive.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "download-artifact.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "install-python.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
#if Int(NativeCpuEnabled) || Int(NativeNvidiaEnabled)
Source: "install-cpu-native-artifact.py"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "install-vc-runtime.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
#endif
Source: "install-msys2-base.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "extract-msys2-base.py"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "install-msys2-packages.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "install-runtime-toolpath.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "run-source-build.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "verify-installed-app.ps1"; DestDir: "{app}"; Flags: ignoreversion dontcopy
Source: "write-setup-receipt.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "uninstall-owned-release.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "remove-owned-file.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "..\update.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "..\update-app.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "initialize-selection.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "run-maintenance.ps1"; DestDir: "{app}"; Flags: ignoreversion; Check: IsInstallMode
Source: "{srcexe}"; DestDir: "{app}"; DestName: "AutoClip-Maintenance.exe"; Flags: external ignoreversion; Check: IsInstallMode
Source: "..\release\notices\inno-setup-7.1.0-LICENSE.txt"; DestDir: "{app}\notices"; Flags: ignoreversion uninsneveruninstall; Check: IsInstallMode
Source: "..\release\notices\uv-0.12.19-LICENSE-MIT.txt"; DestDir: "{app}\notices"; Flags: ignoreversion uninsneveruninstall; Check: IsInstallMode
Source: "..\release\notices\uv-0.12.19-LICENSE-APACHE.txt"; DestDir: "{app}\notices"; Flags: ignoreversion uninsneveruninstall; Check: IsInstallMode
Source: "..\release\notices\setup-tool-sources.md"; DestDir: "{app}\notices"; Flags: ignoreversion uninsneveruninstall; Check: IsInstallMode

[Icons]
Name: "{group}\AutoClip"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{localappdata}\AutoClip\Start-AutoClip-Desktop.ps1"""; WorkingDir: "{localappdata}\AutoClip"; Flags: uninsneveruninstall; Check: IsInstallMode
Name: "{group}\AutoClip Maintenance"; Filename: "{app}\AutoClip-Maintenance.exe"; WorkingDir: "{app}"; Flags: uninsneveruninstall; Check: IsInstallMode

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{localappdata}\AutoClip\Start-AutoClip-Desktop.ps1"""; WorkingDir: "{localappdata}\AutoClip"; Description: "Launch AutoClip"; Flags: postinstall nowait skipifsilent; Check: CanLaunchAutoClip


[Code]
function SetTimer(hWnd: HWND; nIDEvent: UINT_PTR; uElapse: UINT; lpTimerFunc: NativeInt): UINT_PTR;
external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd: HWND; nIDEvent: UINT_PTR): BOOL;
external 'KillTimer@user32.dll stdcall';

var
  ProfilePage: TInputOptionWizardPage;
  SummaryPage: TWizardPage;
  ConsentPage: TInputOptionWizardPage;
  NvidiaConsentPage: TInputOptionWizardPage;
  VcConsentStatus: Integer;
  PythonConsentPage: TInputOptionWizardPage;
  MsysConsentPage: TInputOptionWizardPage;
  SummaryText: TMemo;
  DownloadPage: TOutputMarqueeProgressWizardPage;
  StopDownloadButton: TNewButton;
  DownloadCancelPath: String;
  DownloadCancelled: Boolean;
  BuildActive: Boolean;
  BuildAttemptIndex: Integer;
  BuildAttemptDirectory: String;
  BuildOutput: TMemo;
  BuildRequestCommand: String;
  BuildCancelPending: Boolean;
  BuildCancellationClosed: Boolean;
  HiddenWorkerTimer: UINT_PTR;
  HiddenWorkerDepth: Integer;
  HiddenWorkerTickBusy: Boolean;
  HiddenWorkerDisplayError: String;
  PreflightReady: Boolean;
  SetupReceiptComplete: Boolean;
  UninstallCleanRemoval, UninstallPreserved: Boolean;
  SetupReceiptError, SourceHandoffSha256: String;
  GitPrepared: Boolean;
  UvPrepared: Boolean;
  PythonRestartPending: Boolean;
  MsysPrepared: Boolean;
  MsysRoot, MsysBaseReceiptPath, MsysPackageReceiptPath, MsysPackageReceiptSha256: String;
  SetupSelectionHandle, SetupSelectionThread: Cardinal;
  SetupSelectionProofStream, SetupSelectionEngineStream, SetupSelectionSourceStream: TFileStream;
  SetupSelectionPath, SetupSelectionHash: String;

function SetupNativePid: Cardinal; external 'GetCurrentProcessId@kernel32.dll stdcall';
function SetupNativeThread: Cardinal; external 'GetCurrentThreadId@kernel32.dll stdcall';
function SetupNativeModule(Module: Cardinal; Buffer: String; Size: Cardinal): Cardinal; external 'GetModuleFileNameW@kernel32.dll stdcall';
function SetupSelectionWait(Handle, Milliseconds: Cardinal): Cardinal; external 'WaitForSingleObject@kernel32.dll stdcall';
function SetupSelectionRelease(Handle: Cardinal): Boolean; external 'ReleaseMutex@kernel32.dll stdcall';
function SetupSelectionClose(Handle: Cardinal): Boolean; external 'CloseHandle@kernel32.dll stdcall';

procedure HiddenWorkerTick(A: HWND; B: UINT; C: UINT_PTR; D: DWORD);
var Lines: TArrayOfString;
begin
  if (HiddenWorkerDepth = 0) or HiddenWorkerTickBusy then Exit;
  HiddenWorkerTickBusy := True;
  try
    try
      if DownloadPage <> nil then DownloadPage.Animate;
      if BuildActive and (HiddenWorkerDisplayError = '') then
        if LoadStringsFromFile(BuildAttemptDirectory + '\tail.txt', Lines) then
          BuildOutput.Lines.Text := StringJoin(#13#10, Lines);
    except
      { Never unwind the native wait while its original worker is alive. }
      if HiddenWorkerDisplayError = '' then HiddenWorkerDisplayError := GetExceptionMessage;
    end;
  finally
    HiddenWorkerTickBusy := False;
  end;
end;

function ExecHiddenWorker(Command: String; var Code: Integer; var Output, Errors: String): Boolean;
var Captured: TExecOutput;
begin
  if HiddenWorkerDepth = 0 then begin
    HiddenWorkerDisplayError := '';
    HiddenWorkerTimer := SetTimer(0, 0, 100, CreateCallback(@HiddenWorkerTick));
    if HiddenWorkerTimer = 0 then RaiseException('Could not start native worker progress timer.');
  end;
  HiddenWorkerDepth := HiddenWorkerDepth + 1;
  try
    { Inno creates no console and owns the original process until terminal state.
      Its wait pumps messages even when the worker produces no output. }
    Result := ExecAndCaptureOutputWithNativeSysDir('>', Command, '', SW_HIDE,
      ewWaitUntilTerminated, Code, Captured);
    Output := StringJoin(#13#10, Captured.StdOut);
    Errors := StringJoin(#13#10, Captured.StdErr);
    if Captured.Error then Result := False;
  finally
    HiddenWorkerDepth := HiddenWorkerDepth - 1;
    if HiddenWorkerDepth = 0 then begin
      KillTimer(0, HiddenWorkerTimer);
      HiddenWorkerTimer := 0;
    end;
  end;
end;

function UsePublisherCpu: Boolean;
begin
  Result := ({#NativeCpuEnabled} = 1) and ProfilePage.Values[0];
#ifdef NativeNvidiaEnabled
#if NativeNvidiaEnabled
  Result := Result or ProfilePage.Values[1];
#endif
#endif
end;

procedure VerifyHelper(Name, ExpectedHash: String);
begin
  ExtractTemporaryFile(Name);
  if CompareText(GetSHA256OfFile(ExpandConstant('{tmp}\') + Name), ExpectedHash) <> 0 then
    RaiseException('Installer helper hash differs: ' + Name);
end;

procedure OpenMicrosoftTerms(Sender: TObject);
var Code: Integer;
begin
  ShellExec('open', 'https://visualstudio.microsoft.com/license-terms/vs2022-cruntime/', '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

procedure OpenPythonTerms(Sender: TObject);
var Code: Integer;
begin
  ShellExec('open', '{#PythonTermsUrl}', '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

procedure OpenMsysLicenses(Sender: TObject);
var Code: Integer;
begin
  ShellExec('open', 'https://www.msys2.org/license/', '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

procedure OpenNvidiaTerms(Sender: TObject);
var Code: Integer;
begin
  ShellExec('open', 'https://docs.nvidia.com/cuda/archive/12.8.0/eula/index.html', '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

procedure OpenCublasTerms(Sender: TObject);
var Code: Integer;
    TermsFile: String;
begin
  VerifyHelper('install.ps1', '{#BootstrapSha256}');
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -File ' + AddQuotes(ExpandConstant('{tmp}\install.ps1')) +
    ' -ShowCublasTerms -TermsRoot ' + AddQuotes(ExpandConstant('{tmp}')),
    '', SW_HIDE, ewWaitUntilTerminated, Code, nil) or (Code <> 0) then begin
    MsgBox('Exact cuBLAS terms could not be opened.', mbError, MB_OK);
    Exit;
  end;
  TermsFile := ExpandConstant('{tmp}\terms\cublas-ad6f5853fba0ca0d159d0f58d49ae49830c2f8c93f7a92648b9ce90adb4c6ccd.txt');
  if not FileExists(TermsFile) or
     (CompareText(GetSHA256OfFile(TermsFile), 'ad6f5853fba0ca0d159d0f58d49ae49830c2f8c93f7a92648b9ce90adb4c6ccd') <> 0) then begin
    MsgBox('Exact cuBLAS terms hash differs.', mbError, MB_OK);
    Exit;
  end;
  ShellExec('open', TermsFile, '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

function ReleaseRoot: String;
begin
  Result := ExpandConstant('{localappdata}\AutoClip\{#ReleaseId}');
end;

function AuditRequested: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/AUDIT') = 0 then Result := True;
end;

function ProfileName: String;
begin
  if ProfilePage.Values[1] then Result := 'nvidia' else Result := 'cpu';
end;

function MsysPowerShellQuote(Value: String): String;
begin
  StringChangeEx(Value, '''', '''''', True);
  Result := '''' + Value + '''';
end;

function MsysSummary: String;
var Command, Report: String;
    Lines: TArrayOfString;
    Code: Integer;
begin
  Result := 'Private MSYS2 prerequisite summary could not be authenticated. Setup cannot continue.';
  Report := ExpandConstant('{tmp}\msys-summary.txt');
  Command := '$ErrorActionPreference=''Stop''; $f=$null; try { $m=' + MsysPowerShellQuote(ExpandConstant('{tmp}\installer-dependencies-v1.json')) + '; ' +
    '$f=[IO.File]::Open($m,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne ''{#DependencyManifestSha256}''){throw ''Manifest pin changed.''}; ' +
    '$rows=@((Get-Content -LiteralPath $m -Raw|ConvertFrom-Json).build_prerequisites|Where-Object{$_.identity -ceq ''MSYS2''}); if($rows.Count -ne 1 -or $rows[0].sha256 -cne ''{#MsysArchiveSha256}''){throw ''MSYS2 summary identity differs.''}; $r=$rows[0]; ' +
    '$lines=@(''Private MSYS2 build environment: ''+$r.version+'' x64'',''Publisher: ''+$r.publisher,''Purpose: ''+$r.purpose,''Classification: ''+$r.delivery_classification,''Official component licenses: https://www.msys2.org/license/'',''No elevation or restart; separate protected per-user root. Existing system MSYS2 is preserved.''); ' +
    '$inputs=@($r,$r.signature,$r.installer_key); foreach($p in $r.packages){$inputs+=@($p,$p.signature)}; foreach($p in $inputs){if([long]$p.bytes -le 0 -or -not $p.url){throw ''Unknown MSYS2 acquisition size/source.''};$lines+=(''Source: ''+$p.url+''; bytes: ''+$p.bytes+''; file: ''+$p.filename)}; ' +
    '[IO.File]::WriteAllLines(' + MsysPowerShellQuote(Report) + ',$lines); exit 0 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 } finally {if($f){$f.Dispose()}}';
  if ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command), '', SW_HIDE, ewWaitUntilTerminated, Code, nil) and (Code = 0) then begin
    if LoadStringsFromFile(Report, Lines) then Result := StringJoin(#13#10, Lines) else PreflightReady := False;
  end else PreflightReady := False;
end;

function RunPreflight: Boolean;
var
  Code: Integer;
  Report: String;
  Params: String;
  Lines: TArrayOfString;
begin
  VerifyHelper('preflight.ps1', '{#PreflightSha256}');
  VerifyHelper('install-python.ps1', '{#PythonHelperSha256}');
  Report := ExpandConstant('{tmp}\autoclip-preflight.txt');
  if CompareText(GetSHA256OfFile(ExpandConstant('{tmp}\installer-dependencies-v1.json')),
    '{#DependencyManifestSha256}') <> 0 then begin
    SummaryText.Text := 'Embedded dependency manifest hash differs. Setup cannot continue.';
    Result := False;
    PreflightReady := False;
    Exit;
  end;
  Params := '-NoProfile -ExecutionPolicy Bypass -File ' + AddQuotes(ExpandConstant('{tmp}\preflight.ps1')) +
    ' -ManifestPath ' + AddQuotes(ExpandConstant('{tmp}\installer-dependencies-v1.json')) +
    ' -Profile ' + ProfileName + ' -ReportPath ' + AddQuotes(Report) + ' -RequireNoBlocked';
  Result := ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) and (Code = 0);
  if LoadStringsFromFile(Report, Lines) then
    SummaryText.Text := StringJoin(#13#10, Lines)
  else
    SummaryText.Text := 'Prerequisite inspection failed. Setup cannot continue.';
  PreflightReady := Result;
end;

function ToolAvailable(Identity: String): Boolean;
var Code: Integer;
begin
  Result := ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -File ' + AddQuotes(ExpandConstant('{tmp}\preflight.ps1')) +
    ' -ManifestPath ' + AddQuotes(ExpandConstant('{tmp}\installer-dependencies-v1.json')) +
    ' -CheckIdentity ' + AddQuotes(Identity), '', SW_HIDE, ewWaitUntilTerminated, Code, nil) and (Code = 0);
end;

function InstallToolArchive(Identity, ArchiveName, Destination: String): Boolean;
var Code: Integer;
    Params: String;
begin
  VerifyHelper('install-tool-archive.ps1', '{#ToolArchiveHelperSha256}');
  Params := '-NoProfile -ExecutionPolicy Bypass -File ' + AddQuotes(ExpandConstant('{tmp}\install-tool-archive.ps1')) +
    ' -Identity ' + AddQuotes(Identity) +
    ' -ArchivePath ' + AddQuotes(ExpandConstant('{tmp}\' + ArchiveName)) +
    ' -ManifestPath ' + AddQuotes(ExpandConstant('{tmp}\installer-dependencies-v1.json')) +
    ' -DestinationRoot ' + AddQuotes(Destination);
  Result := ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '',
    SW_HIDE, ewWaitUntilTerminated, Code, nil) and (Code = 0);
end;

function PythonStatePath: String;
begin
  Result := ExpandConstant('{localappdata}\AutoClip\Setup\python-reboot-pending.txt');
end;

function PythonLogDirectory: String;
begin
  Result := ExpandConstant('{localappdata}\AutoClip\PythonSetupLogs');
end;

function PythonRebootStatus(MarkPending: Boolean): Integer;
var
  StatePath, LogDirectory, Command, Params, Mark: String;
  Code: Integer;
begin
  StatePath := PythonStatePath;
  StringChangeEx(StatePath, '''', '''''', True);
  LogDirectory := PythonLogDirectory;
  StringChangeEx(LogDirectory, '''', '''''', True);
  if MarkPending then Mark := '$true' else Mark := '$false';
  Command := '$ErrorActionPreference = ''Stop''; try { $p = ''' + StatePath + '''; $logs = ''' + LogDirectory + '''; $mark = ' + Mark + '; ' +
    '$c = [IO.Path]::GetFullPath($p); while ($c) { if (Test-Path -LiteralPath $c) { if ((Get-Item -LiteralPath $c -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ''Reparse reboot state path.'' } }; $n = Split-Path -Parent $c; if ($n -eq $c) { break }; $c = $n }; ' +
    '$pending = @(); if (-not $mark -and -not (Test-Path -LiteralPath $p)) { if (Test-Path -LiteralPath $logs) { if ((Get-Item -LiteralPath $logs -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ''Reparse Python receipt directory.'' }; foreach ($r in (Get-ChildItem -LiteralPath $logs -Filter ''python-*.json'' -File)) { if ($r.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ''Reparse Python receipt.'' }; $j = Get-Content -LiteralPath $r.FullName -Raw | ConvertFrom-Json; if ($j.schema_version -eq 1 -and $j.identity -eq ''Python 3.11.9 x64'' -and $j.status -eq ''pending_reboot'' -and $j.vendor_exit_code -eq 3010) { $pending += ([datetime]$j.timestamp_utc).ToUniversalTime().Ticks } } }; if (-not $pending.Count) { exit 0 } }; ' +
    '$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().Ticks.ToString(); ' +
    '$prefix = ''AUTOCLIP_PYTHON_3.11.9_REBOOT_V1|{#PythonHelperSha256}|''; ' +
    'if (@($pending | Where-Object { $_ -ge [long]$boot }).Count) { exit 3010 }; ' +
    'if (Test-Path -LiteralPath $p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ''Foreign reboot state.'' }; $old = [IO.File]::ReadAllText($p); if ($old -notmatch (''^'' + [regex]::Escape($prefix) + ''[0-9]{18}$'')) { throw ''Foreign reboot state.'' }; if ($old -eq ($prefix + $boot)) { exit 3010 }; if ($mark) { throw ''Conflicting reboot state.'' }; [IO.File]::Delete($p); exit 0 }; ' +
    'if ($mark) { $dir = Split-Path -Parent $p; [IO.Directory]::CreateDirectory($dir) | Out-Null; $t = Join-Path $dir (''.python-reboot-'' + [guid]::NewGuid().ToString(''N'') + ''.tmp''); $b = [Text.Encoding]::ASCII.GetBytes($prefix + $boot); $f = [IO.File]::Open($t, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); try { $f.Write($b, 0, $b.Length); $f.Flush($true) } finally { $f.Dispose() }; try { [IO.File]::Move($t, $p) } finally { if ([IO.File]::Exists($t)) { [IO.File]::Delete($t) } }; exit 3010 }; exit 0 ' +
    '} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 }';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) then
    Result := 2
  else Result := Code;
end;

function PublisherVcConsentStatus: Integer;
var Command, Params: String;
    Code: Integer;
begin
  Result := 23;
#if Int(NativeCpuEnabled) || Int(NativeNvidiaEnabled)
  VerifyHelper('install-vc-runtime.ps1', '{#VcRuntimeHelperSha256}');
  Command := '$ErrorActionPreference=''Stop''; $locks=@(); try { ' +
    '$m=' + MsysPowerShellQuote(ExpandConstant('{tmp}\installer-dependencies-v1.json')) + '; ' +
    '$h=' + MsysPowerShellQuote(ExpandConstant('{tmp}\install-vc-runtime.ps1')) + '; ' +
    'function Pin($p,$hash) { $c=[IO.Path]::GetFullPath($p); while($c) { if((Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ''Reparse capability input''}; $n=Split-Path -Parent $c;if($n -eq $c){break};$c=$n }; ' +
    'if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ''Missing capability input''};$script:locks+=,[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $hash){throw ''Changed capability input''} }; ' +
    'Pin $m ''{#DependencyManifestSha256}''; Pin $h ''{#VcRuntimeHelperSha256}''; ' +
    '$ps=Join-Path $env:SystemRoot ''System32\WindowsPowerShell\v1.0\powershell.exe''; ' +
    '$lines=@(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $h -CheckOnly -ManifestPath $m -ManifestSha256 ''{#DependencyManifestSha256}'' -StateDirectory ' +
    MsysPowerShellQuote(ExpandConstant('{localappdata}\AutoClip\publisher-cache\vc-runtime')) + '); $code=$LASTEXITCODE; ' +
    'if($lines.Count -ne 1){throw ''Invalid capability framing''};$r=$lines[0]|ConvertFrom-Json; ' +
    'if($r.schema_version -isnot [int] -or $r.schema_version -ne 1 -or $r.exit_code -isnot [int] -or $r.exit_code -ne $code){throw ''Invalid capability result''}; ' +
    'if($code -eq 0 -and $r.status -ceq ''ready''){exit 0};if($code -eq 2 -and $r.status -ceq ''missing''){exit 2}; ' +
    'if($code -eq 3010 -and $r.status -ceq ''pending_reboot''){exit 3010};throw ''Unresolved capability state'' ' +
    '} catch { [Console]::Error.WriteLine($_.Exception.Message);exit 23 } finally {foreach($f in $locks){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) then
    Result := Code;
#endif
end;

#include "unified-maintenance.iss"

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  if not IsInstallMode then begin Result := (PageID <> wpWelcome) and (PageID <> ActionPage.ID) and (PageID <> wpFinished); Exit; end;
  if (PageID = NvidiaConsentPage.ID) and ProfilePage.Values[0] then begin Result := True; Exit; end;
#ifdef NativeCpuEnabled
#if Int(NativeCpuEnabled) || Int(NativeNvidiaEnabled)
  if (PageID = MsysConsentPage.ID) and UsePublisherCpu then begin Result := True; Exit; end;
  if (PageID = ConsentPage.ID) and UsePublisherCpu and (VcConsentStatus = 0) then begin Result := True; Exit; end;
#endif
#endif
  Result := (PageID = PythonConsentPage.ID) and ToolAvailable('Python');
end;

procedure StopDownload(Sender: TObject);
var Code: Integer;
    Output, Errors: String;
begin
  if BuildActive then begin
    if BuildCancelPending or DownloadCancelled or BuildCancellationClosed then Exit;
    try
      BuildCancelPending := True;
      StopDownloadButton.Enabled := False;
      DownloadPage.SetText('Requesting cancellation', 'Checking whether installation completion has already begun.');
      Log('Recipient requested build cancellation; acceptance is pending.');
      if not ExecHiddenWorker(BuildRequestCommand + ' -RequestCancellation', Code, Output, Errors) then Code := -1;
      Log(Output); Log(Errors);
      BuildCancelPending := False;
      Log('Build cancellation request exit: ' + IntToStr(Code));
      if Code = 0 then begin
        DownloadCancelled := True;
        WizardForm.CancelButton.Enabled := False;
        DownloadPage.SetText('Cancellation accepted', 'Waiting for the running build invocation to finish. This installation will not be activated.');
      end else if Code = 170 then begin
        BuildCancellationClosed := True;
        WizardForm.CancelButton.Enabled := False;
        DownloadPage.SetText('Finishing installation', 'Completion has already begun; it is too late to cancel.');
      end else begin
        StopDownloadButton.Enabled := True;
        MsgBox('Cancellation was not accepted. Setup is still observing the current build. Request exit: ' + IntToStr(Code), mbError, MB_OK);
      end;
    except
      BuildCancelPending := False;
      Log('Build cancellation request could not start: ' + GetExceptionMessage);
      MsgBox('Cancellation could not be requested. Setup is still observing the current build.', mbError, MB_OK);
    end;
    Exit;
  end;
  if SaveStringToFile(DownloadCancelPath, 'cancel', False) then begin
    DownloadCancelled := True;
    StopDownloadButton.Enabled := False;
    DownloadPage.SetText('Cancelling download...', 'Waiting for protected staging cleanup.');
    Log('Recipient requested cancellation.');
  end else
    MsgBox('Could not signal download cancellation.', mbError, MB_OK);
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if BuildActive then begin
    Cancel := False;
    StopDownload(nil);
  end;
end;

function DownloadArtifact(Identity, FileName, ExpectedHash: String): Boolean;
var
  Code: Integer;
  Params, Destination, Output, Errors: String;
begin
  Result := False;
  if DownloadCancelled then Exit;
  if CompareText(GetSHA256OfFile(ExpandConstant('{tmp}\installer-dependencies-v1.json')),
    '{#DependencyManifestSha256}') <> 0 then
    RaiseException('Embedded dependency manifest hash differs.');
  VerifyHelper('download-artifact.ps1', '{#SecureDownloaderSha256}');
  Destination := ExpandConstant('{tmp}\' + FileName);
  DownloadCancelPath := ExpandConstant('{tmp}\download-cancel.txt');
  if FileExists(DownloadCancelPath) and not DeleteFile(DownloadCancelPath) then
    RaiseException('Previous download cancellation signal could not be cleared.');
  Params := '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ' +
    AddQuotes(ExpandConstant('{tmp}\download-artifact.ps1')) +
    ' -ManifestPath ' + AddQuotes(ExpandConstant('{tmp}\installer-dependencies-v1.json')) +
    ' -Identity ' + AddQuotes(Identity) + ' -DestinationPath ' + AddQuotes(Destination) +
    ' -CancelPath ' + AddQuotes(DownloadCancelPath);
  if Identity = 'MSYS2' then Params := Params + ' -MsysInputs -ManifestSha256 {#DependencyManifestSha256}';
  DownloadPage.SetText('Downloading and verifying ' + Identity, FileName);
  Log('Recipient download: ' + Identity);
  StopDownloadButton.Enabled := True;
  if not ExecHiddenWorker(AddQuotes(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) + ' ' + Params,
    Code, Output, Errors) then Exit;
  if Output <> '' then Log(Output);
  if Errors <> '' then Log(Errors);
  if DownloadCancelled then begin
    Log('Download cancelled; helper has exited.');
    Exit;
  end;
  Result := (Code = 0) and FileExists(Destination) and (HiddenWorkerDisplayError = '');
  if Result then
    Result := CompareText(GetSHA256OfFile(Destination), ExpectedHash) = 0;
end;

function MsysCommand(Recheck: Boolean): String;
var Mode: String;
begin
  if Recheck then Mode := '$true' else Mode := '$false';
  Result := '$ErrorActionPreference=''Stop''; $locks=@(); try { ' +
    '$t=' + MsysPowerShellQuote(ExpandConstant('{tmp}')) + '; $recheck=' + Mode + '; ' +
    '$ps=Join-Path $env:SystemRoot ''System32\WindowsPowerShell\v1.0\powershell.exe''; ' +
    'function SafePath([string]$p) { if ($p -cnotmatch ''^[A-Za-z]:\\'' -or $p.Substring(3).Split(''\'') -contains ''..'' -or [IO.Path]::GetFullPath($p) -ine $p) { throw ''Absolute canonical local path required.'' }; $c=$p; while($c) { if((Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ''Reparse path prohibited.'' }; $n=Split-Path -Parent $c; if($n -eq $c){break}; $c=$n } }; ' +
    '$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $allowed=@($sid,''S-1-5-18'',''S-1-5-32-544''); ' +
    'function Protected([string]$p) { SafePath $p; $a=Get-Acl -LiteralPath $p; if($a.GetOwner([Security.Principal.SecurityIdentifier]).Value -cnotin $allowed -or -not @($a.Access).Count){throw ''Unowned or empty protected ACL.''}; $writes=278 -bor 64 -bor 65536 -bor 262144 -bor 524288 -bor 268435456 -bor 1073741824; foreach($r in $a.Access) { $s=$r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value; if($r.AccessControlType -eq ''Allow'' -and $s -cnotin $allowed -and ([long]$r.FileSystemRights -band $writes)){throw ''Foreign write ACL.''} } }; ' +
    'function Pin([string]$p,[string]$h) { SafePath $p; if($h -cnotmatch ''^[0-9a-f]{64}$'' -or -not(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $h){throw ''Pinned input changed.''}; $script:locks+=,[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $h){throw ''Pinned input changed at lock.''} }; ' +
    '$m=Join-Path $t ''installer-dependencies-v1.json''; Pin $m ''{#DependencyManifestSha256}''; ' +
    '$pins=@{''install-msys2-base.ps1''=''{#MsysBaseHelperSha256}'';''extract-msys2-base.py''=''{#MsysExtractorSha256}'';''install-msys2-packages.ps1''=''{#MsysPackagesHelperSha256}'';''install-python.ps1''=''{#PythonHelperSha256}'';''preflight.ps1''=''{#PreflightSha256}''}; foreach($n in $pins.Keys){Pin (Join-Path $t $n) $pins[$n]}; ' +
    '$tar=Join-Path $t ''msys2-base-x86_64-20260611.tar.xz''; Pin $tar ''{#MsysArchiveSha256}''; ' +
    '$manifest=Get-Content -LiteralPath $m -Raw|ConvertFrom-Json; $rows=@($manifest.build_prerequisites|Where-Object{$_.identity -ceq ''MSYS2''}); if($manifest.schema_version -ne 1 -or $rows.Count -ne 1 -or $rows[0].delivery_classification -cne ''DIRECT_RECIPIENT_DOWNLOAD'' -or $rows[0].sha256 -cne ''{#MsysArchiveSha256}'' -or (Get-Item -LiteralPath $tar).Length -ne [long]$rows[0].bytes){throw ''Exact direct MSYS2 row required.''}; ' +
    '$cancel=Join-Path $t ''download-cancel.txt''; function Cancel {if(Test-Path -LiteralPath $cancel){throw ''Recipient cancelled MSYS2 preparation.''}}; Cancel; ' +
    'if(-not $recheck) { $py=@(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $t ''install-python.ps1'') -CheckOnly); $e=$LASTEXITCODE; if($e -ne 0 -or $py.Count -ne 1){throw ''Registered Python capability missing.''}; $python=[string]$py[0]; SafePath $python; if(-not(Test-Path -LiteralPath $python -PathType Leaf) -or [IO.Path]::GetFileName($python) -ine ''python.exe''){throw ''Registered Python path invalid.''}; ' +
    '$id=[guid]::NewGuid().ToString(''N'').Substring(0,8); $parent=Join-Path ' + MsysPowerShellQuote(ExpandConstant('{commonappdata}')) + ' (''acm-''+$id); $logs=Join-Path ' + MsysPowerShellQuote(ExpandConstant('{localappdata}')) + ' (''acm-log-''+$id); [Console]::Error.WriteLine(''MSYS2 preserved logs: ''+$logs); ' +
    '$b=@(& (Join-Path $t ''install-msys2-base.ps1'') -BaseArchivePath $tar -BaseSignaturePath ($tar+''.sig'') -InstallerKeyPath (Join-Path $t ([string]$rows[0].installer_key.filename)) -ManifestPath $m -ManifestSha256 ''{#DependencyManifestSha256}'' -PythonPath $python -ExtractionHelperPath (Join-Path $t ''extract-msys2-base.py'') -ExtractionHelperSha256 ''{#MsysExtractorSha256}'' -DestinationParent $parent -LogDirectory $logs -CancelPath $cancel -InstallBase); ' +
    'if($b.Count -ne 1 -or $b[0].status -cne ''VERIFIED_PINNED_BASE'' -or $b[0].root -ine (Join-Path $parent ''msys64'') -or $b[0].receipt_path -ine (Join-Path $logs ''base-receipt.json'')){throw ''Base result binding failed.''}; $root=[string]$b[0].root; $br=[string]$b[0].receipt_path; $bh=[string]$b[0].receipt_sha256; Pin $br $bh; Cancel; ' +
    '$p=@(& (Join-Path $t ''install-msys2-packages.ps1'') -BaseArchivePath $tar -PackageDirectory $t -ManifestPath $m -MsysRoot $root -BaseReceiptPath $br -BaseReceiptSha256 $bh -InstallPinnedPackages); if($p.Count -ne 1){throw ''Package result framing failed.''}; $p=$p[0]; Cancel; ' +
    'if($p.schema_version -ne 1 -or $p.status -cne ''VERIFIED_PINNED_PACKAGES'' -or $p.root -ine $root -or $p.manifest_sha256 -cne ''{#DependencyManifestSha256}'' -or $p.base_receipt_sha256 -cne $bh -or $p.private_home -ine (Join-Path $root ''home\autoclip-base'') -or -not @($p.post_install_code_files).Count){throw ''Package result binding failed.''}; ' +
    'Protected $logs; if(-not(Get-Acl -LiteralPath $logs).AreAccessRulesProtected){throw ''Unprotected receipt directory.''}; $pr=Join-Path $logs ''package-receipt.json''; $tmp=Join-Path $logs (''.package-''+[guid]::NewGuid().ToString(''N'')+''.tmp''); $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($p|ConvertTo-Json -Depth 20)); $f=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}; [IO.File]::Move($tmp,$pr); $ph=(Get-FileHash -LiteralPath $pr).Hash.ToLowerInvariant(); ' +
    '} else { $root=' + MsysPowerShellQuote(MsysRoot) + '; $br=' + MsysPowerShellQuote(MsysBaseReceiptPath) + '; $pr=' + MsysPowerShellQuote(MsysPackageReceiptPath) + '; $ph=' + MsysPowerShellQuote(MsysPackageReceiptSha256) + '; }; ' +
    'Protected (Split-Path -Parent $root); Protected $root; Protected (Split-Path -Parent $pr); if(-not(Get-Acl -LiteralPath (Split-Path -Parent $root)).AreAccessRulesProtected -or -not(Get-Acl -LiteralPath (Split-Path -Parent $pr)).AreAccessRulesProtected){throw ''Unprotected owned directories.''}; Protected $pr; Pin $pr $ph; $p=Get-Content -LiteralPath $pr -Raw|ConvertFrom-Json; $bh=[string]$p.base_receipt_sha256; Protected $br; Pin $br $bh; $b=Get-Content -LiteralPath $br -Raw|ConvertFrom-Json; ' +
    'if($p.schema_version -ne 1 -or $p.status -cne ''VERIFIED_PINNED_PACKAGES'' -or $p.root -ine $root -or $p.manifest_sha256 -cne ''{#DependencyManifestSha256}'' -or $p.private_home -ine (Join-Path $root ''home\autoclip-base'') -or $b.schema_version -ne 1 -or $b.status -cne ''VERIFIED_PINNED_BASE'' -or $b.root -ine $root -or $b.manifest_sha256 -cne ''{#DependencyManifestSha256}'' -or $b.archive_sha256 -cne ''{#MsysArchiveSha256}'' -or $b.private_home -ine $p.private_home -or $b.signature_verified -ne $true -or $b.init_verified -ne $true -or $b.first_login_verified -ne $true -or $b.protected_root_verified -ne $true){throw ''Stored receipt binding failed.''}; ' +
    'foreach($flag in @(''signature_verified'',''init_verified'',''first_login_verified'',''protected_root_verified'')){if($b.$flag -isnot [bool] -or $b.$flag -ne $true){throw ''Base Boolean verification failed.''}}; if($b.signer_fingerprint -cne ''0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC'' -or $b.archive_bytes -ne [long]$rows[0].bytes -or $b.extraction_inventory.file_count -ne 15529 -or $b.extraction_inventory.directory_count -ne 1052){throw ''Base provenance fields failed.''}; $er=Join-Path (Split-Path -Parent $br) ''extraction-receipt.json''; Protected $er; Pin $er ([string]$b.extraction_inventory.receipt_sha256); ' +
    '$seen=New-Object ''Collections.Generic.HashSet[string]'' ([StringComparer]::OrdinalIgnoreCase); foreach($r in $p.post_install_code_files){if($r.path -cnotmatch ''^(?:usr/bin/.+|ucrt64/bin/.+|etc/profile.d/.+|etc/post-install/.+|etc/msystem.d/.+|etc/profile|etc/msystem|etc/bash.bashrc|msys2_shell.cmd)$'' -or $r.path.Split(''/'') -contains ''..'' -or -not $seen.Add([string]$r.path)){throw ''Unsafe/duplicate code closure.''}; $file=Join-Path $root $r.path; Protected $file; $c=Split-Path -Parent $file; while($c.Length -ge $root.Length){Protected $c;$c=Split-Path -Parent $c}; if($r.sha256 -cnotmatch ''^[0-9a-f]{64}$'' -or (Get-Item -LiteralPath $file).Length -ne [long]$r.bytes -or (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $r.sha256){throw ''Post-package code changed.''} }; ' +
    '$actual=@(); foreach($dir in @(''usr/bin'',''ucrt64/bin'',''etc/profile.d'',''etc/post-install'',''etc/msystem.d'')){ $stack=New-Object ''Collections.Generic.Stack[string]''; $stack.Push((Join-Path $root $dir)); while($stack.Count){$d=$stack.Pop();Protected $d;foreach($i in Get-ChildItem -LiteralPath $d -Force){Protected $i.FullName;if($i.PSIsContainer){$stack.Push($i.FullName)}else{$actual+=$i.FullName.Substring($root.Length+1).Replace(''\'',''/'')}}} }; $actual+=@(''etc/profile'',''etc/msystem'',''etc/bash.bashrc'',''msys2_shell.cmd''); if(-not $seen.Count -or @(Compare-Object @($seen) $actual -CaseSensitive).Count){throw ''Post-package closure incomplete.''}; ' +
    'foreach($n in @(''BASH_ENV'',''ENV'',''GNUPGHOME'',''PS1'',''XDG_CONFIG_HOME'',''ORIGINAL_PATH'',''SYSCONFDIR'',''CYG_SYS_BASHRC'',''SHELLOPTS'',''BASHOPTS'',''CDPATH'',''GLOBIGNORE'',''MSYS2_PS1'',''MSYS2_ARG_CONV_EXCL'',''MSYS2_ENV_CONV_EXCL'',''MSYS_NO_PATHCONV'')+@([Environment]::GetEnvironmentVariables(''Process'').Keys|Where-Object{$_ -like ''BASH_FUNC_*''})){[Environment]::SetEnvironmentVariable($n,$null,''Process'')}; $env:PATH=$root+''\usr\bin;''+$root+''\ucrt64\bin;''+$env:SystemRoot+''\System32''; $env:HOME=''/''+$root.Substring(0,1).ToLowerInvariant()+$root.Substring(2).Replace(''\'',''/'')+''/home/autoclip-base''; $env:MSYSTEM=''MSYS''; $env:MSYS2_PATH_TYPE=''strict''; $env:CHERE_INVOKING=''1''; Set-Location -LiteralPath $root; ' +
    'Cancel; $null=& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $t ''preflight.ps1'') -ManifestPath $m -CheckIdentity ''MSYS2'' -MsysRoot $root; $e=$LASTEXITCODE; if($e -ne 0){throw ''Private MSYS2 capability postcheck failed.''}; Cancel; [Console]::Out.WriteLine($root);[Console]::Out.WriteLine($br);[Console]::Out.WriteLine($pr);[Console]::Out.WriteLine($ph); exit 0 ' +
    '} catch {[Console]::Error.WriteLine($_.Exception.Message);exit 2} finally {foreach($f in $locks){$f.Dispose()}}';
end;

function RunMsysProcess(Recheck: Boolean; var Output: String): Boolean;
var Code: Integer;
    Params, Errors: String;
begin
  Result := False;
  VerifyHelper('install-msys2-base.ps1', '{#MsysBaseHelperSha256}');
  VerifyHelper('extract-msys2-base.py', '{#MsysExtractorSha256}');
  VerifyHelper('install-msys2-packages.ps1', '{#MsysPackagesHelperSha256}');
  VerifyHelper('install-python.ps1', '{#PythonHelperSha256}');
  VerifyHelper('preflight.ps1', '{#PreflightSha256}');
  Params := '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -Command ' + AddQuotes(MsysCommand(Recheck));
  DownloadPage.SetText('Preparing private MSYS2', 'Verifying base, offline packages, protected receipts and native capabilities.');
  if not ExecHiddenWorker(AddQuotes(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) + ' ' + Params,
    Code, Output, Errors) then Exit;
  if Errors <> '' then Log(Errors);
  Result := (Code = 0) and not DownloadCancelled and (HiddenWorkerDisplayError = '');
end;

function MsysResultPaths(Output: String): Boolean;
var Lines: TStringList;
    Root, Logs, Prefix, Id, Hash: String;
    I: Integer;
begin
  Result := False;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    if Lines.Count <> 4 then Exit;
    Root := Lines[0]; Hash := Lines[3];
    Prefix := ExpandConstant('{commonappdata}\acm-');
    if (CompareText(Copy(Root, 1, Length(Prefix)), Prefix) <> 0) or
      (Length(Root) <> Length(Prefix) + 8 + Length('\msys64')) then Exit;
    Id := Copy(Root, Length(Prefix) + 1, 8);
    if Copy(Root, Length(Prefix) + 9, MaxInt) <> '\msys64' then Exit;
    for I := 1 to 8 do if Pos(Copy(Id, I, 1), '0123456789abcdef') = 0 then Exit;
    Logs := ExpandConstant('{localappdata}\acm-log-') + Id;
    if (Lines[1] <> Logs + '\base-receipt.json') or (Lines[2] <> Logs + '\package-receipt.json') or (Length(Hash) <> 64) then Exit;
    for I := 1 to 64 do if Pos(Copy(Hash, I, 1), '0123456789abcdef') = 0 then Exit;
    if MsysPrepared and ((MsysRoot <> Root) or (MsysBaseReceiptPath <> Lines[1]) or
      (MsysPackageReceiptPath <> Lines[2]) or (MsysPackageReceiptSha256 <> Hash)) then Exit;
    MsysRoot := Root; MsysBaseReceiptPath := Lines[1]; MsysPackageReceiptPath := Lines[2]; MsysPackageReceiptSha256 := Hash;
    Result := True;
  finally Lines.Free; end;
end;

function PrepareMsys: String;
var Output: String;
    Recheck: Boolean;
begin
  Result := '';
  if not MsysConsentPage.Values[0] then begin
    MsysPrepared := False;
    Result := 'Explicit recipient consent for the private MSYS2 build environment is required before acquisition.';
    Exit;
  end;
  if DownloadCancelled then begin Result := 'MSYS2 preparation was cancelled.'; MsysPrepared := False; Exit; end;
  Recheck := MsysPrepared;
  DownloadPage.Show;
  try
    if not Recheck then
      if not DownloadArtifact('MSYS2', 'msys2-base-x86_64-20260611.tar.xz', '{#MsysArchiveSha256}') then begin
        Result := 'Pinned MSYS2 inputs could not be acquired. See the setup log.'; Exit;
      end;
    if not RunMsysProcess(Recheck, Output) or DownloadCancelled then begin
      MsysPrepared := False;
      Result := 'Private MSYS2 base/packages/capability preparation failed or was cancelled. Owned partial roots and logs are preserved.'; Exit;
    end;
    if not MsysResultPaths(Output) then begin
      MsysPrepared := False;
      Result := 'Private MSYS2 receipt framing or path binding failed. Source build has not started.'; Exit;
    end;
    MsysPrepared := True;
    Log('Private MSYS2 verified: ' + MsysRoot + '; package receipt: ' + MsysPackageReceiptPath + '; SHA256=' + MsysPackageReceiptSha256);
  finally DownloadPage.Hide; end;
end;

function MsysBuildArguments: String;
begin
  if not MsysPrepared then RaiseException('Private MSYS2 has not passed preparation.');
  Result := ' -MsysBash ' + AddQuotes(MsysRoot + '\usr\bin\bash.exe') +
    ' -MsysPackageReceiptPath ' + AddQuotes(MsysPackageReceiptPath) +
    ' -MsysPackageReceiptSha256 ' + MsysPackageReceiptSha256 +
    ' -MsysBaseArchivePath ' + AddQuotes(ExpandConstant('{tmp}\msys2-base-x86_64-20260611.tar.xz'));
end;

function PreparePython(var NeedsRestart: Boolean): String;
var
  Code, State: Integer;
  Params: String;
begin
  Result := '';
  State := PythonRebootStatus(False);
  if PythonRestartPending or (State = 3010) then begin
    NeedsRestart := not WizardSilent;
    Result := 'Python restart is pending. Restart Windows, then rerun setup for capability verification.';
    Exit;
  end;
  if State <> 0 then begin
    Result := 'Python reboot state could not be verified. See the setup log; no Python acquisition was attempted.';
    Exit;
  end;
  VerifyHelper('preflight.ps1', '{#PreflightSha256}');
  VerifyHelper('install-python.ps1', '{#PythonHelperSha256}');
  if ToolAvailable('Python') then Exit;
  if not PythonConsentPage.Values[0] then begin
    Result := 'Explicit recipient Python 3.11.9 terms consent is required before Python download or installation.';
    Exit;
  end;
  DownloadPage.Show;
  try
    if not DownloadArtifact('Python', 'python-3.11.9-amd64.exe', '{#PythonSha256}') then begin
      Result := 'Pinned Python download failed or was cancelled. See the setup log.';
      Exit;
    end;
  finally
    DownloadPage.Hide;
  end;
  VerifyHelper('install-python.ps1', '{#PythonHelperSha256}');
  if CompareText(GetSHA256OfFile(ExpandConstant('{tmp}\installer-dependencies-v1.json')), '{#DependencyManifestSha256}') <> 0 then
    RaiseException('Embedded dependency manifest hash differs before Python provisioning.');
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + AddQuotes(ExpandConstant('{tmp}\install-python.ps1')) +
    ' -InstallerPath ' + AddQuotes(ExpandConstant('{tmp}\python-3.11.9-amd64.exe')) +
    ' -ManifestPath ' + AddQuotes(ExpandConstant('{tmp}\installer-dependencies-v1.json')) +
    ' -LogDirectory ' + AddQuotes(PythonLogDirectory) + ' -AcceptPythonTerms';
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) then begin
    Result := 'Python helper could not be started. See the setup log.';
    Exit;
  end;
  if Code = 3010 then begin
    PythonRestartPending := True;
    State := PythonRebootStatus(True);
    NeedsRestart := not WizardSilent;
    Result := 'Python requires a Windows restart; setup has not succeeded. Restart, then rerun capability verification.';
    if State <> 3010 then Result := Result + ' Durable reboot state could not be recorded; retain the Python helper receipt and resolve manually.';
    Exit;
  end;
  if Code = 1602 then begin
    Result := 'Python installation was cancelled. Setup has not succeeded.';
    Exit;
  end;
  if Code <> 0 then begin
    Result := 'Python helper failed with code ' + IntToStr(Code) + '. See the vendor log and receipt.';
    Exit;
  end;
  if not ToolAvailable('Python') then
    Result := 'Python helper returned success but exact registered 3.11.9 x64 capability verification failed.';
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if (FileExists(ExpandConstant('{localappdata}\AutoClip\active.json')) or
      FileExists(ExpandConstant('{localappdata}\AutoClip\app-active.json')) or
      FileExists(ExpandConstant('{localappdata}\AutoClip\Setup\unins000.exe'))) and
     not FileExists(ExpandConstant('{localappdata}\AutoClip\Setup\installation-receipts\{#ReleaseId}.json')) then begin
    SuppressibleMsgBox('A different AutoClip runtime is already installed. Close AutoClip and use AutoClip-Update-v1.0.0.zip from the v1.0.0 release to update the application with the installed updater. The existing installation has been preserved.', mbError, MB_OK, IDOK);
    Result := False;
  end;
end;

procedure InitializeWizard;
var
  TermsLink: TNewStaticText;
begin
  ForcedMaintenance := (CompareText(ExtractFileName(ExpandConstant('{srcexe}')), 'AutoClip-Maintenance.exe') = 0) or
    (ExpandConstant('{param:MAINTENANCE|no}') <> 'no');
  if ForcedMaintenance and not (FileExists(ExpandConstant('{localappdata}\AutoClip\Setup\installation-receipts\{#ReleaseId}.json')) and
    FileExists(ExpandConstant('{localappdata}\AutoClip\Setup\installation-receipts\{#ReleaseId}.sha256'))) then
    RaiseException('This AutoClip maintenance entry point requires its verified installation receipt.');
  ActionPage := CreateInputOptionPage(wpWelcome, 'AutoClip setup and maintenance', 'Choose an action',
    'Install AutoClip, update the application using its verified runtime, or roll back to a retained application.', True, False);
  ActionPage.Add('Install AutoClip');
  ActionPage.Add('Update AutoClip');
  ActionPage.Add('Roll back the application');
  ActionPage.Values[0] := True;
  if ForcedMaintenance or (FileExists(ExpandConstant('{localappdata}\AutoClip\Setup\installation-receipts\{#ReleaseId}.json')) and
    FileExists(ExpandConstant('{localappdata}\AutoClip\Setup\installation-receipts\{#ReleaseId}.sha256'))) then begin
    ActionPage.Values[0] := False;
    if CompareText(ExpandConstant('{param:MAINTENANCE|no}'), 'rollback') = 0 then ActionPage.Values[2] := True
    else ActionPage.Values[1] := True;
  end;
  ProgressPage := CreateOutputMarqueeProgressPage('AutoClip maintenance', 'Please wait for the verified operation to finish.');
  VcConsentStatus := -1;
  if AuditRequested then begin
    ExtractTemporaryFile('install.ps1');
    ExtractTemporaryFile('preflight.ps1');
    ExtractTemporaryFile('install-tool-archive.ps1');
    ExtractTemporaryFile('download-artifact.ps1');
    ExtractTemporaryFile('install-python.ps1');
    ExtractTemporaryFile('install-msys2-base.ps1');
    ExtractTemporaryFile('extract-msys2-base.py');
    ExtractTemporaryFile('install-msys2-packages.ps1');
    ExtractTemporaryFile('install-runtime-toolpath.ps1');
    ExtractTemporaryFile('run-source-build.ps1');
    ExtractTemporaryFile('verify-installed-app.ps1');
    ExtractTemporaryFile('write-setup-receipt.ps1');
    ExtractTemporaryFile('installer-dependencies-v1.json');
    ExtractTemporaryFile('inno-setup-7.1.0-LICENSE.txt');
    ExtractTemporaryFile('uv-0.12.19-LICENSE-MIT.txt');
    ExtractTemporaryFile('uv-0.12.19-LICENSE-APACHE.txt');
    ExtractTemporaryFile('setup-tool-sources.md');
    Log('AUDIT install.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\install.ps1')));
    Log('AUDIT preflight.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\preflight.ps1')));
    Log('AUDIT install-tool-archive.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\install-tool-archive.ps1')));
    Log('AUDIT download-artifact.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\download-artifact.ps1')));
    Log('AUDIT install-python.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\install-python.ps1')));
    Log('AUDIT install-msys2-base.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\install-msys2-base.ps1')));
    Log('AUDIT extract-msys2-base.py SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\extract-msys2-base.py')));
    Log('AUDIT install-msys2-packages.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\install-msys2-packages.ps1')));
    Log('AUDIT install-runtime-toolpath.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\install-runtime-toolpath.ps1')));
    Log('AUDIT run-source-build.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\run-source-build.ps1')));
    Log('AUDIT verify-installed-app.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\verify-installed-app.ps1')));
    Log('AUDIT write-setup-receipt.ps1 SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\write-setup-receipt.ps1')));
    Log('AUDIT installer-dependencies-v1.json SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\installer-dependencies-v1.json')));
    Log('AUDIT inno-setup-7.1.0-LICENSE.txt SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\inno-setup-7.1.0-LICENSE.txt')));
    Log('AUDIT uv-0.12.19-LICENSE-MIT.txt SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\uv-0.12.19-LICENSE-MIT.txt')));
    Log('AUDIT uv-0.12.19-LICENSE-APACHE.txt SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\uv-0.12.19-LICENSE-APACHE.txt')));
    Log('AUDIT setup-tool-sources.md SHA256=' + GetSHA256OfFile(ExpandConstant('{tmp}\setup-tool-sources.md')));
    Abort;
  end;
  ProfilePage := CreateInputOptionPage(ActionPage.ID, 'Runtime profile',
    'Choose the runtime to install', 'CPU works without NVIDIA hardware.', True, False);
  ProfilePage.Add('CPU (default)');
  ProfilePage.Add('NVIDIA GPU (requires compatible NVIDIA graphics)');
  ProfilePage.Values[0] := True;

  SummaryPage := CreateCustomPage(ProfilePage.ID, 'Prerequisites',
    'Review the downloads and any missing prerequisites before continuing.');
  SummaryText := TMemo.Create(SummaryPage);
  SummaryText.Parent := SummaryPage.Surface;
  SummaryText.Align := alClient;
  SummaryText.ReadOnly := True;
  SummaryText.ScrollBars := ssVertical;

  PythonConsentPage := CreateInputOptionPage(SummaryPage.ID, 'Python 3.11.9 terms',
    'Consent for a missing Python prerequisite', 'Review the exact Python terms. Existing verified compatible Python requires no new declaration.', False, False);
  PythonConsentPage.Add('I have reviewed and agree to the Python 3.11.9 terms linked below.');
  TermsLink := TNewStaticText.Create(PythonConsentPage);
  TermsLink.Parent := PythonConsentPage.Surface;
  TermsLink.Top := ScaleY(100);
  TermsLink.Caption := 'Open exact Python 3.11.9 terms';
  TermsLink.Cursor := crHand;
  TermsLink.Font.Color := clBlue;
  TermsLink.OnClick := @OpenPythonTerms;

  ConsentPage := CreateInputOptionPage(PythonConsentPage.ID, 'Microsoft Runtime terms',
    'Recipient consent', 'Review the applicable vendor terms. Check each box only if you agree.', False, False);
  ConsentPage.Add('I agree to the Microsoft Visual C++ Runtime terms linked below.');
  TermsLink := TNewStaticText.Create(ConsentPage);
  TermsLink.Parent := ConsentPage.Surface;
  TermsLink.Top := ScaleY(100);
  TermsLink.Caption := 'Open Microsoft terms';
  TermsLink.Cursor := crHand;
  TermsLink.Font.Color := clBlue;
  TermsLink.OnClick := @OpenMicrosoftTerms;

  NvidiaConsentPage := CreateInputOptionPage(ConsentPage.ID, 'NVIDIA terms',
    'Consent for the optional NVIDIA profile', 'Review the exact vendor terms. Check each box only if you agree.', False, False);
  #if NativeNvidiaEnabled
  NvidiaConsentPage.Add('I agree to the NVIDIA CUDA runtime 12.8 terms for components included in the GPU runtime.');
#else
  NvidiaConsentPage.Add('I agree to the NVIDIA CUDA Toolkit 12.8.0 terms linked below.');
#endif
  NvidiaConsentPage.Add('I agree to the NVIDIA cuBLAS 12.4.5.8 terms linked below.');
  TermsLink := TNewStaticText.Create(NvidiaConsentPage);
  TermsLink.Parent := NvidiaConsentPage.Surface;
  TermsLink.Top := ScaleY(125);
  TermsLink.Caption := 'Open NVIDIA terms';
  TermsLink.Cursor := crHand;
  TermsLink.Font.Color := clBlue;
  TermsLink.OnClick := @OpenNvidiaTerms;
  TermsLink := TNewStaticText.Create(NvidiaConsentPage);
  TermsLink.Parent := NvidiaConsentPage.Surface;
  TermsLink.Top := ScaleY(150);
  TermsLink.Caption := 'Open exact cuBLAS terms';
  TermsLink.Cursor := crHand;
  TermsLink.Font.Color := clBlue;
  TermsLink.OnClick := @OpenCublasTerms;

  MsysConsentPage := CreateInputOptionPage(NvidiaConsentPage.ID, 'Private MSYS2 build environment',
    'Recipient prerequisite decision', 'Review the MSYS2 component licenses. Setup provisions a separate protected per-user environment and preserves any existing system MSYS2.', False, False);
  MsysConsentPage.Add('I have reviewed the MSYS2 license information and authorize this private native-build prerequisite installation.');
  TermsLink := TNewStaticText.Create(MsysConsentPage);
  TermsLink.Parent := MsysConsentPage.Surface;
  TermsLink.Top := ScaleY(110);
  TermsLink.Caption := 'Open official MSYS2 component license information';
  TermsLink.Cursor := crHand;
  TermsLink.Font.Color := clBlue;
  TermsLink.OnClick := @OpenMsysLicenses;

  DownloadPage := CreateOutputMarqueeProgressPage('Downloading AutoClip', 'Protected official downloads and exact artifact verification');
  StopDownloadButton := TNewButton.Create(DownloadPage);
  StopDownloadButton.Parent := DownloadPage.Surface;
  StopDownloadButton.Top := DownloadPage.ProgressBar.Top + DownloadPage.ProgressBar.Height + ScaleY(8);
  StopDownloadButton.Width := ScaleX(120);
  StopDownloadButton.Height := WizardForm.CancelButton.Height;
  StopDownloadButton.Caption := 'Stop download';
  StopDownloadButton.OnClick := @StopDownload;
  BuildOutput := TMemo.Create(DownloadPage);
  BuildOutput.Parent := DownloadPage.Surface;
  BuildOutput.Top := StopDownloadButton.Top + StopDownloadButton.Height + ScaleY(8);
  BuildOutput.Width := DownloadPage.SurfaceWidth;
  BuildOutput.Height := DownloadPage.SurfaceHeight - BuildOutput.Top;
  BuildOutput.ReadOnly := True;
  BuildOutput.ScrollBars := ssVertical;
  BuildOutput.Visible := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ActionPage.ID then begin
    if ForcedMaintenance and ActionPage.Values[0] then begin
      MsgBox('Run the installer entry point to install AutoClip. This retained entry point is for maintenance.', mbError, MB_OK);
      Result := False; Exit;
    end;
    if not IsInstallMode then begin
      if not OperationDone then begin
        try RunMaintenance;
        except
          OperationDone := True; OperationSucceeded := False;
          Log('AutoClip maintenance failed: ' + GetExceptionMessage);
        end;
      end;
      Exit;
    end;
  end;
  if CurPageID = ProfilePage.ID then begin
    ConsentPage.Values[0] := False;
    NvidiaConsentPage.Values[0] := False;
    NvidiaConsentPage.Values[1] := False;
    VcConsentStatus := -1;
    { The manifest is extracted below before the preflight runs. }
    ExtractTemporaryFile('installer-dependencies-v1.json');
    RunPreflight;
    if not UsePublisherCpu then
      SummaryText.Text := SummaryText.Text + #13#10 + #13#10 + MsysSummary;
  end;
  if CurPageID = SummaryPage.ID then begin
    if not PreflightReady then begin
      MsgBox('Required prerequisites are missing or blocked. Review the list above; setup has made no installation changes.', mbError, MB_OK);
      Result := False;
    end;
    if Result and UsePublisherCpu then begin
      VcConsentStatus := PublisherVcConsentStatus;
      if (VcConsentStatus <> 0) and (VcConsentStatus <> 2) then begin
        if VcConsentStatus = 3010 then
          MsgBox('Microsoft Runtime requires a restart before Setup can continue. Restart Windows and run Setup again.', mbError, MB_OK)
        else
          MsgBox('Microsoft Runtime capability or its pending installation state could not be verified. Resolve the existing installation before continuing.', mbError, MB_OK);
        Result := False;
      end;
    end;
  end;
  if CurPageID = ConsentPage.ID then begin
    if (UsePublisherCpu and (VcConsentStatus <> 0) and (VcConsentStatus <> 2)) or
       (not ConsentPage.Values[0] and not (UsePublisherCpu and (VcConsentStatus = 0))) then begin
      MsgBox('Explicit vendor terms consent is required for this profile.', mbError, MB_OK);
      Result := False;
    end;
  end;
  if (CurPageID = NvidiaConsentPage.ID) and ProfilePage.Values[1] and
     (not NvidiaConsentPage.Values[0] or not NvidiaConsentPage.Values[1]) then begin
    MsgBox('Explicit NVIDIA vendor terms consent is required for this profile.', mbError, MB_OK);
    Result := False;
  end;
  if CurPageID = PythonConsentPage.ID then begin
    if not ToolAvailable('Python') and not PythonConsentPage.Values[0] then begin
      MsgBox('Explicit Python terms consent is required before acquiring missing Python.', mbError, MB_OK);
      Result := False;
    end;
  end;
  if (CurPageID = MsysConsentPage.ID) and not UsePublisherCpu and not MsysConsentPage.Values[0] then begin
    MsgBox('Explicit consent is required before downloading or preparing the private MSYS2 build environment.', mbError, MB_OK);
    Result := False;
  end;
end;

function BuildJsonString(Value: String): String;
var I: Integer;
begin
  for I := 1 to Length(Value) do
    if Ord(Value[I]) < 32 then RaiseException('Invalid control character in build arguments.');
  StringChangeEx(Value, '\', '\\', True);
  StringChangeEx(Value, '"', '\"', True);
  Result := '"' + Value + '"';
end;

function PublisherCpuBuildArguments: String;
begin
  Result := '';
#if NativeCpuEnabled
  if ProfilePage.Values[0] and UsePublisherCpu then
    Result := ',"CpuNativeArtifactPath":' + BuildJsonString(ExpandConstant('{tmp}\{#CpuNativeFilename}'));
#endif
#ifdef NativeNvidiaEnabled
#if NativeNvidiaEnabled
  if ProfilePage.Values[1] and UsePublisherCpu then
    Result := ',"NvidiaNativeArtifactPath":' + BuildJsonString(ExpandConstant('{tmp}\{#NvidiaNativeFilename}'));
#endif
#endif
  if Result = '' then Exit;
#if Int(NativeCpuEnabled) || Int(NativeNvidiaEnabled)
  VerifyHelper('install-cpu-native-artifact.py', '{#CpuNativeHelperSha256}');
  VerifyHelper('install-python.ps1', '{#PythonPrerequisiteHelperSha256}');
  VerifyHelper('install-vc-runtime.ps1', '{#VcRuntimeHelperSha256}');
  Result := Result + ',"CpuNativeHelperSha256":"{#CpuNativeHelperSha256}"' +
    ',"PythonPrerequisiteHelperSha256":"{#PythonPrerequisiteHelperSha256}"' +
    ',"VcRuntimeHelperSha256":"{#VcRuntimeHelperSha256}"';
#endif
end;

function VendorConsentBuildArguments: String;
begin
  Result := '';
  if ConsentPage.Values[0] and (not UsePublisherCpu or (VcConsentStatus = 2)) then
    Result := ',"AcceptMicrosoftTerms":true';
  if ProfilePage.Values[1] and NvidiaConsentPage.Values[0] and NvidiaConsentPage.Values[1] then
    Result := Result + ',"AcceptNvidiaTerms":true,"AcceptCublasTerms":true';
end;

function RunSourceBuild(Archive, GitPath, UvPath: String): Boolean;
var
  Params, ArgumentsPath, Json, ProcessError, Output, Errors: String;
  Lines: TArrayOfString;
  Code: Integer;
  Started: Boolean;
begin
  Result := False;
  Started := False;
  ProcessError := '';
  if not UsePublisherCpu and not MsysPrepared then RaiseException('Private MSYS2 has not passed preparation.');
  VerifyHelper('install.ps1', '{#BootstrapSha256}');
  VerifyHelper('run-source-build.ps1', '{#SourceBuildHelperSha256}');
  VerifyHelper('verify-installed-app.ps1', '{#AppHealthHelperSha256}');
  VerifyHelper('write-setup-receipt.ps1', '{#SetupReceiptHelperSha256}');
  VerifyHelper('download-artifact.ps1', '{#SecureDownloaderSha256}');
  VerifyHelper('install-tool-archive.ps1', '{#ToolArchiveHelperSha256}');
  VerifyHelper('install-runtime-toolpath.ps1', '{#RuntimeToolPathHelperSha256}');
  BuildAttemptIndex := BuildAttemptIndex + 1;
  BuildAttemptDirectory := ExpandConstant('{localappdata}\AutoClip\Setup\logs\source-build-') +
    ExtractFileName(ExpandConstant('{tmp}')) + '-' + IntToStr(BuildAttemptIndex);
  ArgumentsPath := ExpandConstant('{tmp}\build-arguments-') + IntToStr(BuildAttemptIndex) + '.json';
  if FileExists(ArgumentsPath) or DirExists(BuildAttemptDirectory) then
    RaiseException('Source build attempt already exists; its files were preserved.');
  Json := '{"schema_version":1,"parameters":{' +
    '"ArchivePath":' + BuildJsonString(Archive) +
    ',"InstallRoot":' + BuildJsonString(ReleaseRoot) +
    ',"NonInteractive":true,"NoPrerequisiteAcquisition":true,"SkipDesktopShortcut":true' + VendorConsentBuildArguments +
    ',"FfmpegArchivePath":' + BuildJsonString(ExpandConstant('{tmp}\ffmpeg-9.0.1-essentials_build.zip')) +
    ',"ToolArchiveHelperSha256":"{#ToolArchiveHelperSha256}"' +
    ',"RuntimeToolPathHelperSha256":"{#RuntimeToolPathHelperSha256}"' +
    ',"AppHealthHelperSha256":"{#AppHealthHelperSha256}"' +
    ',"SetupReceiptHelperSha256":"{#SetupReceiptHelperSha256}"';
  if UsePublisherCpu then Json := Json + PublisherCpuBuildArguments
  else Json := Json + ',"MsysBash":' + BuildJsonString(MsysRoot + '\usr\bin\bash.exe') +
    ',"MsysPackageReceiptPath":' + BuildJsonString(MsysPackageReceiptPath) +
    ',"MsysPackageReceiptSha256":' + BuildJsonString(MsysPackageReceiptSha256) +
    ',"MsysBaseArchivePath":' + BuildJsonString(ExpandConstant('{tmp}\msys2-base-x86_64-20260611.tar.xz'));
  if (GitPath <> '') and not UsePublisherCpu then Json := Json + ',"GitExePath":' + BuildJsonString(GitPath);
  if UvPath <> '' then Json := Json + ',"UvExePath":' + BuildJsonString(UvPath);
  if ProfilePage.Values[1] then Json := Json +
    ',"InstallNvidiaGpu":true,"AllowPinnedNvidiaAcquisition":true';
  Json := Json + '}}';
  SetArrayLength(Lines, 1); Lines[0] := Json;
  if not SaveStringsToUTF8File(ArgumentsPath, Lines, False) then
    RaiseException('Could not save source build arguments.');
  Params := '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ' +
    AddQuotes(ExpandConstant('{tmp}\run-source-build.ps1')) +
    ' -HelperSha256 {#SourceBuildHelperSha256}' +
    ' -BootstrapPath ' + AddQuotes(ExpandConstant('{tmp}\install.ps1')) + ' -BootstrapSha256 {#BootstrapSha256}' +
    ' -ManifestPath ' + AddQuotes(ExpandConstant('{tmp}\installer-dependencies-v1.json')) + ' -ManifestSha256 {#DependencyManifestSha256}' +
    ' -DownloaderPath ' + AddQuotes(ExpandConstant('{tmp}\download-artifact.ps1')) + ' -DownloaderSha256 {#SecureDownloaderSha256}' +
    ' -ArgumentsPath ' + AddQuotes(ArgumentsPath) + ' -ArgumentsSha256 ' + GetSHA256OfFile(ArgumentsPath) +
    ' -AttemptDirectory ' + AddQuotes(BuildAttemptDirectory);
  DownloadCancelPath := BuildAttemptDirectory + '\cancel.txt';
  DownloadCancelled := False;
  BuildCancelPending := False;
  BuildCancellationClosed := False;
  BuildRequestCommand := AddQuotes(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) + ' ' + Params;
  StopDownloadButton.Caption := 'Cancel installation';
  StopDownloadButton.Enabled := True;
  BuildOutput.Clear;
  BuildOutput.Visible := True;
  if UsePublisherCpu then
    DownloadPage.SetText('Installing AutoClip and verifying its runtime', 'Installing the verified runtime for the selected profile. Recent output appears below.')
  else DownloadPage.SetText('Building AutoClip and verifying its runtime', 'Native compilation can take time. Recent output appears below.');
  BuildActive := True;
  try
    try
      DownloadPage.Show;
      Started := ExecHiddenWorker(BuildRequestCommand, Code, Output, Errors);
      ProcessError := HiddenWorkerDisplayError;
      Log(Output); Log(Errors);
      Result := Started and (Code = 0) and not DownloadCancelled;
      Log('Source build supervisor exit: ' + IntToStr(Code) + '; logs: ' + BuildAttemptDirectory);
    except
      { Clear the pending exception before nested cleanup handlers run. }
      ProcessError := GetExceptionMessage;
    end;
  finally
    { The native wait returned only after observing this exact supervisor. }
    BuildActive := False;
    try
      WizardForm.CancelButton.Enabled := True;
      BuildOutput.Visible := False;
      StopDownloadButton.Caption := 'Stop download';
      DownloadPage.Hide;
    except
      if ProcessError = '' then ProcessError := GetExceptionMessage;
    end;
  end;
  if ProcessError <> '' then begin
    Result := False;
    RaiseException(ProcessError);
  end;
end;

procedure ReleaseNativeSetupInputs;
begin
  if SetupSelectionEngineStream <> nil then begin SetupSelectionEngineStream.Free; SetupSelectionEngineStream := nil; end;
  if SetupSelectionSourceStream <> nil then begin SetupSelectionSourceStream.Free; SetupSelectionSourceStream := nil; end;
  if SetupSelectionProofStream <> nil then begin SetupSelectionProofStream.Free; SetupSelectionProofStream := nil; end;
end;

function AcquireNativeSetupSelection: Boolean;
var OutputPath, Command, Params, EnginePath: String;
    Text: AnsiString;
    Code: Integer;
    Handle, WaitResult, ModuleLength: Cardinal;
begin
  Result := False;
  if SetupSelectionHandle <> 0 then begin
    Result := (SetupSelectionThread = SetupNativeThread) and
      (SetupSelectionProofStream <> nil) and (Length(SetupSelectionHash) = 64) and
      (SetupSelectionEngineStream <> nil) and (SetupSelectionSourceStream <> nil);
    Exit;
  end;
  VerifyHelper('initialize-selection.ps1', '{#InitialSelectionSha256}');
  VerifyHelper('write-setup-receipt.ps1', '{#SetupReceiptHelperSha256}');
  VerifyHelper('update-app.ps1', '{#AppUpdaterSha256}');
  OutputPath := ExpandConstant('{tmp}\native-selection.txt');
  Command := '$ErrorActionPreference=''Stop'';$f=$null;try{$h=' + MsysPowerShellQuote(ExpandConstant('{tmp}\initialize-selection.ps1')) +
    ';$f=[IO.File]::Open($h,''Open'',''Read'',''Read'');if((Get-FileHash -InputStream $f).Hash.ToLowerInvariant() -cne ''{#InitialSelectionSha256}''){throw ''Changed native admission helper''};' +
    '& $h -AdmitNativeSetup -NativePid ' + IntToStr(SetupNativePid) +
    ' -NativeSha256 ' + Lowercase(GetSHA256OfFile(ExpandConstant('{srcexe}'))) +
    ' -BaseRoot ' + MsysPowerShellQuote(ExpandConstant('{localappdata}\AutoClip')) +
    ' -OutputPath ' + MsysPowerShellQuote(OutputPath) +
    ' -ReceiptHelperSha256 ''{#SetupReceiptHelperSha256}'' -UpdaterSha256 ''{#AppUpdaterSha256}'';exit $LASTEXITCODE' +
    '}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{if($f){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) or (Code <> 0) then Exit;
  if not LoadStringFromFile(OutputPath, Text) then Exit;
  Handle := StrToIntDef(Text, 0);
  if Handle = 0 then Exit;
  WaitResult := SetupSelectionWait(Handle, 0);
  if (WaitResult <> 0) and (WaitResult <> 128) then begin SetupSelectionClose(Handle); Exit; end;
  SetupSelectionHandle := Handle;
  SetupSelectionThread := SetupNativeThread;
  SetupSelectionPath := OutputPath + '.proof\handoff.json';
  try
    try
      SetupSelectionProofStream := TFileStream.Create(SetupSelectionPath, fmOpenRead or fmShareDenyWrite);
      SetupSelectionHash := Lowercase(GetSHA256OfFile(SetupSelectionPath));
      SetLength(EnginePath, 32768);
      ModuleLength := SetupNativeModule(0, EnginePath, 32768);
      if (ModuleLength = 0) or (ModuleLength >= 32768) then Exit;
      EnginePath := Copy(EnginePath, 1, ModuleLength);
      SetupSelectionEngineStream := TFileStream.Create(EnginePath, fmOpenRead or fmShareDenyWrite);
      SetupSelectionSourceStream := TFileStream.Create(ExpandConstant('{srcexe}'), fmOpenRead or fmShareDenyWrite);
      Result := True;
    except
      Log('Native selection input retention failed: ' + GetExceptionMessage);
    end;
  finally
    if not Result then ReleaseNativeSetupInputs;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Archive: String;
  NeedsGit: Boolean;
  NeedsUv: Boolean;
  GitRoot: String;
  UvRoot: String;
begin
  Result := '';
  if not IsInstallMode then begin
    if not OperationDone then RunMaintenance;
    Exit;
  end;
  if not PreflightReady then begin
    Result := 'Preflight has not passed.';
    Exit;
  end;
  if not AcquireNativeSetupSelection then begin
    Result := 'AutoClip selection is busy or native admission could not be verified. Managed installation was not started.';
    Exit;
  end;
  Result := PreparePython(NeedsRestart);
  if Result <> '' then Exit;
  if not UsePublisherCpu then begin
    Result := PrepareMsys;
    if Result <> '' then Exit;
  end;
  Archive := ExpandConstant('{tmp}\autoclip-source-build.zip');
  NeedsGit := False;
  if not UsePublisherCpu then NeedsGit := not ToolAvailable('Git for Windows');
  NeedsUv := not ToolAvailable('uv');
  GitRoot := ExpandConstant('{tmp}\mingit');
  UvRoot := ExpandConstant('{tmp}\uv');
  DownloadCancelled := False;
  DownloadPage.Show;
  try
    try
      if NeedsGit and not GitPrepared then
        if not DownloadArtifact('Git for Windows', 'MinGit-2.55.0.3-64-bit.zip', '{#MinGitSha256}') then
          RaiseException('Pinned MinGit download failed or was cancelled. See the setup log.');
      if NeedsUv and not UvPrepared then
        if not DownloadArtifact('uv', 'uv-0.12.19-x64.zip', '{#UvSha256}') then
          RaiseException('Pinned uv download failed or was cancelled. See the setup log.');
      if not DownloadArtifact('{#ReleaseId}', 'autoclip-source-build.zip', '{#ReleaseSha256}') then
        RaiseException('Pinned AutoClip download failed or was cancelled. See the setup log.');
      if not DownloadArtifact('Gyan FFmpeg', 'ffmpeg-9.0.1-essentials_build.zip', '{#FfmpegSha256}') then
        RaiseException('Pinned FFmpeg download failed or was cancelled. See the setup log.');
#if NativeCpuEnabled
      if UsePublisherCpu and ProfilePage.Values[0] then
        if not DownloadArtifact('{#CpuNativeIdentity}', '{#CpuNativeFilename}', '{#CpuNativeSha256}') then
          RaiseException('Pinned CPU runtime download failed or was cancelled. See the setup log.');
#endif
#ifdef NativeNvidiaEnabled
#if NativeNvidiaEnabled
      if UsePublisherCpu and ProfilePage.Values[1] then
        if not DownloadArtifact('{#NvidiaNativeIdentity}', '{#NvidiaNativeFilename}', '{#NvidiaNativeSha256}') then
          RaiseException('Pinned GPU runtime download failed or was cancelled. See the setup log.');
#endif
#endif
    except
      Result := 'AutoClip download failed: ' + GetExceptionMessage;
      Exit;
    end;
  finally
    DownloadPage.Hide;
  end;
  if CompareText(GetSHA256OfFile(Archive), '{#ReleaseSha256}') <> 0 then begin
    Result := 'Release archive hash changed after download.';
    Exit;
  end;
  if NeedsGit and not GitPrepared then begin
    if not InstallToolArchive('Git for Windows', 'MinGit-2.55.0.3-64-bit.zip', GitRoot) then begin
      Result := 'Pinned MinGit archive failed verification or extraction.';
      Exit;
    end;
    GitPrepared := True;
  end;
  if NeedsUv and not UvPrepared then begin
    if not InstallToolArchive('uv', 'uv-0.12.19-x64.zip', UvRoot) then begin
      Result := 'Pinned uv archive failed verification or extraction.';
      Exit;
    end;
    UvPrepared := True;
  end;
  if NeedsGit then GitRoot := GitRoot + '\cmd\git.exe' else GitRoot := '';
  if NeedsUv then UvRoot := UvRoot + '\uv.exe' else UvRoot := '';
  if not RunSourceBuild(Archive, GitRoot, UvRoot) then begin
    Result := 'AutoClip installation failed or was cancelled. Logs: ' + BuildAttemptDirectory;
    Exit;
  end;
  if not FileExists(ReleaseRoot + '\.install-complete') or
     not FileExists(ReleaseRoot + '\release-manifest.json') or
     not FileExists(ReleaseRoot + '\AutoClip.lnk') or
     not FileExists(ReleaseRoot + '\.setup-source-ownership.json') or
     (CompareText(GetSHA256OfFile(ReleaseRoot + '\release-manifest.json'),
       '{#ReleaseManifestSha256}') <> 0) then
    Result := 'AutoClip did not produce a verified completion marker, manifest, launcher and source ownership record.';
  if Result = '' then
    SourceHandoffSha256 := Lowercase(GetSHA256OfFile(ReleaseRoot + '\.setup-source-ownership.json'));
end;

function ValidUninstallHandoff(Path, Hash: String): Boolean;
var I: Integer;
begin
  Result := (Path <> '') and (Length(Hash) = 64);
  if not Result then Exit;
  for I := 1 to Length(Hash) do
    if Pos(Hash[I], '0123456789abcdef') = 0 then begin Result := False; Exit; end;
end;

function BuildUninstallCommand(NativeSilent: Boolean): String;
var Command, Mode: String;
begin
  if NativeSilent then Mode := ' -NativeSilent' else Mode := '';
  Command := '$ErrorActionPreference=''Stop'';$f=$null;try{$s=' + MsysPowerShellQuote(ExpandConstant('{app}')) +
    ';$h=Join-Path $s ''uninstall-owned-release.ps1'';$c=[IO.Path]::GetFullPath($h);while($c){if((Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ''Reparse launcher input''};$n=Split-Path -Parent $c;if($n -eq $c){break};$c=$n};' +
    '$f=[IO.File]::Open($h,''Open'',''Read'',''Read, Delete'');if((Get-FileHash -LiteralPath $h).Hash.ToLowerInvariant() -cne ''{#UninstallHelperSha256}''){throw ''Changed uninstall launcher''};' +
    '$r=Join-Path $s ''installation-receipts/{#ReleaseId}.json'';$a=Join-Path $s ''installation-receipts/{#ReleaseId}.sha256'';$hash=[IO.File]::ReadAllText($a);if($hash -cnotmatch ''^[a-f0-9]{64}$''){throw ''Invalid receipt anchor''};' +
    '& $h -LaunchNativeUninstall -ReceiptPath $r -ReceiptSha256 $hash -ReleaseId ''{#ReleaseId}'' -InstallRoot ' + MsysPowerShellQuote(ExpandConstant('{localappdata}\AutoClip\{#ReleaseId}')) +
    ' -ReceiptHelperSha256 ''{#SetupReceiptHelperSha256}'' -RemovalHelperSha256 ''{#RemovalHelperSha256}'' -SourceBuildHelperSha256 ''{#SourceBuildHelperSha256}'' -UpdaterSha256 ''{#UpdaterSha256}''' + Mode + ';exit $LASTEXITCODE' +
    '}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{if($f){$f.Dispose()}}';
  Result := AddQuotes(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) +
    ' -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
end;

procedure RegisterManagedUninstall;
var Key, Command: String;
begin
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D7451842-48F4-487B-80E0-5C7E9E326342}_is1';
  Command := BuildUninstallCommand(False);
  if not RegValueExists(HKCU64, Key, 'UninstallString') then RaiseException('Native uninstall registration is missing.');
  if not RegWriteStringValue(HKCU64, Key, 'UninstallString', Command) or
     not RegWriteStringValue(HKCU64, Key, 'QuietUninstallString', BuildUninstallCommand(True)) then
    RaiseException('The verified native uninstall launcher could not be registered.');
end;

function RunManagedUninstall(CheckOnly: Boolean): Boolean;
var Command, Params, Mode, HandoffPath, HandoffHash: String;
    Code: Integer;
begin
  Result := False;
  HandoffPath := ExpandConstant('{param:AUTOCLIP-HANDOFF|}');
  HandoffHash := ExpandConstant('{param:AUTOCLIP-HANDOFF-SHA256|}');
  if not ValidUninstallHandoff(HandoffPath, HandoffHash) then Exit;
  if CheckOnly then Mode := '$true' else Mode := '$false';
  Command := '$ErrorActionPreference=''Stop'';$locks=@();try { ' +
    '$s=' + MsysPowerShellQuote(ExpandConstant('{app}')) + '; ' +
    'function Pin($name,$hash){$p=Join-Path $s $name;$c=[IO.Path]::GetFullPath($p);while($c){if((Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ''Reparse cleanup input''};$n=Split-Path -Parent $c;if($n -eq $c){break};$c=$n};$script:locks+=,[IO.File]::Open($p,''Open'',''Read'',''Read'');if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $hash){throw ''Changed cleanup helper''} }; ' +
    'Pin ''write-setup-receipt.ps1'' ''{#SetupReceiptHelperSha256}'';. (Join-Path $s ''write-setup-receipt.ps1''); ' +
    '$script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new();Assert-SetupReceiptPath $s -Protected|Out-Null; ' +
    'Pin ''uninstall-owned-release.ps1'' ''{#UninstallHelperSha256}'';Pin ''remove-owned-file.ps1'' ''{#RemovalHelperSha256}'';Pin ''run-source-build.ps1'' ''{#SourceBuildHelperSha256}'';Pin ''update.ps1'' ''{#UpdaterSha256}''; ' +
    '$id=''{#ReleaseId}'';$r=Join-Path $s (''installation-receipts/''+$id+''.json'');$a=Get-SetupReceiptFile (Join-Path $s (''installation-receipts/''+$id+''.sha256'')); ' +
    '$text=[IO.File]::ReadAllText($a.path);if($text -cnotmatch ''^[a-f0-9]{64}(\r?\n)?$''){throw ''Invalid receipt anchor''};$hash=$text.Trim();$receiptFile=Get-SetupReceiptFile $r $hash; ' +
    '$root=' + MsysPowerShellQuote(ExpandConstant('{localappdata}\AutoClip\{#ReleaseId}')) + ';$check=' + Mode + ';$handoff=' + MsysPowerShellQuote(HandoffPath) + ';$handoffHash=' + MsysPowerShellQuote(HandoffHash) + '; ' +
    '$ps=Join-Path $env:SystemRoot ''System32\WindowsPowerShell\v1.0\powershell.exe''; ' +
    '$arguments=@(''-NoProfile'',''-NonInteractive'',''-ExecutionPolicy'',''Bypass'',''-File'',(Join-Path $s ''uninstall-owned-release.ps1''),''-HandoffPath'',$handoff,''-HandoffSha256'',$handoffHash,''-ReceiptPath'',$r,''-ReceiptSha256'',$hash,''-ReleaseId'',$id,''-InstallRoot'',$root,''-ReceiptHelperSha256'',''{#SetupReceiptHelperSha256}'',''-RemovalHelperSha256'',''{#RemovalHelperSha256}'',''-SourceBuildHelperSha256'',''{#SourceBuildHelperSha256}'',''-UpdaterSha256'',''{#UpdaterSha256}'');if($check){$arguments+=,''-Preflight''}; ' +
    '$lines=@(& $ps @arguments);$code=$LASTEXITCODE;if($code -ne 0 -or $lines.Count -ne 1){throw ''Cleanup failed or invalid result framing''};$result=$lines[0]|ConvertFrom-Json; ' +
    'if($result.schema_version -isnot [int] -or $result.schema_version -ne 1){throw ''Unknown cleanup result''}; ' +
    'if($check){if($result.status -cne ''VERIFIED_UNINSTALL_PREFLIGHT'' -or $result.release_id -cne $id -or $result.install_root -ine $root -or $result.receipt_sha256 -cne $hash){throw ''Cleanup preflight differs''};exit 0};if($result.status -cnotin @(''REMOVED'',''PRESERVED'') -or $result.removed -isnot [array] -or $result.preserved -isnot [array] -or $result.selection -cnotin @(''RESET'',''PRESERVED'') -or ($result.status -ceq ''REMOVED'' -and $result.preserved.Count)){throw ''Cleanup result differs''}; ' +
    '$logs=Join-Path $s ''logs'';Assert-SetupReceiptPath $logs -Protected|Out-Null;$report=Join-Path $logs (''uninstall-''+[guid]::NewGuid().ToString(''N'')+''.json'');Write-SetupReceiptRecord $report $result|Out-Null; ' +
    'if($result.status -ceq ''PRESERVED''){exit 2};$record=Read-SetupReceiptJson $receiptFile;$d=Join-Path $logs (''uninstall-''+$id+''-''+$handoffHash);Assert-SetupReceiptPath $d|Out-Null; ' +
    'if(!(Test-Path -LiteralPath $d)){[IO.Directory]::CreateDirectory($d,(Get-Acl -LiteralPath $s))|Out-Null};Assert-SetupReceiptPath $d -Protected|Out-Null; ' +
    'foreach($entry in @(@(''write-setup-receipt.ps1'',''{#SetupReceiptHelperSha256}''),@(''remove-owned-file.ps1'',''{#RemovalHelperSha256}''))){$dest=Join-Path $d $entry[0];Assert-SetupReceiptPath $dest|Out-Null;if(!(Test-Path -LiteralPath $dest)){[IO.File]::Copy((Join-Path $s $entry[0]),$dest,$false)};if((Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne $entry[1]){throw ''Changed retirement helper preserved''}}; ' +
    '$rows=@(@{path=''installation-receipts/''+$id+''.json'';bytes=$receiptFile.bytes;sha256=$receiptFile.sha256},@{path=''installation-receipts/''+$id+''.sha256'';bytes=$a.bytes;sha256=$a.sha256}); ' +
    '$native=@($record.setup_files|Where-Object path -Match ''^unins[0-9]+\.(exe|dat|msg)$''|ForEach-Object{$_.path});Write-SetupReceiptRecord (Join-Path $d ''retirement.json'') @{schema_version=1;release_id=$id;handoff_sha256=$handoffHash;setup_root=$s;rows=$rows;native=$native}|Out-Null;exit 0 ' +
    '}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{foreach($f in $locks){$f.Dispose()};foreach($f in $script:SetupReceiptLocks){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) then begin
    if CheckOnly then Result := Code = 0
    else begin
      UninstallCleanRemoval := Code = 0;
      UninstallPreserved := Code = 2;
      Result := UninstallCleanRemoval or UninstallPreserved;
    end;
  end;
end;

function RetireUninstallEvidence: Boolean;
var Command, Params, HandoffPath, HandoffHash: String;
    Code: Integer;
begin
  Result := False;
  HandoffPath := ExpandConstant('{param:AUTOCLIP-HANDOFF|}');
  HandoffHash := ExpandConstant('{param:AUTOCLIP-HANDOFF-SHA256|}');
  if not ValidUninstallHandoff(HandoffPath, HandoffHash) then Exit;
  Command := '$ErrorActionPreference=''Stop'';$locks=@();try { $s=' + MsysPowerShellQuote(ExpandConstant('{app}')) + ';$id=''{#ReleaseId}'';$handoffHash=' + MsysPowerShellQuote(HandoffHash) + ';$d=Join-Path $s (''logs/uninstall-''+$id+''-''+$handoffHash); ' +
    'foreach($entry in @(@(''write-setup-receipt.ps1'',''{#SetupReceiptHelperSha256}''),@(''remove-owned-file.ps1'',''{#RemovalHelperSha256}''))){$p=Join-Path $d $entry[0];$c=[IO.Path]::GetFullPath($p);while($c){if((Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ''Reparse retirement input''};$n=Split-Path -Parent $c;if($n -eq $c){break};$c=$n};$locks+=,[IO.File]::Open($p,''Open'',''Read'',''Read'');if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $entry[1]){throw ''Changed retirement helper''};. $p}; ' +
    '$script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new();Assert-SetupReceiptPath $s -Protected|Out-Null;Assert-SetupReceiptPath $d -Protected|Out-Null;$record=Read-SetupReceiptJson (Get-SetupReceiptFile (Join-Path $d ''retirement.json'')); ' +
    'if($record.schema_version -ne 1 -or $record.release_id -cne $id -or $record.handoff_sha256 -cne $handoffHash -or $record.setup_root -ine $s -or @($record.rows).Count -ne 2){throw ''Retirement scope differs''}; ' +
    '$expected=@((''installation-receipts/''+$id+''.json''),(''installation-receipts/''+$id+''.sha256''));if((@($record.rows.path|Sort-Object) -join ''|'') -cne (@($expected|Sort-Object) -join ''|'')){throw ''Retirement paths differ''}; ' +
    'if(@($record.native|Where-Object{$_ -cnotmatch ''^unins[0-9]+\.(exe|dat|msg)$''}).Count -or @($record.native|Where-Object{$_ -match ''\.exe$''}).Count -ne 1 -or @($record.native|Where-Object{$_ -match ''\.dat$''}).Count -ne 1){throw ''Native retirement pair differs''}; ' +
    'foreach($name in $record.native){if(Test-Path -LiteralPath (Join-Path $s $name)){throw ''Native uninstall files remain''}}; ' +
    '$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64);try{$key=$base.OpenSubKey(''Software\Microsoft\Windows\CurrentVersion\Uninstall\{D7451842-48F4-487B-80E0-5C7E9E326342}_is1'',$false);if($key){$key.Dispose();throw ''Native uninstall registration remains''}}finally{$base.Dispose()}; ' +
    'foreach($f in $script:SetupReceiptLocks){$f.Dispose()};$script:SetupReceiptLocks.Clear();foreach($row in $record.rows){$outcome=Remove-SetupOwnedFile -Root $s -Row $row;if($outcome.status -cnotin @(''REMOVED'',''MISSING'')){throw ''Changed uninstall evidence preserved''}};exit 0 ' +
    '}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{foreach($f in $locks){$f.Dispose()};foreach($f in $script:SetupReceiptLocks){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  Result := ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) and (Code = 0);
end;

function InitializeUninstall: Boolean;
begin
  Result := RunManagedUninstall(True);
  if not Result then
    MsgBox('AutoClip uninstall ownership could not be verified. Installed files and registration were preserved. Review the receipt and pending installation before retrying.', mbError, MB_OK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    if not RunManagedUninstall(False) then begin
      MsgBox('AutoClip cleanup did not finish safely. Native uninstall was stopped; owned files and the receipt remain available for retry.', mbError, MB_OK);
      Abort;
    end;
  end;
  if CurUninstallStep = usPostUninstall then begin
    if UninstallCleanRemoval and not RetireUninstallEvidence then
      MsgBox('AutoClip was removed, but its receipt evidence could not be retired safely. Preserved evidence is under the AutoClip Setup folder.', mbInformation, MB_OK);
    if UninstallPreserved then
      MsgBox('AutoClip was uninstalled. Modified or unknown files were preserved. The installation receipt and preservation report remain under the AutoClip Setup folder and its logs.', mbInformation, MB_OK);
  end;
end;

procedure PublishUninstallAnchor(DescriptorPath: String);
var Command, Params: String;
    Code: Integer;
begin
  Command := '$ErrorActionPreference=''Stop'';$locks=@();try { ' +
    '$s=' + MsysPowerShellQuote(ExpandConstant('{app}')) + ';$h=Join-Path $s ''write-setup-receipt.ps1''; ' +
    '$locks+=,[IO.File]::Open($h,''Open'',''Read'',''Read'');if((Get-FileHash -LiteralPath $h).Hash.ToLowerInvariant() -cne ''{#SetupReceiptHelperSha256}''){throw ''Changed receipt helper''};. $h; ' +
    '$script:SetupReceiptLocks=[Collections.Generic.List[IO.FileStream]]::new();Assert-SetupReceiptPath $s -Protected|Out-Null; ' +
    '$descriptor=Read-SetupReceiptJson (Get-SetupReceiptFile ' + MsysPowerShellQuote(DescriptorPath) + ');$r=Join-Path $s ''installation-receipts\{#ReleaseId}.json''; ' +
    'if($descriptor.path -ine $r -or $descriptor.sha256 -cnotmatch ''^[a-f0-9]{64}$''){throw ''Final receipt descriptor differs''};$f=Get-SetupReceiptFile $r $descriptor.sha256;if($f.bytes -ne $descriptor.bytes){throw ''Final receipt size differs''}; ' +
    '$record=Read-SetupReceiptJson $f;if($record.status -cne ''COMPLETE'' -or $record.context.release_id -cne ''{#ReleaseId}'' -or $record.setup_root -ine $s){throw ''Final receipt identity differs''}; ' +
    '$anchor=Join-Path $s ''installation-receipts\{#ReleaseId}.sha256'';Assert-SetupReceiptPath $anchor|Out-Null; ' +
    'if(Test-Path -LiteralPath $anchor){$old=Get-SetupReceiptFile $anchor;if([IO.File]::ReadAllText($old.path) -cne $f.sha256){throw ''Changed receipt anchor preserved''}}else{ ' +
    '$t=Join-Path (Split-Path -Parent $anchor) (''.anchor-''+[guid]::NewGuid().ToString(''N'')+''.tmp'');$b=[Text.Encoding]::ASCII.GetBytes($f.sha256);$o=[IO.File]::Open($t,''CreateNew'',''Write'',''None'');try{$o.Write($b,0,$b.Length);$o.Flush($true)}finally{$o.Dispose()};try{[IO.File]::Move($t,$anchor)}finally{if([IO.File]::Exists($t)){[IO.File]::Delete($t)}} };exit 0 ' +
    '}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{foreach($f in $locks){$f.Dispose()};foreach($f in $script:SetupReceiptLocks){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) or (Code <> 0) then
    RaiseException('The final uninstall receipt anchor could not be published safely.');
end;

procedure PrepareNativeShortcutDirectory;
var Command, Params: String;
    Code: Integer;
begin
  VerifyHelper('run-source-build.ps1', '{#SourceBuildHelperSha256}');
  Command := '$ErrorActionPreference=''Stop'';$f=$null;try { $h=' + MsysPowerShellQuote(ExpandConstant('{tmp}\run-source-build.ps1')) + '; ' +
    '$f=[IO.File]::Open($h,''Open'',''Read'',''Read'');if((Get-FileHash -LiteralPath $h).Hash.ToLowerInvariant() -cne ''{#SourceBuildHelperSha256}''){throw ''Changed storage helper''}; ' +
    '$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($h),[ref]$tokens,[ref]$errors);if($errors.Count){throw ''Storage helper does not parse''}; ' +
    'foreach($name in @(''Assert-BuildPath'',''New-BuildDirectoryAcl'')){$nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true));if($nodes.Count -ne 1){throw ''Storage helper function differs''};. ([scriptblock]::Create($nodes[0].Extent.Text))}; ' +
    '$p=' + MsysPowerShellQuote(ExpandConstant('{group}')) + ';Assert-BuildPath $p|Out-Null; ' +
    'if(Test-Path -LiteralPath $p){if(!(Test-Path -LiteralPath $p -PathType Container)){throw ''Shortcut scope is not a directory''};Assert-BuildPath $p|Out-Null}else{[IO.Directory]::CreateDirectory($p,(New-BuildDirectoryAcl))|Out-Null;Assert-BuildPath $p -Protected|Out-Null};exit 0 ' +
    '}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{if($f){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) or (Code <> 0) then
    RaiseException('The native shortcut directory is not a trusted AutoClip scope.');
end;

procedure InitializeManagedSelection(const Mode, InputPath: String);
var Command, Params: String;
    Code: Integer;
begin
  Command := '$ErrorActionPreference=''Stop'';$f=$null;try{$h=' +
    MsysPowerShellQuote(ExpandConstant('{app}\initialize-selection.ps1')) +
    ';$f=[IO.File]::Open($h,''Open'',''Read'',''Read'');if((Get-FileHash -LiteralPath $h).Hash.ToLowerInvariant() -cne ''{#InitialSelectionSha256}''){throw ''Changed initial selection helper''};' +
    '$a=@{BaseRoot=' + MsysPowerShellQuote(ExpandConstant('{localappdata}\AutoClip')) +
    ';ReleaseId=''{#ReleaseId}'';ReceiptHelperSha256=''{#SetupReceiptHelperSha256}'';UpdaterSha256=''{#AppUpdaterSha256}'';' +
    'NativeSelectionPath=' + MsysPowerShellQuote(SetupSelectionPath) + ';NativeSelectionSha256=' + MsysPowerShellQuote(SetupSelectionHash) + '};';
  if Mode = 'PrepareLaunchers' then
    Command := Command + '$a.PrepareLaunchers=$true;$a.RequestPath=' + MsysPowerShellQuote(InputPath) + ';$a.RequestSha256=' + MsysPowerShellQuote(Lowercase(GetSHA256OfFile(InputPath))) + ';'
  else
    Command := Command + '$a.Activate=$true;$a.ReceiptPath=' + MsysPowerShellQuote(InputPath) + ';$a.ReceiptSha256=' + MsysPowerShellQuote(Lowercase(GetSHA256OfFile(InputPath))) + ';';
  Command := Command + '& $h @a;exit $LASTEXITCODE}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 23}finally{if($f){$f.Dispose()}}';
  Params := '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  if not ExecAndLogOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, nil) or (Code <> 0) then
    RaiseException('AutoClip could not safely prepare or activate the verified selection. Existing state and unknown files were preserved.');
end;

procedure FinalizeSetupReceipt;
var
  RequestPath, Json, HelperRows, Profile, Params, ProcessError, Output, Errors: String;
  SourceSize: Integer;
  Lines: TArrayOfString;
  Code: Integer;
begin
  VerifyHelper('write-setup-receipt.ps1', '{#SetupReceiptHelperSha256}');
  VerifyHelper('run-source-build.ps1', '{#SourceBuildHelperSha256}');
  if SourceHandoffSha256 = '' then RaiseException('The verified source handoff is missing.');
  RegisterManagedUninstall;
  if ProfilePage.Values[1] then Profile := 'nvidia' else Profile := 'cpu';
  RequestPath := BuildAttemptDirectory + '\final-request.json';
  if FileExists(RequestPath) then RaiseException('The finalization request already exists; it was preserved.');
  if not FileSize(ExpandConstant('{srcexe}'), SourceSize) then RaiseException('Could not read the held installer size.');
  HelperRows := '{#SetupHelperRows}';
  { The original source is held by native admission until finalization finishes. }
  Delete(HelperRows, Length(HelperRows), 1);
  HelperRows := HelperRows + ',{"path":"AutoClip-Maintenance.exe","bytes":' +
    IntToStr(SourceSize) + ',"sha256":' +
    BuildJsonString(Lowercase(GetSHA256OfFile(ExpandConstant('{srcexe}')))) + '}]';
  Json := '{"schema_version":1,"context":{' +
    '"install_root":' + BuildJsonString(ReleaseRoot) +
    ',"release_id":"{#ReleaseId}","profile":' + BuildJsonString(Profile) +
    ',"archive_sha256":"{#ReleaseSha256}","release_manifest_sha256":"{#ReleaseManifestSha256}"' +
    ',"dependency_manifest_sha256":"{#DependencyManifestSha256}","bootstrap_sha256":"{#BootstrapSha256}"' +
    ',"source_helper_sha256":"{#SetupReceiptHelperSha256}","health_helper_sha256":"{#AppHealthHelperSha256}"},' +
    '"handoff_sha256":' + BuildJsonString(SourceHandoffSha256) +
    ',"setup_path":' + BuildJsonString(ExpandConstant('{srcexe}')) +
    ',"setup_sha256":' + BuildJsonString(Lowercase(GetSHA256OfFile(ExpandConstant('{srcexe}')))) +
    ',"source_build_helper_sha256":"{#SourceBuildHelperSha256}","notices":{#SetupNoticeRows},"helpers":' + HelperRows +
    ',"native_uninstaller":' + BuildJsonString(ExpandConstant('{uninstallexe}')) +
    ',"uninstall_command":' + BuildJsonString(BuildUninstallCommand(False)) +
    ',"quiet_uninstall_command":' + BuildJsonString(BuildUninstallCommand(True)) +
    ',"native_shortcut_path":' + BuildJsonString(ExpandConstant('{group}\AutoClip.lnk')) +
    ',"native_shortcut_sha256":' + BuildJsonString(Lowercase(GetSHA256OfFile(ExpandConstant('{group}\AutoClip.lnk')))) + '}';
  SetArrayLength(Lines, 1); Lines[0] := Json;
  if not SaveStringsToUTF8File(RequestPath, Lines, False) then RaiseException('Could not write the finalization request.');
  ProcessError := '';
  try
    try
      DownloadPage.SetText('Preparing AutoClip launchers', 'Checking the managed shortcuts and selected runtime.');
      DownloadPage.Show;
      DownloadPage.Animate;
      InitializeManagedSelection('PrepareLaunchers', RequestPath);
      Params := AddQuotes(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) +
        ' -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ' +
        AddQuotes(ExpandConstant('{tmp}\write-setup-receipt.ps1')) +
        ' -Finalize -RequestPath ' + AddQuotes(RequestPath) +
        ' -RequestSha256 ' + Lowercase(GetSHA256OfFile(RequestPath));
      DownloadPage.SetText('Recording the verified installation', 'Checking installed files and native setup records.');
      if not ExecHiddenWorker(Params, Code, Output, Errors) then
        RaiseException('Installation receipt worker could not complete. Logs: ' + BuildAttemptDirectory);
      if HiddenWorkerDisplayError <> '' then RaiseException(HiddenWorkerDisplayError);
      Log('Setup finalization exit: ' + IntToStr(Code));
      Log(Output); Log(Errors);
      if (Code <> 0) or not FileExists(RequestPath + '.receipt.json') then
        RaiseException('Installation receipt publication failed. Logs: ' + BuildAttemptDirectory);
      DownloadPage.SetText('Verifying the uninstall receipt', 'Publishing the exact installation receipt anchor.');
      DownloadPage.Animate;
      PublishUninstallAnchor(RequestPath + '.receipt.json');
      DownloadPage.SetText('Activating the verified AutoClip selection', 'Selecting the verified runtime and application.');
      DownloadPage.Animate;
      InitializeManagedSelection('Activate', ExpandConstant('{app}\installation-receipts\{#ReleaseId}.json'));
      SetupReceiptComplete := True;
    except
      { Clear the pending exception before nested cleanup handlers run. }
      ProcessError := GetExceptionMessage;
    end;
  finally
    try
      DownloadPage.Hide;
    except
      if ProcessError = '' then ProcessError := GetExceptionMessage;
    end;
  end;
  if ProcessError <> '' then RaiseException(ProcessError);
end;

function CanLaunchAutoClip: Boolean;
begin
  Result := (IsInstallMode and SetupReceiptComplete and (SetupReceiptError = '')) or
    (not IsInstallMode and OperationDone and OperationSucceeded);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if not IsInstallMode then Exit;
  if CurStep = ssInstall then PrepareNativeShortcutDirectory;
  if CurStep = ssPostInstall then begin
    try
      FinalizeSetupReceipt;
    except
      SetupReceiptComplete := False;
      SetupReceiptError := GetExceptionMessage;
      Log('AutoClip setup incomplete: ' + SetupReceiptError);
      MsgBox(SetupReceiptError + #13#10 + #13#10 +
        'The built runtime and native setup files were preserved. Setup did not complete verified activation.', mbError, MB_OK);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and not IsInstallMode then begin
    if OperationSucceeded then begin
      WizardForm.FinishedHeadingLabel.Caption := 'AutoClip maintenance completed';
      WizardForm.FinishedLabel.Caption := 'The verified operation completed. You can open AutoClip below.';
    end else begin
      WizardForm.FinishedHeadingLabel.Caption := 'AutoClip maintenance failed';
      WizardForm.FinishedLabel.Caption := 'The prior selection was preserved. See the maintenance log in ' + ExpandConstant('{localappdata}\AutoClip\Setup\logs') + '.';
    end;
    Exit;
  end;
  if (CurPageID = wpFinished) and (SetupReceiptError <> '') then begin
    WizardForm.FinishedHeadingLabel.Caption := 'AutoClip setup is incomplete';
    WizardForm.FinishedLabel.Caption := SetupReceiptError + #13#10 + #13#10 +
      'The built runtime and native setup files were preserved. Setup did not complete verified activation.';
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  if not IsInstallMode then begin
    if OperationDone and OperationSucceeded then Result := 0 else Result := 1;
  end else if SetupReceiptComplete then Result := 0 else Result := 20;
end;

procedure DeinitializeSetup;
begin
  ReleaseNativeSetupInputs;
  if SetupSelectionHandle <> 0 then begin
    if SetupSelectionThread <> SetupNativeThread then RaiseException('Native selection owner thread changed.');
    if not SetupSelectionRelease(SetupSelectionHandle) then RaiseException('Native selection ownership could not be released.');
    SetupSelectionClose(SetupSelectionHandle); SetupSelectionHandle := 0;
  end;
end;
