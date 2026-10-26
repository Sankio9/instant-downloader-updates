# Interactive installer. Never requires an admin account if it can reuse Node or install portable Node.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$exeNames=@('README_RO.txt','package.json','Instant_Downloader.ps1','START_INSTANT_DOWNLOADER.cmd','supervisor.cjs','bridge.mjs','audit_archive.cjs','selection.cjs','check_update_notice.cjs','patch_progress.cjs','DIAGNOSTIC_INSTANT_DOWNLOADER.cmd','Diagnostics.ps1','Preflight.ps1','Update_Instant_Downloader.ps1','Apply_Update.ps1')

function ShowInfo($message,$title='Instant Downloader Installer') { [void][System.Windows.Forms.MessageBox]::Show($message,$title) }
function Ensure-InstantDownloaderSubfolder([string]$selectedPath){
  # Folder selection picks a parent. Use a dedicated subfolder without duplicating it.
  if([string]::IsNullOrWhiteSpace($selectedPath)){return $selectedPath}
  $trimmed=$selectedPath.TrimEnd([char[]]@('\','/'))
  $lastPart=[IO.Path]::GetFileName($trimmed)
  if($lastPart -ieq 'Instant Downloader' -or $lastPart -ieq 'InstantDownloader'){
    return $selectedPath
  }
  return (Join-Path -Path $selectedPath -ChildPath 'Instant Downloader')
}
function FolderDialog($current){
  $d=New-Object System.Windows.Forms.FolderBrowserDialog
  $d.Description='Alege un folder'
  # Optional old-app path may be blank. Never pass an empty LiteralPath.
  if(-not [string]::IsNullOrWhiteSpace([string]$current)){
    try { if(Test-Path -LiteralPath $current -ErrorAction Stop){$d.SelectedPath=$current} }catch{}
  }
  if([string]::IsNullOrWhiteSpace([string]$d.SelectedPath)){
    $d.SelectedPath=[Environment]::GetFolderPath('UserProfile')
  }
  if($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){return $d.SelectedPath}
  return $null
}
function FreeGB($drive){
  try{ return '{0:N1} GB liberi' -f ($drive.AvailableFreeSpace/1GB) }catch{return 'Necunoscut'}
}
function Notice($msg){
  $line='['+(Get-Date).ToString('HH:mm:ss')+'] '+$msg
  $script:log.AppendText($line+"`r`n")
  $script:log.SelectionStart=$script:log.TextLength;$script:log.ScrollToCaret()
  [System.Windows.Forms.Application]::DoEvents()
}
function Read-RunningLogTail([string]$logPath){
  try {
    if(-not (Test-Path -LiteralPath $logPath)) { return '' }
    $stream=[System.IO.File]::Open($logPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
    try {
      [void]$stream.Seek([Math]::Max([long]0,([long]$stream.Length - 8192)),[System.IO.SeekOrigin]::Begin)
      $reader=[System.IO.StreamReader]::new($stream)
      return $reader.ReadToEnd()
    } finally { $stream.Dispose() }
  }catch{ return '' }
}
function Stop-InstallerTree($process){
  if(-not $process){ return }
  try {
    $taskKill=Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if(Test-Path -LiteralPath $taskKill){
      & $taskKill /PID ([string]$process.Id) /T /F 2>$null | Out-Null
    }
  } catch {}
  try{if(-not $process.HasExited){$process.Kill()}}catch{}
}
function RunInstallerCommand($executable,$arguments,$folder,$label,$allowFailure=$false,$timeoutMinutes=18,$showTransfer=$false){
  Notice $label
  $out=Join-Path $script:tempFolder 'install_stdout.txt'
  $err=Join-Path $script:tempFolder 'install_stderr.txt'
  # Files are per invocation. Keep a copy of the last failure for diagnostics.
  Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
  $p=$null
  try{
    $p=Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $folder -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
    $began=Get-Date
    $lastReport=Get-Date
    $lastProgress=''
    if($showTransfer){
      $script:componentLabel.Text='Browser Playwright: verificare / descarcare...'
      $script:componentBar.Value=0
    }
    while(-not $p.HasExited){
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 350
      $p.Refresh()
      if($script:cancelRequested){
        Stop-InstallerTree $p
        throw 'Instalarea a fost anulata. Poti relua fara a sterge fisierele deja instalate.'
      }
      if($showTransfer){
        $logData=(Read-RunningLogTail $out)+(Read-RunningLogTail $err)
        $allPercents=[regex]::Matches($logData,'(?<![0-9])([0-9]{1,3})(?:\.[0-9]+)?%')
        $elapsed=[int]((Get-Date)-$began).TotalSeconds
        if($allPercents.Count -gt 0){
          $lastMatch=$allPercents[$allPercents.Count-1]
          $pct=[Math]::Min(100,[Math]::Max(0,[int]$lastMatch.Groups[1].Value))
          $script:componentBar.Value=$pct
          $script:componentLabel.Text=('Browser: pachet curent '+$pct+'% | activ de '+$elapsed+' secunde')
          if( ($lastProgress -ne $lastMatch.Value) -and ((Get-Date)-$lastReport).TotalSeconds -ge 7 ){
            Notice ('Chromium / Playwright: componenta curenta '+$lastMatch.Value)
            $lastProgress=$lastMatch.Value
            $lastReport=Get-Date
          }
        }else{
          $script:componentLabel.Text=('Browser Playwright: verificare / descarcare... '+$elapsed+' secunde')
          if(((Get-Date)-$lastReport).TotalSeconds -ge 20){
            Notice ('Playwright este in lucru ('+$elapsed+' secunde). Urmareste fisierele din folderul _browsers; loguri in _temp.')
            $lastReport=Get-Date
          }
        }
      }
      if(((Get-Date)-$began).TotalMinutes -gt $timeoutMinutes){
        Stop-InstallerTree $p
        throw ('Procesul nu s-a terminat in '+$timeoutMinutes+' minute. Verifica internetul si reincearca. Jurnale: '+$out+' si '+$err)
      }
    }
    $p.WaitForExit()
    if($showTransfer){
      $script:componentLabel.Text='Verificare browser finalizata; controlez rezultatul...'
    }
    $code=[int]$p.ExitCode
    if($code -ne 0){
      $stdoutTail=((Get-Content -LiteralPath $out -Tail 12 -ErrorAction SilentlyContinue) -join ' | ')
      $stderrTail=((Get-Content -LiteralPath $err -Tail 12 -ErrorAction SilentlyContinue) -join ' | ')
      Notice ('Cod iesire '+$code+'. '+$stdoutTail+' '+$stderrTail)
      if(-not $allowFailure){throw ('Comanda a esuat: '+$label+' (cod '+$code+'). Vezi '+$out+' si '+$err)}
    }else{Notice ('OK: '+$label)}
    return $code
  }finally{if($p){$p.Dispose()}}
}
function DependenciesPresent($folder){
  $vendor=Join-Path $folder 'node_modules'
  return ((Test-Path -LiteralPath (Join-Path $vendor 'skool-downloader\src\index.ts')) -and
          (Test-Path -LiteralPath (Join-Path $vendor 'tsx\dist\cli.mjs')) -and
          (Test-Path -LiteralPath (Join-Path $vendor 'esbuild')))
}

function InstallPortableNode($programDir){
  Notice 'Node.js lipseste: caut versiunea oficiala LTS pentru Windows x64...'
  $releases=Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 35
  $rel=$releases | Where-Object {$_.lts -and $_.lts -ne $false} | Select-Object -First 1
  if(-not $rel){throw 'Nu am gasit o versiune Node.js LTS.'}
  $v=$rel.version
  $name="node-$v-win-x64.zip"
  $base="https://nodejs.org/dist/$v/"
  $zip=Join-Path $script:tempFolder $name
  Notice "Descarc Node.js $v de pe nodejs.org..."
  Invoke-WebRequest -Uri ($base+$name) -OutFile $zip -UseBasicParsing -TimeoutSec 120
  $hashList=(Invoke-WebRequest -Uri ($base+'SHASUMS256.txt') -UseBasicParsing -TimeoutSec 40).Content
  $matching=@($hashList -split "`n" | Where-Object {$_ -match ('\s+'+[regex]::Escape($name)+'\s*$')}) | Select-Object -First 1
  if(-not $matching){throw 'Nu am gasit checksum pentru Node.js.'}
  $expected=($matching.Trim() -split '\s+')[0].ToLowerInvariant()
  $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
  if($actual -ne $expected){throw 'Suma SHA256 Node.js nu coincide. Instalare oprita.'}
  $vendor=Join-Path $programDir 'vendor'
  [void][IO.Directory]::CreateDirectory($vendor)
  Expand-Archive -LiteralPath $zip -DestinationPath $vendor -Force
  $bin=Join-Path (Join-Path $vendor "node-$v-win-x64") 'node.exe'
  $npm=Join-Path (Split-Path -Parent $bin) 'npm.cmd'
  if(-not (Test-Path -LiteralPath $bin) -or -not (Test-Path -LiteralPath $npm)){throw 'Arhiva Node.js incompleta.'}
  return @{node=$bin;npm=$npm}
}
$form=New-Object System.Windows.Forms.Form
$form.Text='Instant Downloader v1.8 RC12 - Installer'
$form.ClientSize=New-Object System.Drawing.Size(720,715)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$form.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#f5f7fa')
$font=New-Object System.Drawing.Font('Segoe UI',10)
$form.Font=$font
function Label($str,$x,$y,$w,$h){$l=New-Object System.Windows.Forms.Label;$l.Text=$str;$l.SetBounds($x,$y,$w,$h);$form.Controls.Add($l);return $l}
function Field($value,$y){$t=New-Object System.Windows.Forms.TextBox;$t.Text=$value;$t.SetBounds(25,$y,580,28);$form.Controls.Add($t);return $t}
function Btn($str,$y){$b=New-Object System.Windows.Forms.Button;$b.Text=$str;$b.SetBounds(615,$y,80,29);$form.Controls.Add($b);return $b}
[void](Label 'INSTANT DOWNLOADER' 25 16 600 35)
[void](Label 'Installer local: alege discul TEMP, folderul arhivei si locatia aplicatiei.' 25 53 670 24)
[void](Label 'Discul pentru TEMP / cache / browser Playwright:' 25 95 530 22)
$driveCombo=New-Object System.Windows.Forms.ComboBox
$driveCombo.DropDownStyle='DropDownList';$driveCombo.SetBounds(25,122,670,29);$form.Controls.Add($driveCombo)
$ready=@([IO.DriveInfo]::GetDrives() | Where-Object {$_.IsReady -and $_.DriveType -ne [IO.DriveType]::CDRom})
foreach($drive in $ready){[void]$driveCombo.Items.Add(($drive.Name+' - '+(FreeGB $drive)))}
$chosen=0
for($i=0;$i -lt $ready.Count;$i++){if($ready[$i].Name -eq 'Q:\'){$chosen=$i;break}}
if($driveCombo.Items.Count -gt 0){$driveCombo.SelectedIndex=$chosen}
function CurrentDisk(){if($ready.Count -eq 0){throw 'Nu exista un disc disponibil.'};return $ready[[Math]::Max($driveCombo.SelectedIndex,0)].Name}
$defaultDisk=if($ready.Count -gt 0){$ready[$chosen].Name}else{'C:\'}
[void](Label 'Folder TEMP (date temporare, cache npm, browser):' 25 167 540 20)
$tempText=Field (Join-Path $defaultDisk 'TEMP\Instant Downloader') 190
$tempBrowse=Btn 'Alege...' 189
[void](Label 'Folder ARCHIVA (numai cursuri / lectii / index.html):' 25 232 565 20)
$archiveText=Field (Join-Path $defaultDisk 'Instant Archive') 254
$archiveBrowse=Btn 'Alege...' 253
[void](Label 'Folder APLICATIE (instalare program):' 25 295 530 20)
$appText=Field (Join-Path $defaultDisk 'Apps\Instant Downloader') 317
$appBrowse=Btn 'Alege...' 316
[void](Label 'Optional: folderul vechii versiuni BAT pentru sesiunea Skool:' 25 354 650 20)
$oldText=Field '' 377
$oldBrowse=Btn 'Alege...' 376
$driveCombo.Add_SelectedIndexChanged({
  if($ready.Count -eq 0){return}
  $d=CurrentDisk
  $tempText.Text=Join-Path $d 'TEMP\Instant Downloader'
  $archiveText.Text=Join-Path $d 'Instant Archive'
  $appText.Text=Join-Path $d 'Apps\Instant Downloader'
})
$tempBrowse.Add_Click({if($script:isInstalling){return};$v=FolderDialog $tempText.Text;if($v){$tempText.Text=Ensure-InstantDownloaderSubfolder $v}})
$archiveBrowse.Add_Click({if($script:isInstalling){return};$v=FolderDialog $archiveText.Text;if($v){$archiveText.Text=$v}})
$appBrowse.Add_Click({if($script:isInstalling){return};$v=FolderDialog $appText.Text;if($v){$appText.Text=Ensure-InstantDownloaderSubfolder $v}})
$oldBrowse.Add_Click({if($script:isInstalling){return};$v=FolderDialog $oldText.Text;if($v){$oldText.Text=$v}})
$installBtn=New-Object System.Windows.Forms.Button
$installBtn.Text='INSTALEAZA / ACTUALIZEAZA'
$installBtn.SetBounds(25,420,310,40);$installBtn.BackColor=[Drawing.ColorTranslator]::FromHtml('#d9f2e0')
$form.Controls.Add($installBtn)
$log=New-Object System.Windows.Forms.TextBox
$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical'
$log.Font=New-Object System.Drawing.Font('Consolas',9)
$log.SetBounds(25,557,670,125);$form.Controls.Add($log)
$script:log=$log
$stepLabel=Label 'Pregatit pentru instalare' 25 467 660 22
$stepBar=New-Object System.Windows.Forms.ProgressBar
$stepBar.SetBounds(25,490,670,12)
$stepBar.Minimum=0;$stepBar.Maximum=8;$stepBar.Value=0
$form.Controls.Add($stepBar)
$componentLabel=Label 'Progresul descarcarilor necesare apare aici.' 25 509 670 20
$componentBar=New-Object System.Windows.Forms.ProgressBar
$componentBar.SetBounds(25,532,670,12)
$componentBar.Minimum=0;$componentBar.Maximum=100;$componentBar.Value=0
$form.Controls.Add($componentBar)
$script:componentLabel=$componentLabel
$script:componentBar=$componentBar
$cancelBtn=New-Object System.Windows.Forms.Button
$cancelBtn.Text='ANULEAZA'
$cancelBtn.SetBounds(350,420,150,40)
$cancelBtn.Enabled=$false
$form.Controls.Add($cancelBtn)
$script:cancelRequested=$false
$cancelBtn.Add_Click({
  if(-not $script:isInstalling){return}
  $answer=[System.Windows.Forms.MessageBox]::Show('Opresti instalarea? Fisierele finalizate raman pe disc.','Instant Downloader',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
  if($answer -eq [System.Windows.Forms.DialogResult]::Yes){
    $script:cancelRequested=$true
    $cancelBtn.Enabled=$false
    Notice 'Anulare ceruta; inchid procesele de instalare...'
  }
})
function Step($number,$message){$stepBar.Value=[Math]::Min(8,[Math]::Max(0,$number));$stepLabel.Text=$message;[Windows.Forms.Application]::DoEvents()}
$script:isInstalling=$false
$script:installedOk=$false
$form.Add_FormClosing({param($sender,$eventArgs) if($script:isInstalling){$eventArgs.Cancel=$true}})
$installBtn.Add_Click({
  $installBtn.Enabled=$false
  $script:cancelRequested=$false
  $cancelBtn.Enabled=$true
  $script:componentBar.Value=0
  $script:componentLabel.Text='Verificari de instalare...'
  $script:isInstalling=$true
  try{
    $stepLabel.ForeColor=[Drawing.ColorTranslator]::FromHtml('#283747')
    Step 0 'Etapa 1/8 - Verific locatiile si spatiul liber...'
    $programDir=$appText.Text.Trim()
    $tempRoot=$tempText.Text.Trim()
    $archive=$archiveText.Text.Trim()
    if(-not [IO.Path]::IsPathRooted($tempRoot) -or -not [IO.Path]::IsPathRooted($archive) -or -not [IO.Path]::IsPathRooted($programDir)) {throw 'Alege foldere absolute pentru toate cele 3 locatii.'}
    $threePaths=@($programDir,$tempRoot,$archive) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\').ToLowerInvariant() }
    for($i=0;$i -lt 3;$i++){
      for($j=$i+1;$j -lt 3;$j++){
        if($threePaths[$i] -eq $threePaths[$j] -or $threePaths[$i].StartsWith($threePaths[$j]+'\') -or $threePaths[$j].StartsWith($threePaths[$i]+'\')){
          throw 'APLICATIE, TEMP si ARHIVA trebuie sa fie foldere separate, fara unul in interiorul altuia.'
        }
      }
    }
    foreach($v in @($programDir,$tempRoot,$archive)){
      $disk=[IO.Path]::GetPathRoot($v)
      $di=[IO.DriveInfo]::new($disk)
      if(-not $di.IsReady){throw "Discul $disk nu este disponibil."}
      if($di.AvailableFreeSpace -lt 1024MB){ throw "Discul $disk are sub 1 GB liber. Elibereaza spatiu inainte de instalare." }
    }

    if($programDir -match '(?i)^[a-z]:\\Program Files( \(x86\))?\\'){
      Notice 'AVERTISMENT: Program Files poate cere drepturi de administrator. Recomandam E:\Apps\Instant Downloader.'
    }
    foreach($v in @($programDir,$tempRoot,$archive,(Join-Path $tempRoot '_temp'),(Join-Path $tempRoot '_browsers'),(Join-Path $tempRoot '_npm-cache'),(Join-Path $tempRoot '_cache'))){[void][IO.Directory]::CreateDirectory($v)}
    Step 1 'Etapa 2/8 - Pregatesc folderele selectate...'
    $script:tempFolder=Join-Path $tempRoot '_temp'
    $env:TEMP=$script:tempFolder;$env:TMP=$script:tempFolder
    $env:NPM_CONFIG_CACHE=Join-Path $tempRoot '_npm-cache'
    $env:PLAYWRIGHT_BROWSERS_PATH=Join-Path $tempRoot '_browsers'
    $env:SKOOL_DOWNLOADER_CACHE_DIR=Join-Path $tempRoot '_cache'
    Notice ('TEMP: '+$tempRoot)
    Notice ('ARHIVA: '+$archive)
    # Snapshot old app scripts before any update. Never copy or remove authentication data.
    $backupFiles=@($exeNames | Where-Object {Test-Path -LiteralPath (Join-Path $programDir $_)})
    if($backupFiles.Count -gt 0){
      $stamp=(Get-Date).ToString('yyyyMMdd_HHmmss')
      $bk=Join-Path $programDir ('_backup_app_'+$stamp)
      [void][IO.Directory]::CreateDirectory($bk)
      foreach($f in $backupFiles){Copy-Item -LiteralPath (Join-Path $programDir $f) -Destination (Join-Path $bk $f)}
      Notice 'Versiunea anterioara a aplicatiei a fost salvata local in folderul _backup_app_*.'
    }
    foreach($f in $exeNames){ if(-not (Test-Path -LiteralPath (Join-Path $source $f) -PathType Leaf)){throw ('Installer package is missing '+$f)} }
    foreach($f in $exeNames){ Copy-Item -LiteralPath (Join-Path $source $f) -Destination (Join-Path $programDir $f) -Force }
    if(Test-Path -LiteralPath (Join-Path $source 'SHA256SUMS.txt')){Copy-Item -LiteralPath (Join-Path $source 'SHA256SUMS.txt') -Destination (Join-Path $programDir 'SHA256SUMS.txt') -Force}
    Notice 'Fisierele aplicatiei au fost copiate.'
    Step 2 'Etapa 3/8 - Verific Node.js...'
    $nodeCmd=Get-Command node.exe -ErrorAction SilentlyContinue
    $npmCmd=Get-Command npm.cmd -ErrorAction SilentlyContinue
    $usableNode=$false
    if($nodeCmd -and $npmCmd){
      try { $vText=(& $nodeCmd.Source --version).Trim(); $vMatch=[regex]::Match($vText,'^v(\d+)'); $vMajor=[int]$vMatch.Groups[1].Value; $usableNode=($vMajor -ge 18) }catch{}
    }
    if($usableNode){
      $node=$nodeCmd.Source;$npm=$npmCmd.Source
      Notice ('Node.js existent: '+$node+' ('+$vText+')')
    }else{
      $bins=InstallPortableNode $programDir
      $node=$bins.node;$npm=$bins.npm
      Notice 'Node.js LTS portabil instalat pe discul ales, fara drepturi administrator.'
    }
    $env:PATH=(Split-Path -Parent $node)+';'+$env:PATH
    # installer may be rerun: npm will retain installation if up-to-date.
    Step 3 'Etapa 4/8 - Instalez dependentele npm...'
    $npmArgs='/d /s /c ""'+$npm+'" install --no-audit --no-fund"'
    $npmExit=0
    try {
      $npmExit=RunInstallerCommand "$env:SystemRoot\System32\cmd.exe" $npmArgs $programDir 'Verific si instalez pachetele npm necesare...' $true
    }catch{
      Notice ('Executie npm intrerupta: '+$_)
      $npmExit=1
    }
    if(-not (DependenciesPresent $programDir)){
      throw ('Dependentele npm lipsesc sau sunt incomplete (cod '+$npmExit+'). Consulta install_stdout.txt si install_stderr.txt din '+$script:tempFolder)
    }
    if($npmExit -ne 0){ Notice 'AVERTISMENT: npm a semnalat eroare, dar modulele necesare exista. Verific functionalitatea modulului tsx.' }
    $tsxCheck='--import tsx -e "console.log(42)"'
    $tsxStatus=RunInstallerCommand $node $tsxCheck $programDir 'Verific ca tsx/esbuild pot porni corect...'
    Notice 'Dependente npm verificate functional, nu doar dupa mesaje de avertizare.'
    Step 4 'Etapa 5/8 - Activez progresul video...'
    $patchScript=Join-Path $programDir 'patch_progress.cjs'
    $r=RunInstallerCommand $node ('"'+$patchScript+'"') $programDir 'Activez progresul individual yt-dlp...'
    Step 5 'Etapa 6/8 - Verific browserul Playwright...'
    $playwright=Join-Path $programDir 'node_modules\.bin\playwright.cmd'
    if(-not (Test-Path -LiteralPath $playwright)){throw 'Playwright lipseste dupa npm install.'}
    $browserFolder=Join-Path $tempRoot '_browsers'
    # Playwright itself checks the exact compatible browser version and avoids redownloading it.
    $pwArgs='/d /s /c ""'+$playwright+'" install chromium"'
    $env:PLAYWRIGHT_DOWNLOAD_CONNECTION_TIMEOUT='120000'
    $r=RunInstallerCommand "$env:SystemRoot\System32\cmd.exe" $pwArgs $programDir 'Verific browserul Playwright / instalez doar daca lipseste...' $false 18 $true
    # The upstream downloader manages its own video tools. Do not require a third-party
    # ffmpeg-static npm package which may not be present in the pinned dependency tree.
    Step 6 'Etapa 7/8 - Verific FFmpeg si autentificarea existenta...'
    $ffmpegCmd=Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if($ffmpegCmd){ Notice ('FFmpeg existent: '+$ffmpegCmd.Source) }
    else{
      $ffmpegLocal=Join-Path $programDir 'node_modules\ffmpeg-static\ffmpeg.exe'
      if(Test-Path -LiteralPath $ffmpegLocal){Notice 'FFmpeg este disponibil local in node_modules.'}
      else{
        Notice 'FFmpeg nu este detectat. Incerc sa il instalez local, fara drepturi administrator...'
        $ffmpegArgs='/d /s /c ""'+$npm+'" install --no-save --no-audit --no-fund ffmpeg-static"'
        $ffmpegResult=RunInstallerCommand "$env:SystemRoot\System32\cmd.exe" $ffmpegArgs $programDir 'Instalez ffmpeg-static optional...' $true
        if($ffmpegResult -ne 0 -or -not (Test-Path -LiteralPath $ffmpegLocal)){
          Notice 'ATENTIE: FFmpeg lipseste. Unele videoclipuri se pot descarca fara sunet sau pot esua. Aplicatia ramane instalabila.'
        }
      }
    }
    $old=$oldText.Text.Trim()
    $authDest=Join-Path $programDir '.auth'
    if(Test-Path -LiteralPath (Join-Path $authDest 'storage_state.json')){
      Notice 'Sesiunea Skool existenta se pastreaza. Nu este suprascrisa.'
    }

    if($old){
      if(Test-Path -LiteralPath (Join-Path $old '.auth\storage_state.json')){
        [void][IO.Directory]::CreateDirectory($authDest)
        if(-not (Test-Path -LiteralPath (Join-Path $authDest 'storage_state.json'))){
          Copy-Item -LiteralPath (Join-Path $old '.auth\storage_state.json') -Destination (Join-Path $authDest 'storage_state.json')
        }
        if((Test-Path -LiteralPath (Join-Path $old '.auth\cookies.txt')) -and -not (Test-Path -LiteralPath (Join-Path $authDest 'cookies.txt'))){
          Copy-Item -LiteralPath (Join-Path $old '.auth\cookies.txt') -Destination (Join-Path $authDest 'cookies.txt')
        }
        Notice 'Sesiunea Skool a fost transferata LOCAL, numai la cererea utilizatorului.'
      }else{Notice 'Nu am gasit sesiunea Skool in folderul vechi selectat.'}
    }
    $cfgFile=Join-Path $programDir 'config.json'
    $prior=$null
    if(Test-Path -LiteralPath $cfgFile){try{$prior=Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json}catch{}}
    if(Test-Path -LiteralPath $cfgFile){Copy-Item -LiteralPath $cfgFile -Destination ($cfgFile+'.backup') -Force}
    $releaseVer=[string]((Get-Content -LiteralPath (Join-Path $programDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version)
    if($releaseVer -notmatch '^\d+\.\d+\.\d+(?:-rc\.\d+)?$'){throw 'Invalid application package version.'}
    $defaultFeed='https://raw.githubusercontent.com/Sankio9/instant-downloader-updates/main/latest.json'
    $cfg=@{version=$releaseVer;tempPath=$tempRoot;archivePath=$archive;nodePath=$node;lastUrl=$(if($prior){[string]$prior.lastUrl}else{''});language=$(if($prior -and $prior.language){[string]$prior.language}else{'en'});updateManifestSource=$(if($prior -and $prior.updateManifestSource){[string]$prior.updateManifestSource}else{$defaultFeed});updateManifestFallback=$(if($prior){[string]$prior.updateManifestFallback}else{''});updateChannel=$(if($prior -and $prior.updateChannel){[string]$prior.updateChannel}else{'rc'})}
    [IO.File]::WriteAllText($cfgFile,($cfg|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    Step 7 'Etapa 8/8 - Finalizez configurarea...'
    $desktop=[Environment]::GetFolderPath('Desktop')
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut((Join-Path $desktop 'Instant Downloader.lnk'))
    $shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $programDir 'Instant_Downloader.ps1')+'"'
    $shortcut.WorkingDirectory=$programDir
    $shortcut.Description='Instant Downloader '+$releaseVer
    $shortcut.Save()
    Notice 'Scurtatura Desktop creata.'
    # The package downloads yt-dlp by itself. Proactively try installing it now.
    $verifyArgs='--import tsx "'+(Join-Path $programDir 'bridge.mjs')+'" verify-ytdlp'
    $binPath=Join-Path $tempRoot '_cache\bin\yt-dlp.exe'
    if(Test-Path -LiteralPath $binPath){Notice 'yt-dlp este deja prezent; verificarea actualizarilor se face la descarcare.';$r=0}
    else{$r=RunInstallerCommand $node $verifyArgs $programDir 'Instalez yt-dlp pentru prima utilizare...' $true}
    if($r -ne 0){Notice 'yt-dlp va fi verificat automat la prima descarcare; installerul poate continua.'}
    Step 8 'Instalare finalizata.'
    Notice 'INSTALARE FINALIZATA. Testeaza mai intai o singura categorie.'
    $script:componentLabel.Text='Instalare completa.'
    ShowInfo 'Instalarea s-a terminat. Pe Desktop exista Instant Downloader. Prima data foloseste Login Skool daca nu ai transferat sesiunea.'
    Start-Process -FilePath $shortcut.FullName
    $script:installedOk=$true
    $script:isInstalling=$false
    $form.Close()
  }catch{
    Notice ('INSTALARE OPRITA: '+$_)
    Step 0 'Instalare oprita: corecteaza eroarea si apasa REINCEARCA'
    $stepLabel.ForeColor=[Drawing.ColorTranslator]::FromHtml('#b82f3c')
    $installBtn.Text='REINCEARCA INSTALAREA'
    ShowInfo ("Instalarea nu s-a terminat:`r`n"+$_)
  }finally{$script:isInstalling=$false;$installBtn.Enabled=$true;$cancelBtn.Enabled=$false}
})
Notice 'Alege locatiile si apasa INSTALEAZA. Internetul este necesar la prima instalare.'
[void]$form.ShowDialog()
if(-not $script:installedOk){exit 1}
