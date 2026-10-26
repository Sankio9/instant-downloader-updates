# Instant Downloader v1.8 RC7 | Windows 10/11 | Windows PowerShell 5.1
# Local desktop application. Never uploads authentication data.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class SkoolProcessControl {
  [DllImport("ntdll.dll")] static extern int NtSuspendProcess(IntPtr handle);
  [DllImport("ntdll.dll")] static extern int NtResumeProcess(IntPtr handle);
  public static void Suspend(int pid) { using(var p=Process.GetProcessById(pid)) { var r=NtSuspendProcess(p.Handle); if(r!=0) throw new Exception("Suspend error " + r); } }
  public static void Resume(int pid) { using(var p=Process.GetProcessById(pid)) { var r=NtResumeProcess(p.Handle); if(r!=0) throw new Exception("Resume error " + r); } }
}
'@
$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:AppRoot 'config.json'
if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
  [System.Windows.Forms.MessageBox]::Show('Configuratia lipseste. Ruleaza mai intai INSTALL_INSTANT_DOWNLOADER.cmd.','Instant Downloader') | Out-Null
  exit 1
}
$script:cfg = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:nodeExe = $script:cfg.nodePath
if (-not (Test-Path -LiteralPath $script:nodeExe)) {
  [System.Windows.Forms.MessageBox]::Show('Node.js nu mai este la locatia configurata. Ruleaza din nou installerul.','Instant Downloader') | Out-Null
  exit 1
}
$script:jobProcess = $null
$script:isPaused = $false
$script:pausedPids = @()
$script:jobLog = ''
$script:offset = [long]0
$script:remainder = ''
$script:pendingUtf8Bytes = [byte[]]@()
$script:lastError = ''
$script:completeErrors = 0
$script:failedVideos = @{}
$script:runningMode = ''
$script:loginSucceeded = $false
$script:slotItems = @{}
$script:slotOrder = New-Object System.Collections.ArrayList
$script:entries = @()
$script:childSnapshot = @()
$script:selectedUrl = ''
$script:selectedLevel = 'all'
$script:selectedKeys = @()
$script:catalogResult = $null
$script:historyItems = @{}
$script:activeCourse = ''
$script:noticeFile = Join-Path ([string]$script:cfg.tempPath) '_updates\update_notice.json'
$script:noticeStarted = [DateTime]::MinValue
$script:noticeObserved = [DateTime]::MinValue
$script:nextNotice = [DateTime]::MinValue
$script:knownUpdate = ''
$script:sessionStarted = Get-Date



# Persisted UI preference. Default to English for new and previously-installed users.
$script:language = if(([string]$script:cfg.language) -eq 'ro'){'ro'}else{'en'}
$script:currentState = 'ready'
$script:operationStart = $null
$script:lastActivity = $null
$script:operationElapsed = [TimeSpan]::Zero
$script:translations = @{
  en = @{
    appTitle='Instant Downloader'; subtitle='SKOOL  |  YouTube, Instagram and TikTok (coming soon)'
    language='Language'; courseUrl='Skool Classroom / course link'; subgroups='Choose sections'; allSections='Default: download the entire course. Optionally select specific sections.'
    archive='Course archive folder'; browse='Browse...'; start='Start'; pause='Pause'; resume='Resume'; stop='Stop'; login='Login Skool'; rebuild='Refresh course pages'; updates='Updates';
    ready='READY'; downloading='DOWNLOADING'; loggingin='SIGNING IN'; scanning='SCANNING SECTIONS'; indexing='REFRESHING COURSE PAGES'; paused='PAUSED'; stopping='STOPPING...'; finished='FINISHED'; failed='STOPPED / ERROR';
    waiting='Waiting...'; history='History - green: archived | orange: incomplete | red: failed'; colLesson='Lesson'; colStatus='Status'; colProgress='Progress'; colDetails='Details';
    openFolder='Open folder'; openIndex='Open course library'; openLog='Open log'; elapsed='Elapsed'; lastActivity='Last activity'; noActivity='No recent updates'; active='Active'; stopped='Stopped';
    archived='ARCHIVED'; downloaded='DOWNLOADED'; incomplete='INCOMPLETE'; error='ERROR'; running='IN PROGRESS';
    chooseFolder='Choose the folder for your course archive'; chooseSections='Select Skool sections to download'; useSelection='Use selection'; selectAll='Select all'; deselectAll='Clear all';
    noSections='No available sections found.'; selectOne='Select at least one section.'; selected='SELECTED'; sections='sections'; courses='courses';
    linkNeeded='Enter a valid https://www.skool.com/... address.'; linkRequired='Link required'; updateWhileWorking='Finish or stop active downloads before updating.';
    loginFailed='Skool sign-in was not completed.'; noJournal='No operation log yet.'; missingIndex='Course library not found. Download a course or click Refresh course pages.';
    closeBusy='A download is running. Stop it and close the application?'; closeTitle='Close'; startup='Application ready. Archive:';
    stateWarning='Process is running, but no progress events have arrived recently.';
    notifyCheck='Checking for updates...';
    notifyAvailable='Update available:';
    notifyFailed='Could not check for updates:';
    pausedLog='Paused. Some connections may expire before resuming; files already saved are preserved.';
    resumedLog='Transfers resumed.';
    stopLog='Stop requested. Completed files are preserved; partial downloads may resume if supported.';
    startedLog='Started:';
    startError='Cannot start:';
    auditLog='Archive audit:';
    loginLog='LOGIN FAILED:';
    logLabel='Log:';
    logComplete='Complete lessons';
    logIncomplete='incomplete';
    logInvalid='invalid';
    updateTitle='APPLICATION UPDATES'; installedVersion='Installed version'; back='Back to downloads'; checkUpdates='Check for updates'; installUpdate='Install update'; rollback='Restore previous version'; restart='Restart application';
    updateInstruction='Check for updates without leaving this window. Courses and login remain local.'; updateNotConfigured='Online updates are not configured yet.';
    updateChecking='Checking for updates...'; updateWorking='Working...'; updateNoChanges='You have the latest version.'; updatePendingRestart='Update installed. Restart the application to load the new version.';
    updateNoRollback='No update backup is available.'; updateConfirm='Install the verified update? Downloads and login will be preserved.';
    updateRollbackConfirm='Restore the most recent application backup?'; updateFailed='Update failed'; updateStarted='Preparing update...'; updateBusy='Another update task is running.';
    progressDone=' - OK'; progressFailed=' - FAILED'; infoCourse='Course'; infoLessons='lessons'; infoVideoFailed='Video download failed'; infoLessonError='Lesson error';
    infoIndex='Course pages updated'; infoCourses='courses'; infoCatalog='Sections found'; infoSession='Session finished'; infoErrors='errors'; infoNoUpdates='No update available';
    accessUnconfirmed='access unconfirmed'; selectAvailable='available sections'; selectLessons='lessons/modules'; selectedUnit='sections'; tempLabel='TEMP';
    resources='Text, links, attachments'; maxFour='up to 4 parallel downloads'; jobFailed='Process ended'; loginUnknown='See the local log for the exact cause.';
    pauseError='Pause unavailable'; pauseSafety='Could not safely suspend all child processes. Pause cancelled.'; resumeWarning='WARNING: some processes did not resume';
    updateWorkerMissing='Updater component is missing.'; indexReady='Course pages updated';

  }
  ro = @{
    appTitle='Instant Downloader'; subtitle='SKOOL  |  YouTube, Instagram și TikTok (în dezvoltare)'
    language='Limbă'; courseUrl='Link Skool Classroom / curs'; subgroups='Alege subgrupe'; allSections='Implicit: se descarcă întregul curs. Poți selecta doar anumite subgrupe.';
    archive='Folder arhivă cursuri'; browse='Alege...'; start='Start'; pause='Pauză'; resume='Continuă'; stop='Stop'; login='Login Skool'; rebuild='Actualizează paginile'; updates='Actualizări';
    ready='PREGĂTIT'; downloading='DESCĂRCARE'; loggingin='AUTENTIFICARE'; scanning='CITIRE SUBGRUPE'; indexing='ACTUALIZARE PAGINI'; paused='PAUZĂ'; stopping='OPRIRE...'; finished='FINALIZAT'; failed='OPRIT / EROARE';
    waiting='În așteptare...'; history='Istoric - verde: arhivat | portocaliu: incomplet | roșu: eroare'; colLesson='Lecție'; colStatus='Status'; colProgress='Progres'; colDetails='Detalii';
    openFolder='Deschide folder'; openIndex='Deschide biblioteca'; openLog='Deschide jurnal'; elapsed='Timp rulat'; lastActivity='Ultima activitate'; noActivity='Fără progres recent'; active='Activ'; stopped='Oprit';
    archived='ARHIVAT'; downloaded='DESCĂRCAT'; incomplete='INCOMPLET'; error='EROARE'; running='ÎN CURS';
    chooseFolder='Alege folderul arhivei cursurilor'; chooseSections='Selectează subgrupele Skool'; useSelection='Folosește selecția'; selectAll='Bifează toate'; deselectAll='Debifează';
    noSections='Nu am găsit subgrupe accesibile.'; selectOne='Bifează cel puțin o subgrupă.'; selected='SELECTATE'; sections='subgrupe'; courses='cursuri';
    linkNeeded='Introdu un link https://www.skool.com/... valid.'; linkRequired='Link necesar'; updateWhileWorking='Oprește sau finalizează descărcările înainte de actualizare.';
    loginFailed='Autentificarea Skool nu s-a finalizat.'; noJournal='Nu există încă un jurnal al operației.'; missingIndex='Biblioteca nu există încă. Descarcă un curs sau apasă Actualizează paginile.';
    closeBusy='O descărcare este activă. Oprești procesul și închizi aplicația?'; closeTitle='Închide'; startup='Aplicația este pregătită. Arhiva:';
    stateWarning='Procesul rulează, dar nu a trimis recent progres.';
    notifyCheck='Verific versiunea disponibilă...';
    notifyAvailable='Actualizare disponibilă:';
    notifyFailed='Nu pot verifica actualizările:';
    pausedLog='Pauză. Conexiunile pot expira; fișierele salvate rămân intacte.';
    resumedLog='Transferurile au fost reluate.';
    stopLog='Oprire solicitată. Fișierele complete sunt păstrate; descărcările parțiale pot fi reluate când sursa permite.';
    startedLog='Pornit:';
    startError='Nu pot porni:';
    auditLog='Audit arhivă:';
    loginLog='LOGIN EȘUAT:';
    logLabel='Jurnal:';
    logComplete='Lecții complete';
    logIncomplete='incomplete';
    logInvalid='invalide';
    updateTitle='ACTUALIZĂRI APLICAȚIE'; installedVersion='Versiune instalată'; back='Înapoi la descărcări'; checkUpdates='Verifică actualizările'; installUpdate='Instalează actualizarea'; rollback='Revino la versiunea anterioară'; restart='Repornește aplicația';
    updateInstruction='Verifică actualizările fără a părăsi această fereastră. Cursurile și autentificarea rămân locale.'; updateNotConfigured='Sursa de actualizare online nu este configurată.';
    updateChecking='Verific actualizările...'; updateWorking='În curs...'; updateNoChanges='Ai deja cea mai nouă versiune.'; updatePendingRestart='Actualizarea a fost instalată. Repornește aplicația pentru a încărca versiunea nouă.';
    updateNoRollback='Nu există o copie de rezervă disponibilă.'; updateConfirm='Instalezi actualizarea verificată? Cursurile și autentificarea vor fi păstrate.';
    updateRollbackConfirm='Restaurezi ultima copie de rezervă a aplicației?'; updateFailed='Actualizarea a eșuat'; updateStarted='Pregătesc actualizarea...'; updateBusy='Există deja o operație de actualizare.';
    progressDone=' - OK'; progressFailed=' - EROARE'; infoCourse='Curs'; infoLessons='lecții'; infoVideoFailed='Descărcarea video a eșuat'; infoLessonError='Eroare la lecție';
    infoIndex='Pagini de curs actualizate'; infoCourses='cursuri'; infoCatalog='Subgrupe găsite'; infoSession='Sesiune finalizată'; infoErrors='erori'; infoNoUpdates='Nu există actualizări disponibile';
    accessUnconfirmed='acces neconfirmat'; selectAvailable='subgrupe disponibile'; selectLessons='lecții/module'; selectedUnit='subgrupe'; tempLabel='TEMP';
    resources='Text, linkuri, atașamente'; maxFour='maximum 4 descărcări simultane'; jobFailed='Proces încheiat'; loginUnknown='Cauza exactă se găsește în jurnalul local.';
    pauseError='Pauza nu este disponibilă'; pauseSafety='Nu pot suspenda în siguranță toate procesele copil. Pauza a fost anulată.'; resumeWarning='AVERTISMENT: unele procese nu au putut fi reluate';
    updateWorkerMissing='Componenta pentru actualizări lipsește.'; indexReady='Pagini de curs actualizate';

  }
}
function Tr([string]$key) {
  $value=$script:translations[$script:language][$key]
  if(-not $value){$value=$script:translations.en[$key]}
  return [string]$value
}
function SetState([string]$state){$script:currentState=$state;if($script:stateLabel){$script:stateLabel.Text=Tr $state}}
function Set-ExistingLanguagePreference([string]$value){
  if($script:cfg.PSObject.Properties['language']){$script:cfg.language=$value}
  else{$script:cfg|Add-Member -NotePropertyName 'language' -NotePropertyValue $value}
}

function Color([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function MakeLabel($text, $x, $y, $w, $h, $fontSize=10, $bold=$false) {
  $l = New-Object Windows.Forms.Label
  $l.Text = $text; $l.SetBounds($x,$y,$w,$h)
  $style = [Drawing.FontStyle]::Regular
  if($bold){$style = [Drawing.FontStyle]::Bold}
  $l.Font = New-Object Drawing.Font('Segoe UI',$fontSize,$style)
  $l.ForeColor = Color '#283747'; $l.BackColor = [Drawing.Color]::Transparent
  return $l
}
function MakeButton($text,$x,$y,$w,$h){
  $b=New-Object Windows.Forms.Button
  $b.Text=$text; $b.SetBounds($x,$y,$w,$h)
  $b.Font=New-Object Drawing.Font('Segoe UI',10)
  $b.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderColor=Color '#bdc8d9'
  $b.BackColor=Color '#ffffff'; $b.ForeColor=Color '#243346'
  return $b
}
function Trace($message){
  if(-not $message){return}
  $time = (Get-Date).ToString('HH:mm:ss')
  $script:logBox.AppendText("[$time] $message`r`n")
  if($script:logBox.Lines.Count -gt 200){$script:logBox.Text = (($script:logBox.Lines | Select-Object -Last 100) -join "`r`n")+"`r`n"}
  $script:logBox.SelectionStart = $script:logBox.TextLength
  $script:logBox.ScrollToCaret()
}
function RecordStatus($id,$title,$status,$percent,$detail=''){
  if(-not $script:historyList){return}
  $key = $script:activeCourse + '/' + $id
  $item=$null
  if($script:historyItems.ContainsKey($key)){$item=$script:historyItems[$key]}
  else{
    $item=New-Object Windows.Forms.ListViewItem([string]$title)
    [void]$item.SubItems.Add('')
    [void]$item.SubItems.Add('')
    [void]$item.SubItems.Add('')
    [void]$script:historyList.Items.Add($item)
    $script:historyItems[$key]=$item
  }
  $item.Text=[string]$title
  $item.Tag=[string]$status
  $statusKey=switch($status){'DESCARCAT'{'downloaded'}'ARHIVAT'{'archived'}'EROARE'{'error'}'INCOMPLET'{'incomplete'}default{'running'}}
  $item.SubItems[1].Text=Tr $statusKey
  $item.SubItems[2].Text=([Math]::Min(100,[Math]::Max(0,[double]$percent))).ToString('0')+'%'
  $item.SubItems[3].Text=[string]$detail
  $item.ForeColor = switch($status) {
    'DESCARCAT' {Color '#147d43'}
    'EROARE' {Color '#b82f3c'}
    'ARHIVAT' {Color '#147d43'}
    'INCOMPLET' {Color '#a5680b'}
    default {Color '#26384e'}
  }
  if($status -in @('DESCARCAT','ARHIVAT','EROARE','INCOMPLET')){
    try {
      $folder=Join-Path ([string]$script:cfg.tempPath) '_history'
      [void][IO.Directory]::CreateDirectory($folder)
      $log=Join-Path $folder 'downloads.jsonl'
      $entry=@{time=(Get-Date).ToString('o');course=$script:activeCourse;item=$title;status=$status;detail=$detail}
      [IO.File]::AppendAllText($log,(($entry|ConvertTo-Json -Compress -Depth 4)+"`n"),[Text.UTF8Encoding]::new($false))
    }catch{}
  }
}
function ShowSelectionDialog($catalog){
  if(-not $catalog -or -not $catalog.items){Trace (Tr 'noSections');return}
  $d=New-Object Windows.Forms.Form
  $d.Text=Tr 'chooseSections'
  $d.ClientSize=New-Object Drawing.Size(650,530)
  $d.StartPosition='CenterParent';$d.FormBorderStyle='FixedDialog';$d.MaximizeBox=$false
  $d.Font=New-Object Drawing.Font('Segoe UI',10)
  $label=MakeLabel ([string]$catalog.name+' - '+$catalog.items.Count+' '+(Tr 'selectAvailable')) 17 13 615 28 11 $true
  $d.Controls.Add($label)
  $list=New-Object Windows.Forms.CheckedListBox
  $list.SetBounds(17,48,615,393);$list.CheckOnClick=$true;$list.HorizontalScrollbar=$true
  $all=@($catalog.items)
  foreach($it in $all){$label=[string]$it.title+' ('+[string]$it.count+' '+(Tr 'selectLessons')+')';if([string]$it.accessStatus -eq 'unconfirmed'){$label+=' ['+(Tr 'accessUnconfirmed')+']'};[void]$list.Items.Add($label,$true)}
  $d.Controls.Add($list)
  $yes=MakeButton (Tr 'useSelection') 450 455 182 42
  $mark=MakeButton (Tr 'selectAll') 17 455 145 42
  $clear=MakeButton (Tr 'deselectAll') 176 455 145 42
  $d.Controls.Add($yes);$d.Controls.Add($mark);$d.Controls.Add($clear)
  $mark.Add_Click({for($i=0;$i -lt $list.Items.Count;$i++){$list.SetItemChecked($i,$true)}})
  $clear.Add_Click({for($i=0;$i -lt $list.Items.Count;$i++){$list.SetItemChecked($i,$false)}})
  $yes.Add_Click({
    if($list.CheckedIndices.Count -eq 0){[void][Windows.Forms.MessageBox]::Show((Tr 'selectOne'));return}
    $script:selectedKeys=@(foreach($i in $list.CheckedIndices){[string]$all[[int]$i].key})
    $script:selectedLevel=[string]$catalog.level
    $script:selectedUrl=$script:urlText.Text.Trim()
    $script:selectionSummary.Text=(Tr 'selected')+': '+$script:selectedKeys.Count+' / '+$all.Count+' '+$(if($catalog.level -eq 'modules'){Tr 'sections'}else{Tr 'courses'})
    $d.DialogResult=[Windows.Forms.DialogResult]::OK;$d.Close()
  })
  [void]$d.ShowDialog($form)
  $d.Dispose()
}
function StartNoticeCheck(){
  if(-not [string]$script:cfg.updateManifestSource -and -not [string]$script:cfg.updateManifestFallback){return}
  if(-not (Test-Path -LiteralPath (Join-Path $script:AppRoot 'check_update_notice.cjs'))){return}
  if((Get-Date) -lt $script:nextNotice){return}
  $script:nextNotice=(Get-Date).AddHours(12)
  try{
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:noticeFile))
    $p=New-Object Diagnostics.ProcessStartInfo
    $p.FileName=$script:nodeExe
    $p.Arguments='"'+(Join-Path $script:AppRoot 'check_update_notice.cjs')+'" "'+$script:ConfigPath+'" "'+$script:noticeFile+'"'
    $p.WorkingDirectory=$script:AppRoot;$p.UseShellExecute=$false;$p.CreateNoWindow=$true
    $proc=[Diagnostics.Process]::Start($p)
    $script:noticeStarted=Get-Date
    Trace (Tr 'notifyCheck')
  }catch{Trace ((Tr 'notifyFailed')+' '+$_)}
}
function ObserveNotice(){
  if(-not (Test-Path -LiteralPath $script:noticeFile)){return}
  try{
    $file=Get-Item -LiteralPath $script:noticeFile
    if($file.LastWriteTime -le $script:noticeObserved){return}
    $script:noticeObserved=$file.LastWriteTime
    $notice=Get-Content -LiteralPath $file.FullName -Encoding UTF8 -Raw | ConvertFrom-Json
    if(([datetime]$notice.checkedAt) -lt $script:sessionStarted){return}
    if([string]$notice.status -eq 'available' -and [string]$notice.version -ne $script:knownUpdate){
      $script:knownUpdate=[string]$notice.version
      $script:updatesBtn.Text='Update '+$script:knownUpdate
      $script:updatesBtn.BackColor=Color '#fff0c9'
      Trace ((Tr 'notifyAvailable')+' '+$script:knownUpdate)
      if($script:trayIcon){
        $script:trayIcon.BalloonTipTitle='Instant Downloader - '+(Tr 'notifyAvailable')
        $script:trayIcon.BalloonTipText=(Tr 'notifyAvailable')+' '+$script:knownUpdate
        $script:trayIcon.BalloonTipIcon=[Windows.Forms.ToolTipIcon]::Info
        $script:trayIcon.ShowBalloonTip(6000)
      }
    }
  }catch{Trace ((Tr 'updateFailed')+': '+$_)}
}
function UpdateButtons(){
  $running = $script:jobProcess -and (-not $script:jobProcess.HasExited)
  $script:startBtn.Enabled = (-not $running) -and (-not $script:updatePendingRestart)
  $script:loginBtn.Enabled = (-not $running) -and (-not $script:updatePendingRestart)
  $script:indexBtn.Enabled = (-not $running) -and (-not $script:updatePendingRestart)
  if($script:selectBtn){$script:selectBtn.Enabled = (-not $running) -and (-not $script:updatePendingRestart)}
  $script:pauseBtn.Enabled = $running -and (-not $script:isPaused) -and $script:runningMode -eq 'download'
  $script:resumeBtn.Enabled = $running -and $script:isPaused
  $script:stopBtn.Enabled = $running
  if($script:updatesBtn){$script:updatesBtn.Enabled = (-not $running)}
}
function SaveConfig(){
  $script:cfg.archivePath = $script:archiveText.Text.Trim()
  $script:cfg.lastUrl = $script:urlText.Text.Trim()
  $script:cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}
function SelectFolder($initial){
  $dlg=New-Object Windows.Forms.FolderBrowserDialog
  $dlg.Description=Tr 'chooseFolder'
  if(Test-Path -LiteralPath $initial){$dlg.SelectedPath=$initial}
  if($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){return $dlg.SelectedPath}
  return $null
}
function ResetSlots(){
  $script:slotItems.Clear();$script:slotOrder.Clear();$script:failedVideos.Clear()
  for($i=0;$i -lt 4;$i++){
    $script:entries[$i].name.Text=Tr 'waiting'
    $script:entries[$i].bar.Value=0
    $script:entries[$i].active=$false;$script:entries[$i].finished=$false
    $script:entries[$i].pct.Text='[                    ]   0%'
  }
}
function SetSlot($id,$title,$percent,$status='active'){
  if(-not $script:slotItems.ContainsKey($id)) {
    $free = @($script:entries | Where-Object { -not $_.active -and -not $_.finished }) | Select-Object -First 1
    if($free) { $slot=$free.index }
    else {
      # Replace completed slots first; never replace an active video while tracking progress.
      $recycle = @($script:entries | Where-Object {$_.finished}) | Select-Object -First 1
      if(-not $recycle){return}
      $slot=$recycle.index
      foreach($k in @($script:slotItems.Keys)) { if($script:slotItems[$k] -eq $slot) {$script:slotItems.Remove($k);break} }
    }
    $script:slotItems[$id] = $slot
  }
  $slot=$script:slotItems[$id]
  $entry=$script:entries[$slot]
  $percent=[int][Math]::Max(0,[Math]::Min(100,[Math]::Round([double]$percent)))
  $entry.active=($status -eq 'active')
  $entry.finished=($status -ne 'active')
  $suffix = switch($status){'done' {Tr 'progressDone'}'failed'{Tr 'progressFailed'}default{''}}
  $entry.name.Text = $title + $suffix
  $entry.bar.Value=$percent
  $filled=[int][Math]::Round(20*$percent/100.0)
  $entry.pct.Text = '[' + ('=' * $filled) + (' ' * (20-$filled)) + '] ' + $percent.ToString().PadLeft(3) + '%'
}
function GetProcessTree($rootPid){
  $all=@(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
  $current=@([int]$rootPid)
  $found=New-Object System.Collections.ArrayList
  [void]$found.Add([int]$rootPid)
  for($k=0;$k -lt 8;$k++){
    $next = @()
    foreach($p in $all){
      if($current -contains [int]$p.ParentProcessId -and -not $found.Contains([int]$p.ProcessId)){
        $next+= [int]$p.ProcessId;[void]$found.Add([int]$p.ProcessId)
      }
    }
    if($next.Count -eq 0){break};$current=$next
  }
  return @($found.ToArray())
}
function PauseProcess(){
  if(-not $script:jobProcess -or $script:jobProcess.HasExited){return}
  try{
    $tree=@(GetProcessTree $script:jobProcess.Id)
    $script:pausedPids = @()
    [Array]::Reverse($tree)
    foreach($pidToPause in $tree){
      try{[SkoolProcessControl]::Suspend([int]$pidToPause);$script:pausedPids+= [int]$pidToPause}catch{}
    }
    if($script:pausedPids.Count -ne $tree.Count){
      foreach($stopped in $script:pausedPids){try{[SkoolProcessControl]::Resume([int]$stopped)}catch{}}
      $script:pausedPids=@()
      throw (Tr 'pauseSafety')
    }
    $script:isPaused=$true
    SetState 'paused'
    Trace (Tr 'pausedLog')
  }catch{Trace ((Tr 'pauseError')+': '+$_)}
  UpdateButtons
}
function ResumeProcess(){
  if(-not $script:isPaused){return}
  $resumeOrder = @($script:pausedPids)
  [Array]::Reverse($resumeOrder)
  $failed=@()
  foreach($pidToResume in $resumeOrder){
    try{[SkoolProcessControl]::Resume([int]$pidToResume)}catch{$failed+=$pidToResume}
  }
  if($failed.Count -gt 0){Trace ((Tr 'resumeWarning')+': '+$failed.Count)}
  $script:isPaused=$false;$script:pausedPids=@()
  SetState 'downloading'
  Trace (Tr 'resumedLog')
  UpdateButtons
}
function StopProcess(){
  if(-not $script:jobProcess -or $script:jobProcess.HasExited){return}
  if($script:isPaused){ResumeProcess}
  Trace (Tr 'stopLog')
  SetState 'stopping'
  try{$taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'; & $taskkill /PID $script:jobProcess.Id /T /F 2>$null | Out-Null}catch{}
  UpdateButtons
}
function StartJob([string]$mode,[string]$url=''){
  if($script:jobProcess -and -not $script:jobProcess.HasExited){return}
  try{
    SaveConfig
    if($mode -in @('download','scan')){
      if($url -notmatch '^https?://([\w-]+\.)?skool\.com/'){
        [System.Windows.Forms.MessageBox]::Show((Tr 'linkNeeded'),(Tr 'linkRequired'))|Out-Null;return
      }
    }
    $base=$script:cfg.tempPath
    $temp=Join-Path $base '_temp'
    $jobs=Join-Path $base '_jobs'
    foreach($p in @($base,$temp,$jobs,(Join-Path $base '_cache'),(Join-Path $base '_browsers'))){
      [void][IO.Directory]::CreateDirectory($p)
    }
    [void][IO.Directory]::CreateDirectory($script:archiveText.Text)
    $id=[guid]::NewGuid().ToString('N')
    $script:jobLog=Join-Path $jobs "$id.log"
    $jobPath=Join-Path $jobs "$id.json"
    $sel=@{level='all';keys=@()}
    if($mode -eq 'download' -and $script:selectedUrl -eq $url -and $script:selectedKeys.Count -gt 0){
      $sel=@{level=$script:selectedLevel;keys=@($script:selectedKeys)}
    }
    $job=@{mode=$mode;url=$url;output=$script:archiveText.Text;temp=$temp;tempRoot=$base;logPath=$script:jobLog;selection=$sel}
    # PowerShell 5.1 UTF8 JSON has BOM. Node can only parse BOM-less JSON.
    [IO.File]::WriteAllText($jobPath,($job|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $script:offset=0;$script:remainder='';$script:pendingUtf8Bytes=[byte[]]@();$script:lastError='';$script:completeErrors=0;$script:runningMode=$mode;$script:loginSucceeded=$false;$script:isPaused=$false
    $script:operationStart=Get-Date;$script:lastActivity=$script:operationStart;$script:operationElapsed=[TimeSpan]::Zero
    $script:pausedPids=@();$script:failedVideos=@{}
    if($mode -eq 'download'){ResetSlots;$script:historyItems.Clear();$script:historyList.Items.Clear();$script:activeCourse=''}
    if($mode -eq 'scan'){$script:catalogResult=$null}
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$script:nodeExe
    $psi.Arguments='"'+(Join-Path $script:AppRoot 'supervisor.cjs')+'" "'+$jobPath+'"'
    $psi.WorkingDirectory=$script:AppRoot
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    if(-not $p.Start()){throw 'Cannot start Node.js.'}
    $script:jobProcess=$p
    SetState $(if($mode -eq 'download'){'downloading'}elseif($mode -eq 'login'){'loggingin'}elseif($mode -eq 'scan'){'scanning'}else{'indexing'})
    Trace ((Tr 'startedLog')+' ' + $mode + $(if($mode -eq 'download'){' | '+(Tr 'maxFour')}else{''}))
    UpdateButtons
  }catch{Trace ((Tr 'startError')+' '+$_);[System.Windows.Forms.MessageBox]::Show("Eroare: $_",'Instant Downloader')|Out-Null}
}
function ProcessLine([string]$line){
  if([string]::IsNullOrWhiteSpace($line)){return}
  $script:lastActivity=Get-Date
  if($line.StartsWith('@@SKOOL@@')){
    try{$msg=$line.Substring(9)|ConvertFrom-Json}catch{return}
    switch([string]$msg.type){
      'login-success' {$script:loginSucceeded=$true;Trace ('OK: '+[string]$msg.message)}
      'course' {ResetSlots;$script:activeCourse=[string]$msg.title;Trace((Tr 'infoCourse')+': '+$msg.title+' ('+$msg.lessons+' '+(Tr 'infoLessons')+')')}
      'start' {SetSlot ([string]$msg.id) ([string]$msg.title) 0;RecordStatus ([string]$msg.id) ([string]$msg.title) 'IN CURS' 0}
      'progress' {SetSlot ([string]$msg.id) ([string]$msg.title) ([double]$msg.percent);RecordStatus ([string]$msg.id) ([string]$msg.title) 'IN CURS' ([double]$msg.percent)}
      'done' {
        if($script:failedVideos.ContainsKey([string]$msg.id)){SetSlot ([string]$msg.id) ([string]$msg.title) 0 'failed'}
        elseif($msg.hasVideo){SetSlot ([string]$msg.id) ([string]$msg.title) 100 'done';RecordStatus ([string]$msg.id) ([string]$msg.title) 'DESCARCAT' 100}
        else{SetSlot ([string]$msg.id) ([string]$msg.title) 100 'done';RecordStatus ([string]$msg.id) ([string]$msg.title) 'ARHIVAT' 100 ((Tr 'resources')+': '+[string]$msg.resourcesCount)}
      }
      'failed-video' {$script:failedVideos[[string]$msg.id]=$true;SetSlot ([string]$msg.id) ([string]$msg.title) 0 'failed';RecordStatus ([string]$msg.id) ([string]$msg.title) 'EROARE' 0 (Tr 'infoVideoFailed');Trace((Tr 'infoVideoFailed')+': '+$msg.title)}
      'failed' {SetSlot ([string]$msg.id) ([string]$msg.title) 0 'failed';RecordStatus ([string]$msg.id) ([string]$msg.title) 'EROARE' 0 ([string]$msg.reason);Trace((Tr 'infoLessonError')+': '+$msg.title)}
      'error' {Trace([string]$msg.message);$script:lastError=[string]$msg.message}
      'fatal' {Trace('EROARE: '+$msg.message);$script:lastError=[string]$msg.message}
      'info' {Trace([string]$msg.message)}
      'audit' {
        Trace ((Tr 'auditLog')+' '+$msg.complete+' '+(Tr 'logComplete')+'; '+$msg.incomplete+' '+(Tr 'logIncomplete')+'; '+$msg.invalid+' '+(Tr 'logInvalid'))
        foreach($it in $msg.issues){
          RecordStatus ([string]$it.id) ([string]$it.lesson) 'INCOMPLET' 100 ([string]($it.problems -join '; '))
        }
      }
      'index' {Trace((Tr 'infoIndex')+': '+$msg.count+' '+(Tr 'infoCourses'))}
      'catalog' {$script:catalogResult=$msg;Trace((Tr 'infoCatalog')+': '+$msg.items.Count)}
      'complete' {$bad=@($script:historyList.Items | Where-Object {$_.Tag -eq 'EROARE'}).Count;$script:completeErrors=[Math]::Max([int]$msg.failed,$bad);Trace((Tr 'infoSession')+': '+$script:completeErrors+' '+(Tr 'infoErrors'))}
      'exit' {if($msg.code -ne 0){Trace('Procesul a iesit cu codul '+$msg.code)}}
    }
  }else{
    if($line -match '(?i)(error|exception|failed|fatal|EROARE)') {Trace(($line -replace '(https?://\S+)','[link]'))}
  }
}
function CheckLog(){
  if(-not $script:jobLog -or -not (Test-Path -LiteralPath $script:jobLog)){return}
  try{
    $fs=New-Object IO.FileStream($script:jobLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
      if($script:offset -gt $fs.Length){$script:offset=0;$script:pendingUtf8Bytes=[byte[]]@()}
      $length=[int][Math]::Min(($fs.Length-$script:offset),1024*1024)
      if($length -le 0){return}
      [void]$fs.Seek($script:offset,[IO.SeekOrigin]::Begin)
      $bytes=New-Object byte[] $length
      $read=$fs.Read($bytes,0,$length)
      $script:offset += $read
    }finally{$fs.Dispose()}
    if($read -le 0){return}
    $before=[byte[]]$script:pendingUtf8Bytes
    $full=New-Object byte[] ($before.Length+$read)
    [Array]::Copy($before,0,$full,0,$before.Length)
    [Array]::Copy($bytes,0,$full,$before.Length,$read)
    $lineStart=0
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    for($j=0;$j -lt $full.Length;$j++){
      if($full[$j] -eq 10){
        $len=$j-$lineStart
        if($len -gt 0){
          try{$line=$utf8.GetString($full,$lineStart,$len).TrimEnd([char]13);ProcessLine $line}
          catch{Trace ('Skipped an invalid UTF-8 log line. Original archive data is unchanged.')}
        }
        $lineStart=$j+1
      }
    }
    $pending=$full.Length-$lineStart
    $script:pendingUtf8Bytes=New-Object byte[] $pending
    if($pending -gt 0){[Array]::Copy($full,$lineStart,$script:pendingUtf8Bytes,0,$pending)}
  }catch{}
}
$form=New-Object Windows.Forms.Form
$form.Text='Instant Downloader v1.8 RC11 - Skool'
$form.ClientSize=New-Object Drawing.Size(910,845)
$form.StartPosition='CenterScreen';$form.MaximizeBox=$false
$form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.BackColor=Color '#f2f5f8';$form.Font=New-Object Drawing.Font('Segoe UI',10)
$brand=MakeLabel 'INSTANT DOWNLOADER' 24 15 650 40 21 $true;$form.Controls.Add($brand)
$languageCaption=MakeLabel (Tr 'language') 660 22 80 22 9;$form.Controls.Add($languageCaption)
$languageBox=New-Object Windows.Forms.ComboBox
$languageBox.SetBounds(742,17,133,30);$languageBox.DropDownStyle='DropDownList'
[void]$languageBox.Items.Add('English');[void]$languageBox.Items.Add('Română')
$languageBox.SelectedIndex=if($script:language -eq 'ro'){1}else{0}
$form.Controls.Add($languageBox)
$subtitleLabel=MakeLabel (Tr 'subtitle') 27 55 830 26 10;$form.Controls.Add($subtitleLabel)
$urlLabel=MakeLabel (Tr 'courseUrl') 27 100 360 22 10 $true;$form.Controls.Add($urlLabel)
$urlText=New-Object Windows.Forms.TextBox
$urlText.SetBounds(27,126,678,31);$urlText.Text=[string]$script:cfg.lastUrl
$urlText.Font=New-Object Drawing.Font('Segoe UI',11)
$form.Controls.Add($urlText);$script:urlText=$urlText
$selectBtn=MakeButton (Tr 'subgroups') 717 126 158 31;$form.Controls.Add($selectBtn);$script:selectBtn=$selectBtn
$selectBtn.Add_Click({StartJob 'scan' $script:urlText.Text.Trim()})
$selectionSummary=MakeLabel (Tr 'allSections') 27 157 848 18 8
$form.Controls.Add($selectionSummary);$script:selectionSummary=$selectionSummary
$urlText.Add_TextChanged({if($script:selectedUrl -ne $urlText.Text.Trim()){$script:selectedKeys=@();$script:selectedLevel='all';$script:selectionSummary.Text=Tr 'allSections'}})
$archiveLabel=MakeLabel (Tr 'archive') 27 178 320 20 10 $true;$form.Controls.Add($archiveLabel)
$archiveText=New-Object Windows.Forms.TextBox;$archiveText.SetBounds(27,196,730,30)
$archiveText.Text=[string]$script:cfg.archivePath
$form.Controls.Add($archiveText);$script:archiveText=$archiveText
$browseBtn=MakeButton (Tr 'browse') 771 195 104 32;$form.Controls.Add($browseBtn)
$browseBtn.Add_Click({$p=SelectFolder $script:archiveText.Text;if($p){$script:archiveText.Text=$p;SaveConfig}})
$form.Controls.Add((MakeLabel ((Tr 'tempLabel')+': '+$script:cfg.tempPath) 27 234 820 24 9))
$startBtn=MakeButton (Tr 'start') 27 274 135 41; $startBtn.BackColor=Color '#e0f4e8';$startBtn.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$pauseBtn=MakeButton (Tr 'pause') 174 274 128 41
$resumeBtn=MakeButton (Tr 'resume') 314 274 128 41
$stopBtn=MakeButton (Tr 'stop') 454 274 110 41;$stopBtn.BackColor=Color '#ffe6e8'
$loginBtn=MakeButton (Tr 'login') 577 274 142 41
$indexBtn=MakeButton (Tr 'rebuild') 733 274 142 41
foreach($b in @($startBtn,$pauseBtn,$resumeBtn,$stopBtn,$loginBtn,$indexBtn)){$form.Controls.Add($b)}
$script:startBtn=$startBtn;$script:pauseBtn=$pauseBtn;$script:resumeBtn=$resumeBtn;$script:stopBtn=$stopBtn;$script:loginBtn=$loginBtn;$script:indexBtn=$indexBtn
$stateLabel=MakeLabel (Tr 'ready') 27 332 205 27 11 $true;$form.Controls.Add($stateLabel);$script:stateLabel=$stateLabel
$elapsedLabel=MakeLabel '' 253 334 235 24 10 $true;$form.Controls.Add($elapsedLabel);$script:elapsedLabel=$elapsedLabel
$activityLabel=MakeLabel '' 500 334 220 24 9;$form.Controls.Add($activityLabel);$script:activityLabel=$activityLabel
$updatesBtn=MakeButton (Tr 'updates') 731 329 144 30;$form.Controls.Add($updatesBtn);$script:updatesBtn=$updatesBtn
$updatesBtn.Add_Click({
  $script:updatePanel.Visible=$true
  $script:updatePanel.BringToFront()
  $script:updateInstalledLabel.Text=(Tr 'installedVersion')+': '+[string]$script:cfg.version
  if(-not $script:updateChecked -and -not $script:updateProc){Start-UpdateWorker 'Check'}
})

# Update panel is displayed in the SAME Windows Form. Back returns without stopping downloads.
$script:updateProc=$null
$script:updateWorkFile=''
$script:updateChecked=$false
$script:updateSource=''
$script:updateVersion=''
$script:updatePendingRestart=$false
$script:updateLastMessage=''
$script:updateAction=''
$script:updatePanel=New-Object Windows.Forms.Panel
$script:updatePanel.SetBounds(0,0,910,845)
$script:updatePanel.BackColor=Color '#f2f5f8'
$script:updatePanel.Visible=$false
$form.Controls.Add($script:updatePanel)
function UpdateLabel($text,$x,$y,$w,$h,$size=10,$bold=$false){$a=MakeLabel $text $x $y $w $h $size $bold;$script:updatePanel.Controls.Add($a);return $a}
$script:updateHeading=UpdateLabel (Tr 'updateTitle') 32 30 790 46 20 $true
$script:updateInstalledLabel=UpdateLabel ((Tr 'installedVersion')+': '+[string]$script:cfg.version) 32 88 700 30 11
$script:updateDescription=UpdateLabel (Tr 'updateInstruction') 32 132 822 58 10
$script:backBtn=MakeButton (Tr 'back') 32 211 205 44
$script:checkUpdateBtn=MakeButton (Tr 'checkUpdates') 250 211 205 44
$script:installUpdateBtn=MakeButton (Tr 'installUpdate') 468 211 205 44
$script:installUpdateBtn.Enabled=$false
$script:installUpdateBtn.BackColor=Color '#def2e5'
foreach($b in @($script:backBtn,$script:checkUpdateBtn,$script:installUpdateBtn)){$script:updatePanel.Controls.Add($b)}
$script:updateStatusLabel=UpdateLabel (Tr 'ready') 32 283 818 33 12 $true
$script:updateStatusBar=New-Object Windows.Forms.ProgressBar
$script:updateStatusBar.SetBounds(32,329,822,16)
$script:updateStatusBar.Style=[Windows.Forms.ProgressBarStyle]::Continuous
$script:updatePanel.Controls.Add($script:updateStatusBar)
$script:updateDetails=New-Object Windows.Forms.TextBox
$script:updateDetails.Multiline=$true;$script:updateDetails.ReadOnly=$true
$script:updateDetails.ScrollBars=[Windows.Forms.ScrollBars]::Vertical
$script:updateDetails.SetBounds(32,369,822,157)
$script:updateDetails.Font=New-Object Drawing.Font('Consolas',10)
$script:updatePanel.Controls.Add($script:updateDetails)
$script:rollbackUpdateBtn=MakeButton (Tr 'rollback') 32 563 276 43
$script:restartUpdateBtn=MakeButton (Tr 'restart') 571 563 283 43
$script:restartUpdateBtn.Enabled=$false
$script:updatePanel.Controls.Add($script:rollbackUpdateBtn)
$script:updatePanel.Controls.Add($script:restartUpdateBtn)
function Update-Report([string]$message){
  if(-not $message -or $message -eq $script:updateLastMessage){return}
  $script:updateLastMessage=$message
  $script:updateStatusLabel.Text=$message
  $script:updateDetails.AppendText(('['+(Get-Date).ToString('HH:mm:ss')+'] '+$message+"`r`n"))
}
function Start-UpdateWorker([string]$action,[string]$source='', [string]$backup=''){
  if($script:updateProc -and -not $script:updateProc.HasExited){Update-Report (Tr 'updateBusy');return}
  try{
    if($script:jobProcess -and -not $script:jobProcess.HasExited -and $action -ne 'Check'){
      Update-Report (Tr 'updateWhileWorking');return
    }
    SaveConfig
    $updater=Join-Path $script:AppRoot 'Update_Instant_Downloader.ps1'
    if(-not (Test-Path -LiteralPath $updater -PathType Leaf)){throw (Tr 'updateWorkerMissing')}
    $work=Join-Path ([string]$script:cfg.tempPath) '_updates'
    [void][IO.Directory]::CreateDirectory($work)
    $script:updateWorkFile=Join-Path $work ('ui_'+[guid]::NewGuid().ToString('N')+'.json')
    $script:updateLastMessage=''
    $script:updateAction=$action
    $script:updateProc=$null
    $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args='-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "'+$updater+'" -Headless -Action '+$action+' -StatusPath "'+$script:updateWorkFile+'"'
    if($source){$args+=' -Source "'+$source+'"'}
    if($backup){$args+=' -BackupPath "'+$backup+'"'}
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$psExe;$psi.Arguments=$args;$psi.WorkingDirectory=$script:AppRoot
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$psi
    if(-not $process.Start()){throw 'Cannot start update worker.'}
    $script:updateProc=$process
    $script:updateStatusBar.Style=[Windows.Forms.ProgressBarStyle]::Marquee
    $script:checkUpdateBtn.Enabled=$false;$script:installUpdateBtn.Enabled=$false;$script:rollbackUpdateBtn.Enabled=$false
    Update-Report (Tr 'updateWorking')
  }catch{
    Update-Report ((Tr 'updateFailed')+': '+$_)
    $script:checkUpdateBtn.Enabled=$true
  }
}
function Poll-UpdateWorker(){
  if(-not $script:updateProc){return}
  $done=$script:updateProc.HasExited
  if($script:updateWorkFile -and (Test-Path -LiteralPath $script:updateWorkFile)){
    try{
      $msg=Get-Content -LiteralPath $script:updateWorkFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $script:updateLastReportStatus=[string]$msg.status
      $displayText=[string]$msg.message
      if($msg.status -eq 'unconfigured'){$displayText=Tr 'updateNotConfigured'}
      elseif($msg.status -eq 'up_to_date'){$displayText=Tr 'updateNoChanges'}
      elseif($msg.status -eq 'available'){$displayText=(Tr 'notifyAvailable')+' '+[string]$msg.version}
      elseif($msg.status -eq 'installed' -or $msg.status -eq 'restored'){$displayText=Tr 'updatePendingRestart'}
      Update-Report $displayText
      if($msg.status -eq 'available'){
        $script:updateSource=[string]$msg.source;$script:updateVersion=[string]$msg.version
        $script:updateChecked=$true
      }
      if($msg.status -in @('installed','restored')){$script:updatePendingRestart=$true}
    }catch{}
  }
  if(-not $done){return}
  $code=$script:updateProc.ExitCode
  $script:updateProc.Dispose();$script:updateProc=$null
  $script:updateStatusBar.Style=[Windows.Forms.ProgressBarStyle]::Continuous
  $script:updateStatusBar.Value=if($code -eq 0){100}else{0}
  $script:checkUpdateBtn.Enabled=$true;$script:rollbackUpdateBtn.Enabled=$true
  $script:installUpdateBtn.Enabled=([bool]$script:updateSource -and -not $script:updatePendingRestart -and $code -eq 0)
  $script:restartUpdateBtn.Enabled=$script:updatePendingRestart
  if($script:updatePendingRestart){Update-Report (Tr 'updatePendingRestart');UpdateButtons}
  elseif($code -ne 0 -and $script:updateLastReportStatus -ne 'error'){Update-Report ((Tr 'updateFailed')+' (exit '+$code+')')}
}
$script:backBtn.Add_Click({$script:updatePanel.Visible=$false})
$script:checkUpdateBtn.Add_Click({$script:updateSource='';$script:updateChecked=$false;Start-UpdateWorker 'Check'})
$script:installUpdateBtn.Add_Click({
  if(-not $script:updateSource){return}
  if($script:jobProcess -and -not $script:jobProcess.HasExited){Update-Report (Tr 'updateWhileWorking');return}
  $confirm=[Windows.Forms.MessageBox]::Show((Tr 'updateConfirm'),'Instant Downloader', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
  if($confirm -eq [Windows.Forms.DialogResult]::Yes){Start-UpdateWorker 'Install' $script:updateSource}
})
$script:rollbackUpdateBtn.Add_Click({
  if($script:jobProcess -and -not $script:jobProcess.HasExited){Update-Report (Tr 'updateWhileWorking');return}
  $backupRoot=Join-Path ([string]$script:cfg.tempPath) '_updates\backups'
  $backups=@(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'record.json')} | Sort-Object Name -Descending)
  if($backups.Count -eq 0){Update-Report (Tr 'updateNoRollback');return}
  $confirm=[Windows.Forms.MessageBox]::Show((Tr 'updateRollbackConfirm'),'Instant Downloader',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
  if($confirm -eq [Windows.Forms.DialogResult]::Yes){Start-UpdateWorker 'Rollback' '' $backups[0].FullName}
})
$script:restartUpdateBtn.Add_Click({
  if(-not $script:updatePendingRestart){return}
  try{
    $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $gui=Join-Path $script:AppRoot 'Instant_Downloader.ps1'
    Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$gui+'"') -WorkingDirectory $script:AppRoot | Out-Null
    $form.Close()
  }catch{Update-Report ((Tr 'updateFailed')+': '+$_)}
})

for($i=0;$i -lt 4;$i++){
  $y=367+$i*51
  $caption=MakeLabel (Tr 'waiting') 30 $y 445 22 10
  $bar=New-Object Windows.Forms.ProgressBar;$bar.SetBounds(30,($y+26),440,16);$bar.Minimum=0;$bar.Maximum=100;$bar.Value=0
  $pct=MakeLabel '[                    ]   0%' 488 ($y+22) 330 26 10
  $pct.Font=New-Object Drawing.Font('Consolas',11)
  $form.Controls.Add($caption);$form.Controls.Add($bar);$form.Controls.Add($pct)
  $script:entries+=@{index=$i;name=$caption;bar=$bar;pct=$pct;active=$false;finished=$false}
}
$historyLabel=MakeLabel (Tr 'history') 27 578 848 18 9 $true;$form.Controls.Add($historyLabel)
$historyList=New-Object Windows.Forms.ListView
$historyList.SetBounds(27,599,848,124)
$historyList.View=[Windows.Forms.View]::Details
$historyList.FullRowSelect=$true;$historyList.GridLines=$true;$historyList.HideSelection=$false
[void]$historyList.Columns.Add((Tr 'colLesson'),418)
[void]$historyList.Columns.Add((Tr 'colStatus'),120)
[void]$historyList.Columns.Add((Tr 'colProgress'),80)
[void]$historyList.Columns.Add((Tr 'colDetails'),225)
$form.Controls.Add($historyList);$script:historyList=$historyList
$logBox=New-Object Windows.Forms.TextBox
$logBox.Multiline=$true;$logBox.ReadOnly=$true;$logBox.ScrollBars=[System.Windows.Forms.ScrollBars]::Vertical
$logBox.SetBounds(27,765,690,57);$logBox.BackColor=Color '#ffffff'
$logBox.Font=New-Object Drawing.Font('Consolas',9)
$form.Controls.Add($logBox);$script:logBox=$logBox
$folderBtn=MakeButton (Tr 'openFolder') 731 766 144 29
$openIndexBtn=MakeButton (Tr 'openIndex') 731 799 144 29
$form.Controls.Add($folderBtn);$form.Controls.Add($openIndexBtn)
$logBtn=MakeButton (Tr 'openLog') 731 731 144 29
$form.Controls.Add($logBtn)
$logBtn.Add_Click({
  if(-not $script:jobLog -or -not (Test-Path -LiteralPath $script:jobLog)){Trace (Tr 'noJournal');return}
  Start-Process -FilePath notepad.exe -ArgumentList ('"'+$script:jobLog+'"')
})
$folderBtn.Add_Click({if(Test-Path -LiteralPath $script:archiveText.Text){Start-Process -FilePath explorer.exe -ArgumentList ('"'+$script:archiveText.Text+'"')}})
$openIndexBtn.Add_Click({$p=Join-Path $script:archiveText.Text 'index.html';if(Test-Path -LiteralPath $p){Start-Process -FilePath $p}else{Trace (Tr 'missingIndex')}})
$startBtn.Add_Click({StartJob 'download' $script:urlText.Text.Trim()})
$loginBtn.Add_Click({StartJob 'login'})
$indexBtn.Add_Click({StartJob 'index'})
$pauseBtn.Add_Click({PauseProcess})
$resumeBtn.Add_Click({ResumeProcess})
$stopBtn.Add_Click({StopProcess})
$timer=New-Object Windows.Forms.Timer
$timer.Interval=500
$timer.Add_Tick({
  $now=Get-Date
  if($script:operationStart){
    if($script:jobProcess -and -not $script:jobProcess.HasExited){$script:operationElapsed=$now-$script:operationStart}
    $script:elapsedLabel.Text=(Tr 'elapsed')+': '+('{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($script:operationElapsed.TotalHours),$script:operationElapsed.Minutes,$script:operationElapsed.Seconds)
    if($script:jobProcess -and -not $script:jobProcess.HasExited){
      $since=if($script:lastActivity){[int]($now-$script:lastActivity).TotalSeconds}else{0}
      if($script:isPaused){$script:activityLabel.Text=Tr 'paused';$script:activityLabel.ForeColor=Color '#9b6a09'}
      elseif($since -ge 90){$script:activityLabel.Text=(Tr 'noActivity')+' ('+$since+'s)';$script:activityLabel.ForeColor=Color '#aa6600'}
      else{$script:activityLabel.Text=(Tr 'lastActivity')+': '+$since+'s';$script:activityLabel.ForeColor=Color '#147d43'}
    }else{$script:activityLabel.Text=Tr 'stopped';$script:activityLabel.ForeColor=Color '#52637a'}
  }else{$script:elapsedLabel.Text=(Tr 'elapsed')+': 00:00:00';$script:activityLabel.Text=Tr 'ready'}
  CheckLog
  Poll-UpdateWorker
  ObserveNotice
  StartNoticeCheck
  if($script:jobProcess -and $script:jobProcess.HasExited){
    CheckLog
    $code=$script:jobProcess.ExitCode
    $script:jobProcess=$null;$script:isPaused=$false
    if($code -eq 0){SetState 'finished';Trace ((Tr 'infoSession')+' - OK')}
    else {
      SetState 'failed';Trace ((Tr 'jobFailed')+' (exit '+$code+')')
      if($script:runningMode -eq 'login'){ 
      $reason=[string]$script:lastError
      if([string]::IsNullOrWhiteSpace($reason)){
        $last=@(Get-Content -LiteralPath $script:jobLog -Tail 20 -ErrorAction SilentlyContinue)
        $lines=@($last | Where-Object {$_ -match '(?i)(Error|Exception|Cannot|not found|failed|ENOENT|missing|browserType)'})
        if($lines.Count -gt 0){$reason=[string]($lines | Select-Object -Last 1)}
      }
      if([string]::IsNullOrWhiteSpace($reason)){$reason=Tr 'loginUnknown'}
      $reason=($reason -replace '(https?://\S+)','[link]')
      if($reason.Length -gt 360){$reason=$reason.Substring(0,360)+'...'}
      Trace ((Tr 'loginLog')+' '+$reason)
      [void][Windows.Forms.MessageBox]::Show(((Tr 'loginFailed')+[Environment]::NewLine+$reason+[Environment]::NewLine+[Environment]::NewLine+(Tr 'logLabel')+' '+$script:jobLog), 'Instant Downloader - Login', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
      }
    }

    UpdateButtons
    if($code -eq 0 -and $script:runningMode -eq 'scan' -and $script:catalogResult){ShowSelectionDialog $script:catalogResult}
  }
})
$form.Add_FormClosing({param($sender,$eventArgs)
if($script:updateProc -and -not $script:updateProc.HasExited){
  [void][Windows.Forms.MessageBox]::Show((Tr 'updateWorking'),'Instant Downloader')
  $eventArgs.Cancel=$true;return
}
if($script:jobProcess -and -not $script:jobProcess.HasExited){
  $choice=[System.Windows.Forms.MessageBox]::Show((Tr 'closeBusy'), (Tr 'closeTitle'), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
  if($choice -ne [System.Windows.Forms.DialogResult]::Yes){$eventArgs.Cancel=$true;return}
  StopProcess
}})

function Refresh-Language(){
  $languageCaption.Text=Tr 'language';$subtitleLabel.Text=Tr 'subtitle';$urlLabel.Text=Tr 'courseUrl'
  $archiveLabel.Text=Tr 'archive';$selectBtn.Text=Tr 'subgroups';$browseBtn.Text=Tr 'browse'
  $startBtn.Text=Tr 'start';$pauseBtn.Text=Tr 'pause';$resumeBtn.Text=Tr 'resume';$stopBtn.Text=Tr 'stop'
  $loginBtn.Text=Tr 'login';$indexBtn.Text=Tr 'rebuild';$updatesBtn.Text=$(if($script:knownUpdate){'Update '+$script:knownUpdate}else{Tr 'updates'})
  $historyLabel.Text=Tr 'history';$folderBtn.Text=Tr 'openFolder';$openIndexBtn.Text=Tr 'openIndex';$logBtn.Text=Tr 'openLog'
  if(-not $script:selectedKeys -or $script:selectedKeys.Count -eq 0){$script:selectionSummary.Text=Tr 'allSections'}
  $historyList.Columns[0].Text=Tr 'colLesson';$historyList.Columns[1].Text=Tr 'colStatus';$historyList.Columns[2].Text=Tr 'colProgress';$historyList.Columns[3].Text=Tr 'colDetails'
  foreach($item in $script:historyList.Items){
    $key=switch([string]$item.Tag){'DESCARCAT'{'downloaded'}'ARHIVAT'{'archived'}'EROARE'{'error'}'INCOMPLET'{'incomplete'}default{'running'}}
    $item.SubItems[1].Text=Tr $key
  }
  $script:updateHeading.Text=Tr 'updateTitle'
  $script:updateInstalledLabel.Text=(Tr 'installedVersion')+': '+[string]$script:cfg.version
  $script:updateDescription.Text=Tr 'updateInstruction'
  $script:backBtn.Text=Tr 'back';$script:checkUpdateBtn.Text=Tr 'checkUpdates';$script:installUpdateBtn.Text=Tr 'installUpdate'
  $script:rollbackUpdateBtn.Text=Tr 'rollback';$script:restartUpdateBtn.Text=Tr 'restart'
  if(-not $script:updateProc){$script:updateStatusLabel.Text=if($script:updatePendingRestart){Tr 'updatePendingRestart'}else{Tr 'ready'}}
  SetState $script:currentState
  foreach($entry in $script:entries){if(-not $entry.active -and -not $entry.finished){$entry.name.Text=Tr 'waiting'}}
}
$languageBox.Add_SelectedIndexChanged({
  $script:language=if($languageBox.SelectedIndex -eq 1){'ro'}else{'en'}
  Set-ExistingLanguagePreference $script:language
  try{SaveConfig}catch{Trace ('Unable to save language preference: '+$_)}
  Refresh-Language
})
Refresh-Language
$script:trayIcon=New-Object Windows.Forms.NotifyIcon
$script:trayIcon.Icon=[Drawing.SystemIcons]::Information
$script:trayIcon.Text='Instant Downloader'
$script:trayIcon.Visible=$true
UpdateButtons
Trace ((Tr 'startup') + ' ' + $script:archiveText.Text)
$timer.Start()
[void]$form.ShowDialog()
$timer.Stop()
if($script:trayIcon){$script:trayIcon.Visible=$false;$script:trayIcon.Dispose()}
