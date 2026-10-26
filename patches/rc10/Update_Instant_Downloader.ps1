param([switch]$AutoCheck,[switch]$Headless,[ValidateSet('Check','Install','Rollback')][string]$Action='Check',[string]$StatusPath,[string]$Source,[string]$BackupPath)
# Instant Downloader 1.6 - updater optional, local / HTTPS signed-by-hash releases.
# No telemetry. Never transfers browser sessions, personal files, configs or download logs.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:AppRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath=Join-Path $script:AppRoot 'config.json'
if(-not (Test-Path -LiteralPath $script:ConfigPath)){[void][Windows.Forms.MessageBox]::Show('Instaleaza aplicatia inainte de a folosi Update.');exit 1}
$script:cfg=Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:currentVersion=[string]$script:cfg.version
$script:release=$null;$script:manifestLocation='';$script:canInstall=$false
$script:base=Join-Path ([string]$script:cfg.tempPath) '_updates'
[void][IO.Directory]::CreateDirectory($script:base)

function Version-Compare([string]$a,[string]$b){
  $rx='^(\d+)\.(\d+)\.(\d+)(?:-rc\.(\d+))?$'
  $m1=[regex]::Match($a,$rx);$m2=[regex]::Match($b,$rx)
  if(-not $m1.Success -or -not $m2.Success){throw "Versiune invalida: $a / $b"}
  for($i=1;$i -le 3;$i++){$x=[int]$m1.Groups[$i].Value;$y=[int]$m2.Groups[$i].Value;if($x -gt $y){return 1};if($x -lt $y){return -1}}
  $aRc=$m1.Groups[4].Success;$bRc=$m2.Groups[4].Success
  if(-not $aRc -and $bRc){return 1};if($aRc -and -not $bRc){return -1}
  if($aRc -and $bRc){$x=[int]$m1.Groups[4].Value;$y=[int]$m2.Groups[4].Value;if($x -gt $y){return 1};if($x -lt $y){return -1}}
  return 0
}
function UiMsg($text,$title='Instant Downloader Updates') {[void][Windows.Forms.MessageBox]::Show([string]$text,$title)}
function Display($text){
  if($Headless){Write-WorkerState 'working' ([string]$text);return}
  $script:statusBox.AppendText('['+(Get-Date).ToString('HH:mm:ss')+'] '+$text+"`r`n")
  $script:statusBox.SelectionStart=$script:statusBox.TextLength
  $script:statusBox.ScrollToCaret()
  [Windows.Forms.Application]::DoEvents()
}
function Source-Text([string]$src){
  if($src -match '^https://'){
    $result=Invoke-WebRequest -Uri $src -UseBasicParsing -TimeoutSec 45 -MaximumRedirection 5
    if($result.BaseResponse.ResponseUri.Scheme -ne 'https'){throw 'Redirectionarea manifestului trebuie sa ramana HTTPS.'}
    return [string]$result.Content
  }
  if($src -match '^https?://'){throw 'Manifestul remote necesita HTTPS.'}
  if(-not (Test-Path -LiteralPath $src -PathType Leaf)){throw 'Nu gasesc manifestul. Alege un fisier JSON local sau un link HTTPS.'}
  return [IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)
}
function Load-Release([string]$src){
  $obj=(Source-Text $src)|ConvertFrom-Json
  $v=[string]$obj.version;$channel=[string]$obj.channel;$hash=[string]$obj.sha256
  if($v -notmatch '^\d+\.\d+\.\d+(-rc\.\d+)?$'){throw 'Versiune release invalida.'}
  if($channel -notin @('stable','rc')){throw 'Canal release invalid (stable sau rc).'}
  if($hash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Manifestul nu are SHA256 valid.'}
  if($channel -eq 'rc' -and [string]$script:cfg.updateChannel -ne 'rc'){throw 'Release-ul RC nu este acceptat pe canalul Stable.'}
  if((Version-Compare $v $script:currentVersion) -le 0){throw "Nu exista update nou. Instalat: $script:currentVersion, manifest: $v"}
  $remote=($src -match '^https://')
  $url=[string]$obj.package_url;$file=[string]$obj.package_path
  if($remote -and ($url -notmatch '^https://')){throw 'Manifestul HTTPS trebuie sa contina package_url HTTPS.'}
  if($url -and $url -notmatch '^https://'){throw 'Pachetele remote necesita HTTPS.'}
  if(-not $url){
    if(-not $file){throw 'Manifestul nu contine package_url sau package_path.'}
    if($remote){throw 'Manifestul remote nu poate referi un fisier local.'}
    if(-not [IO.Path]::IsPathRooted($file)){$file=Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $src).Path) $file}
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw 'Pachetul ZIP nu exista in locatia din manifest.'}
  }
  $notes=[string]$obj.notes
  return @{version=$v;channel=$channel;sha256=$hash.ToLowerInvariant();url=$url;file=$file;notes=$notes}
}
function Check-Dependencies($stagePath){
  $old=(Get-Content -LiteralPath (Join-Path $script:AppRoot 'package.json') -Raw | ConvertFrom-Json).dependencies
  $new=(Get-Content -LiteralPath (Join-Path $stagePath 'package.json') -Raw | ConvertFrom-Json).dependencies
  $names=@($old.PSObject.Properties.Name)+@($new.PSObject.Properties.Name) | Sort-Object -Unique
  foreach($key in $names){if([string]$old.$key -ne [string]$new.$key){throw 'Aceasta actualizare schimba dependentele Node.js. Ruleaza installerul complet, pentru siguranta.'}}
}
function Extract-Release([string]$zipPath,[string]$dst){
  $allow=@('DIAGNOSTIC_INSTANT_DOWNLOADER.cmd','Diagnostics.ps1','INSTALL_INSTANT_DOWNLOADER.cmd','Install_Instant_Downloader.ps1','Preflight.ps1','README_RO.txt','SHA256SUMS.txt','START_INSTANT_DOWNLOADER.cmd','Instant_Downloader.ps1','bridge.mjs','audit_archive.cjs','lesson_documents.cjs','lesson_ui.cjs','selection.cjs','check_update_notice.cjs','package.json','patch_progress.cjs','supervisor.cjs','Update_Instant_Downloader.ps1','Apply_Update.ps1','test_local.cjs','test_upgrade.cjs','test_v16.cjs','test_v17.cjs','test_audit.cjs','test_lesson_documents.cjs','test_lesson_ui.cjs','ARCHITECTURA_RO.txt','test_updates.py','UPDATE_MANIFEST_EXEMPLU.json')
  $names=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $found=@()
  $zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
  try{
    foreach($entry in $zip.Entries){
      if($entry.Name -eq ''){continue}
      $raw=[string]$entry.FullName
      if($raw.Contains('\') -or $raw.Contains('..') -or $raw.Contains(':') -or $raw.StartsWith('/')){throw 'ZIP invalid: cale nesigura.'}
      $parts=@($raw.Split('/'))
      if($parts.Count -gt 2 -or $parts.Count -eq 0 -or $parts[-1] -notin $allow){throw 'ZIP contine un fisier neaprobat. Actualizare anulata.'}
      $name=[string]$parts[-1]
      if(-not $names.Add($name)){throw 'ZIP contine fisiere duplicate.'}
      $found+=@{entry=$entry;name=$name}
    }
    foreach($required in @('Instant_Downloader.ps1','Update_Instant_Downloader.ps1','Apply_Update.ps1','bridge.mjs','audit_archive.cjs','selection.cjs','check_update_notice.cjs','package.json','supervisor.cjs','patch_progress.cjs','INSTALL_INSTANT_DOWNLOADER.cmd','Install_Instant_Downloader.ps1')){
      if(-not $names.Contains($required)){throw "Pachet incomplet: lipseste $required"}
    }
    [void][IO.Directory]::CreateDirectory($dst)
    foreach($item in $found){
      $target=Join-Path $dst $item.name
      $s=$item.entry.Open();$o=[IO.File]::Create($target)
      try{$s.CopyTo($o)}finally{$o.Dispose();$s.Dispose()}
    }
  }finally{$zip.Dispose()}
}
function Prepare-Update($release){
  $id=[guid]::NewGuid().ToString('N')
  $work=Join-Path $script:base ('stage_'+$id)
  [void][IO.Directory]::CreateDirectory($work)
  $zip=Join-Path $work 'release.zip';$payload=Join-Path $work 'app'
  Display 'Pregatesc pachetul; nu citesc datele de autentificare.'
  if($release.url){
    Display 'Descarc ZIP prin HTTPS...'
    $response=Invoke-WebRequest -Uri $release.url -OutFile $zip -UseBasicParsing -TimeoutSec 180 -MaximumRedirection 5 -PassThru
    if($response.BaseResponse.ResponseUri.Scheme -ne 'https'){throw 'Descarcarea a redirectionat catre un protocol nesecurizat.'}
  }else{Copy-Item -LiteralPath $release.file -Destination $zip -Force}
  $actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -ne $release.sha256){throw 'SHA256 nu coincide! Pachetul nu va fi instalat.'}
  Display 'Checksum SHA-256 valid.'
  Extract-Release $zip $payload
  $newPkg=Get-Content -LiteralPath (Join-Path $payload 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if([string]$newPkg.version -ne $release.version){throw 'Versiunea pachetului nu coincide cu manifestul.'}
  Check-Dependencies $payload
  Display 'Pachet valid; fisierele tehnice sunt pregatite.'
  return $payload
}
function Launch-Apply([string]$mode,[string]$stage,[string]$version,[string]$backup=''){
  $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $apply=if($mode -eq 'Install'){Join-Path $stage 'Apply_Update.ps1'}else{Join-Path $script:AppRoot 'Apply_Update.ps1'}
  $args='-NoProfile -ExecutionPolicy Bypass -File "'+$apply+'" -Mode '+$mode+' -AppRoot "'+$script:AppRoot+'"'
  if($mode -eq 'Install'){$args+=' -StagePath "'+$stage+'" -NewVersion "'+$version+'"'}
  else{$args+=' -BackupPath "'+$backup+'"'}
  Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $script:AppRoot | Out-Null
}


# Headless mode: the running main window owns the UI; never open an updater window.
function W([string]$english,[string]$romanian){if([string]$script:cfg.language -eq 'ro'){return $romanian};return $english}
function Write-WorkerState([string]$state,[string]$message,[hashtable]$more=@{}){
  if([string]::IsNullOrWhiteSpace($StatusPath)){return}
  $data=@{status=$state;message=$message;time=(Get-Date).ToString('o')}
  foreach($key in $more.Keys){$data[$key]=$more[$key]}
  $tmp=$StatusPath+'.tmp.'+[guid]::NewGuid().ToString('N')
  [IO.File]::WriteAllText($tmp,($data | ConvertTo-Json -Compress -Depth 7),[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination $StatusPath -Force
}
if($Headless){
  try{
    if([string]::IsNullOrWhiteSpace($StatusPath)){throw 'Missing status path.'}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $StatusPath))
    if($Action -eq 'Check'){
      Write-WorkerState 'working' (W 'Checking available releases...' 'Verific versiunile disponibile...')
      $sources=@([string]$script:cfg.updateManifestSource,[string]$script:cfg.updateManifestFallback) | Where-Object {$_ -and $_.Trim()} | Select-Object -Unique
      if($sources.Count -eq 0){Write-WorkerState 'unconfigured' (W 'No update source configured. A public HTTPS manifest is required.' 'Sursa actualizărilor nu este configurată. Este necesar un manifest HTTPS public.');exit 0}
      $latest=$null;$selected='';$success=0;$errors=@()
      foreach($candidate in $sources){
        try{
          $candidate=[string]$candidate
          $data=Load-Release $candidate
          $success++
          if(-not $latest -or (Version-Compare $data.version $latest.version) -gt 0){$latest=$data;$selected=$candidate}
        }catch{
          $reason=[string]$_.Exception.Message
          if($reason -like '*Nu exista update nou*'){$success++}
          else{$errors+=$reason}
        }
      }
      if($latest){Write-WorkerState 'available' ((W 'Update available: ' 'Actualizare disponibilă: ')+$latest.version) @{version=$latest.version;source=$selected;notes=$latest.notes};exit 0}
      if($success -gt 0){Write-WorkerState 'up_to_date' ((W 'Latest installed: ' 'Ai deja cea mai nouă versiune: ')+$script:currentVersion);exit 0}
      Write-WorkerState 'error' ((W 'Update check failed: ' 'Verificarea actualizării a eșuat: ')+($errors -join ' | '));exit 1
    }
    if($Action -eq 'Install'){
      if([string]::IsNullOrWhiteSpace($Source)){throw 'No selected release source.'}
      Write-WorkerState 'working' (W 'Validating release manifest...' 'Validez manifestul versiunii...')
      $candidate=Load-Release $Source
      $payload=Prepare-Update $candidate
      Write-WorkerState 'working' (W 'Installing verified update. Creating rollback backup...' 'Instalez actualizarea verificată și creez copia de rezervă...')
      $apply=Join-Path $payload 'Apply_Update.ps1'
      & $apply -Mode Install -AppRoot $script:AppRoot -StagePath $payload -NewVersion $candidate.version -Quiet -StatusPath $StatusPath
      # Apply_Update.ps1 creates the final "installed" or "error" state.
      exit 0
    }
    if($Action -eq 'Rollback'){
      if([string]::IsNullOrWhiteSpace($BackupPath)){throw 'Backup path is missing.'}
      Write-WorkerState 'working' (W 'Restoring previous application version...' 'Restaurez versiunea anterioară...')
      $apply=Join-Path $script:AppRoot 'Apply_Update.ps1'
      & $apply -Mode Rollback -AppRoot $script:AppRoot -BackupPath $BackupPath -Quiet -StatusPath $StatusPath
      exit 0
    }
  }catch{
    Write-WorkerState 'error' ([string]$_.Exception.Message)
    exit 1
  }
}

# Minimal two-step update flow: no file selector for regular updates.
$lang=if([string]$script:cfg.language -eq 'ro'){'ro'}else{'en'}
function U([string]$en,[string]$ro){if($lang -eq 'ro'){return $ro};return $en}
$form=New-Object Windows.Forms.Form
$form.Text='Instant Downloader - Updates'
$form.ClientSize=New-Object Drawing.Size(630,370)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$form.BackColor=[Drawing.ColorTranslator]::FromHtml('#f5f7fa');$form.Font=New-Object Drawing.Font('Segoe UI',10)
function L($t,$x,$y,$w,$h){$a=New-Object Windows.Forms.Label;$a.Text=$t;$a.SetBounds($x,$y,$w,$h);$form.Controls.Add($a);return $a}
function B($t,$x,$y,$w,$h){$a=New-Object Windows.Forms.Button;$a.Text=$t;$a.SetBounds($x,$y,$w,$h);$form.Controls.Add($a);return $a}
[void](L (U 'APPLICATION UPDATES' 'ACTUALIZARI APLICATIE') 22 14 540 32)
[void](L ((U 'Installed version: ' 'Versiunea instalata: ')+$script:currentVersion) 22 49 550 24)
[void](L (U 'Check online, then install the update. No ZIP or manual manifest needed.' 'Verifica online si instaleaza update-ul. Fara ZIP sau manifest manual.') 22 81 590 30)
$check=B (U 'Check for updates' 'Verifica actualizarile') 22 119 189 40
$install=B (U 'Install update' 'Instaleaza update') 222 119 189 40;$install.Enabled=$false;$install.BackColor=[Drawing.ColorTranslator]::FromHtml('#e0f4e8')
$rollback=B (U 'Rollback' 'Revino la versiunea veche') 422 119 178 40
$statusBox=New-Object Windows.Forms.TextBox;$statusBox.Multiline=$true;$statusBox.ReadOnly=$true;$statusBox.ScrollBars='Vertical';$statusBox.SetBounds(22,173,578,121);$statusBox.Font=New-Object Drawing.Font('Consolas',9)
$form.Controls.Add($statusBox);$script:statusBox=$statusBox
$sourceInfo=L '' 22 302 578 40
$sourceInfo.Text= U 'GitHub is primary; Dropbox is the fallback. Personal data stays on your PC.' 'GitHub este sursa principala; Dropbox este rezerva. Datele personale raman pe PC.'
function Check-Now {
  $check.Enabled=$false;$install.Enabled=$false;$script:release=$null
  try{
    $sources=@([string]$script:cfg.updateManifestSource,[string]$script:cfg.updateManifestFallback) | Where-Object {$_ -match '^https://'} | Select-Object -Unique
    if($sources.Count -eq 0){throw (U 'Update service not configured yet. A GitHub/Dropbox release must be published first.' 'Sursa update nu este configurata. Trebuie publicat mai intai release-ul GitHub/Dropbox.')}
    $r=$null;$selected='';$errors=@()
    foreach($candidate in $sources){
      try{$possible=Load-Release $candidate;if(-not $r -or (Version-Compare $possible.version $r.version) -gt 0){$r=$possible;$selected=$candidate}}
      catch{$errors+=($_.Exception.Message)}
    }
    if(-not $r){throw ((U 'No eligible update: ' 'Nu exista actualizare eligibila: ')+($errors -join ' | '))}
    $script:release=$r;$script:manifestLocation=$selected
    Display ((U 'Update available: ' 'Actualizare disponibila: ')+$r.version+' ['+$r.channel+']')
    if($r.notes){Display ('Release notes: '+$r.notes)}
    $install.Enabled=$true
  }catch{Display ('INFO: '+$_)}
  finally{$check.Enabled=$true}
}
$check.Add_Click({Check-Now})
$install.Add_Click({
  if(-not $script:release){return}
  $install.Enabled=$false
  try{
    $payload=Prepare-Update $script:release
    $ok=[Windows.Forms.MessageBox]::Show((U 'Install ' 'Instalezi ')+$script:release.version+'?'+[Environment]::NewLine+(U 'Your downloads and Skool login are kept.' 'Cursurile si autentificarea Skool raman neschimbate.'),'Instant Downloader',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
    if($ok -ne 'Yes'){Display (U 'Update cancelled.' 'Actualizarea a fost anulata.');return}
    Launch-Apply 'Install' $payload $script:release.version
    $form.Close()
  }catch{Display ('ERROR: '+$_);UiMsg $_.Exception.Message}
  finally{$install.Enabled=$true}
})
$rollback.Add_Click({
  try{
    $backupRoot=Join-Path $script:base 'backups'
    $all=@(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'record.json')} | Sort-Object Name -Descending)
    if($all.Count -eq 0){throw (U 'No update backups found.' 'Nu exista copii de rezerva.')}
    $recent=$all[0].FullName;$rec=Get-Content -LiteralPath (Join-Path $recent 'record.json') -Raw | ConvertFrom-Json
    $choice=[Windows.Forms.MessageBox]::Show((U 'Restore version ' 'Revii la versiunea ')+[string]$rec.previous_version+'?','Instant Downloader',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if($choice -eq 'Yes'){Launch-Apply 'Rollback' '' '' $recent;$form.Close()}
  }catch{Display ('INFO: '+$_);UiMsg $_.Exception.Message}
})
Display (U 'Updates are checked through the configured online channels.' 'Actualizari verificate prin canalele online configurate.')
if($AutoCheck){
  $autoTimer=New-Object Windows.Forms.Timer
  $autoTimer.Interval=500
  $autoTimer.Add_Tick({$autoTimer.Stop();Check-Now})
  $form.Add_Shown({$autoTimer.Start()})
}
[void]$form.ShowDialog()
