var
  ActionPage: TInputOptionWizardPage;
  ProgressPage: TOutputMarqueeProgressWizardPage;
  OperationDone, OperationSucceeded, DisplayFailed, ForcedMaintenance: Boolean;

function IsInstallMode: Boolean;
begin
  Result := (ActionPage = nil) or (ActionPage.Values[0] and not ForcedMaintenance);
end;

function PSQuote(const Value: String): String;
var Escaped: String;
begin
  Escaped := Value;
  StringChangeEx(Escaped, '''', '''''', True);
  Result := '''' + Escaped + '''';
end;

procedure MaintenanceOutput(const S: String; const Error, FirstLine: Boolean);
begin
  { Display errors must never abandon the owned native worker. }
  try
    Log(S);
    ProgressPage.SetText('Maintaining AutoClip', Copy(S, 1, 240));
    ProgressPage.Animate;
  except
    DisplayFailed := True;
  end;
end;

procedure RunMaintenance;
var
  Worker, Command, Params, Fixture, FixturePin: String;
  Code: Integer;
  Started: Boolean;
begin
  ExtractTemporaryFile('run-maintenance.ps1');
  Worker := ExpandConstant('{tmp}\run-maintenance.ps1');
  if Lowercase(GetSHA256OfFile(Worker)) <> '{#MaintenanceWorkerSha256}' then
    RaiseException('The maintenance worker differs from its compiled identity.');
  Command := '$ErrorActionPreference=''Stop'';$h=$null;try{' +
    '$w=' + PSQuote(Worker) + ';$h=[IO.File]::Open($w,''Open'',''Read'',''Read'');' +
    'if((Get-FileHash -LiteralPath $w).Hash.ToLowerInvariant() -cne ''{#MaintenanceWorkerSha256}''){throw ''Changed maintenance worker''};' +
    '$base=Join-Path $env:LOCALAPPDATA ''AutoClip'';$r=Join-Path $base ''Setup\installation-receipts\{#ReleaseId}.json'';' +
    '$a=@{BaseRoot=$base;ReleaseId=''{#ReleaseId}'';ReceiptPath=$r;ReceiptSha256=[IO.File]::ReadAllText(($r -replace ''\.json$'',''.sha256''));' +
    'ReceiptHelperSha256=''{#SetupReceiptHelperSha256}'';OwnershipHelperSha256=''{#UninstallHelperSha256}'';UpdaterSha256=''{#AppUpdaterSha256}'';' +
    'BootstrapSha256=''{#BootstrapSha256}'';DependencyManifestSha256=''{#DependencyManifestSha256}''};';
  if ActionPage.Values[2] then Command := Command + '$a.Rollback=$true;';
  { First-party test fixtures are pinned CLI inputs, never editable UI commands. }
  Fixture := ExpandConstant('{param:AUTOCLIP-TEST-MANIFEST|}');
  FixturePin := ExpandConstant('{param:AUTOCLIP-TEST-MANIFEST-SHA256|}');
  if Fixture <> '' then Command := Command + '$a.ManifestPath=' + PSQuote(Fixture) + ';$a.ManifestSha256=' + PSQuote(FixturePin) + ';';
  Fixture := ExpandConstant('{param:AUTOCLIP-TEST-WHEEL|}');
  FixturePin := ExpandConstant('{param:AUTOCLIP-TEST-WHEEL-SHA256|}');
  if Fixture <> '' then Command := Command + '$a.WheelPath=' + PSQuote(Fixture) + ';$a.WheelSha256=' + PSQuote(FixturePin) + ';';
  Command := Command + '& $w @a;exit $LASTEXITCODE}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}finally{if($h){$h.Dispose()}}';
  Params := '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -Command ' + AddQuotes(Command);
  ProgressPage.SetText('Maintaining AutoClip', 'Verifying the installed runtime and application.');
  ProgressPage.Show;
  WizardForm.CancelButton.Enabled := False;
  DisplayFailed := False;
  try
    { Inno drains stdout/stderr and waits for the original process handle. }
    Started := ExecAndLogOutput(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code, @MaintenanceOutput);
    OperationSucceeded := Started and (Code = 0);
  finally
    ProgressPage.Hide;
    WizardForm.CancelButton.Enabled := True;
  end;
  OperationDone := True;
  if DisplayFailed then Log('Some progress frames could not be displayed; the worker exit was still observed.');
end;

