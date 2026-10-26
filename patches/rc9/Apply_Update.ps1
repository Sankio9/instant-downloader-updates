# Applies code-only updates from a verified staging folder. Never touches downloads or .auth.
param([ValidateSet('Install','Rollback')][string]$Mode='Install',[string]$AppRoot,[string]$StagePath,[string]$NewVersion,[string]$BackupPath,[switch]$Quiet,[string]$StatusPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$allowed=@('DIAGNOSTIC_INSTANT_DOWNLOADER.cmd','Diagnostics.ps1','INSTALL_INSTANT_DOWNLOADER.cmd','Install_Instant_Downloader.ps1','Preflight.ps1','README_RO.txt','SHA256SUMS.txt','START_INSTANT_DOWNLOADER.cmd','Instant_Downloader.ps1','bridge.mjs','login_skool.mjs','audit_archive.cjs','lesson_documents.cjs','selection.cjs','check_update_notice.cjs','package.json','patch_progress.cjs','supervisor.cjs','Update_Instant_Downloader.ps1','Apply_Update.ps1','test_local.cjs','test_upgrade.cjs','test_v16.cjs','test_lesson_documents.cjs','ARCHITECTURA_RO.txt','test_updates.py','UPDATE_MANIFEST_EXEMPLU.json')
function Quiet-Report([string]$status,[string]$message){
  if(-not $StatusPath){return}
  $state=@{status=$status;message=$message;time=(Get-Date).ToString('o');version=$NewVersion}
  $tmp=$StatusPath+'.tmp.'+[guid]::NewGuid().ToString('N')
  [IO.File]::WriteAllText($tmp,($state | ConvertTo-Json -Compress -Depth 6),[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination $StatusPath -Force
}
function Report([string]$text){
  if($Quiet){Quiet-Report $(if($Mode -eq 'Rollback'){'restored'}else{'installed'}) $text;return}
  [void][Windows.Forms.MessageBox]::Show($text,'Instant Downloader - Update')
}
function Safe-Set-Version([string]$to){
  $cfgPath=Join-Path $AppRoot 'config.json'
  $cfg=Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $cfg.version=$to
  [IO.File]::WriteAllText($cfgPath,($cfg|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
function Relaunch(){
  $gui=Join-Path $AppRoot 'Instant_Downloader.ps1'
  if(Test-Path -LiteralPath $gui){
    $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$gui+'"') -WorkingDirectory $AppRoot | Out-Null
  }
}
try{
  if(-not [IO.Path]::IsPathRooted($AppRoot)){throw 'Folder aplicatie invalid.'}
  $AppRoot=[IO.Path]::GetFullPath($AppRoot)
  if(-not (Test-Path -LiteralPath (Join-Path $AppRoot 'config.json'))){throw 'Aplicatia nu e instalata.'}
  $cfg=Get-Content -LiteralPath (Join-Path $AppRoot 'config.json') -Raw | ConvertFrom-Json
  $backupBase=Join-Path ([string]$cfg.tempPath) '_updates\backups'
  if($Mode -eq 'Install'){
    if($NewVersion -notmatch '^\d+\.\d+\.\d+(-rc\.\d+)?$'){throw 'Versiunea release este invalida.'}
    if(-not (Test-Path -LiteralPath (Join-Path $StagePath 'package.json'))){throw 'Pachetul staging lipseste.'}
    $pkg=Get-Content -LiteralPath (Join-Path $StagePath 'package.json') -Raw | ConvertFrom-Json
    if([string]$pkg.version -ne $NewVersion){throw 'Pachetul nu corespunde versiunii validate.'}
    [void][IO.Directory]::CreateDirectory($backupBase)
    $backup=Join-Path $backupBase ('backup_'+(Get-Date).ToString('yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($backup)
    $files=@(Get-ChildItem -LiteralPath $StagePath -File | Where-Object {$_.Name -in $allowed} | ForEach-Object {$_.Name})
    foreach($need in @('Instant_Downloader.ps1','Update_Instant_Downloader.ps1','Apply_Update.ps1','package.json')){if($need -notin $files){throw "Fisier esential lipsa: $need"}}
    $record=@{previous_version=[string]$cfg.version;new_version=$NewVersion;created_at=(Get-Date).ToString('o');files=@()}
    foreach($f in $files){
      $existing=Test-Path -LiteralPath (Join-Path $AppRoot $f)
      $record.files+=@{name=$f;existed=[bool]$existing}
      if($existing){Copy-Item -LiteralPath (Join-Path $AppRoot $f) -Destination (Join-Path $backup $f) -ErrorAction Stop}
    }
    [IO.File]::WriteAllText((Join-Path $backup 'record.json'),($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    try{
      foreach($f in $files){Copy-Item -LiteralPath (Join-Path $StagePath $f) -Destination (Join-Path $AppRoot $f) -Force -ErrorAction Stop}
      Safe-Set-Version $NewVersion
    }catch{
      $err=$_
      foreach($x in $record.files){
        if($x.existed){Copy-Item -LiteralPath (Join-Path $backup $x.name) -Destination (Join-Path $AppRoot $x.name) -Force -ErrorAction SilentlyContinue}
        else{Remove-Item -LiteralPath (Join-Path $AppRoot $x.name) -Force -ErrorAction SilentlyContinue}
      }
      throw "Actualizare anulata; s-a incercat rollback automat. Cauza: $err"
    }
    Report ("Actualizare instalata: $NewVersion`r`nBackup cod local: $backup`r`nVideoclipurile si sesiunea au ramas nemodificate.")
  }else{
    $resolvedBase=[IO.Path]::GetFullPath($backupBase).TrimEnd('\')+'\'
    $resolvedBackup=[IO.Path]::GetFullPath($BackupPath).TrimEnd('\')+'\'
    if(-not $resolvedBackup.StartsWith($resolvedBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Folderul de rollback este in afara directorului de backup.'}
    $recordFile=Join-Path $BackupPath 'record.json'
    if(-not (Test-Path -LiteralPath $recordFile)){throw 'Manifestul backup nu exista.'}
    $rec=Get-Content -LiteralPath $recordFile -Raw | ConvertFrom-Json
    foreach($f in $rec.files){
      if([string]$f.name -notin $allowed){throw 'Backup contine un nume de fisier neaprobat.'}
      if($f.existed -and -not (Test-Path -LiteralPath (Join-Path $BackupPath $f.name))){throw "Backup incomplet: $($f.name)"}
    }
    foreach($f in $rec.files){
      if($f.existed){Copy-Item -LiteralPath (Join-Path $BackupPath $f.name) -Destination (Join-Path $AppRoot $f.name) -Force -ErrorAction Stop}
      else{Remove-Item -LiteralPath (Join-Path $AppRoot $f.name) -Force -ErrorAction SilentlyContinue}
    }
    Safe-Set-Version ([string]$rec.previous_version)
    Report ('Restaurat codul versiunii '+[string]$rec.previous_version+'. Datele personale si cursurile nu au fost schimbate.')
  }
  if(-not $Quiet){Relaunch}
}catch{
  if($Quiet){Quiet-Report 'error' ('Update failed: '+$_)}else{Report ('Eroare actualizare: '+$_);Relaunch}
  exit 1
}
