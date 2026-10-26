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
$script:completionTextKey = ''
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
    appTitle='Instant Downloader'; subtitle='Learning workspace'; sideDownloads='Downloads'; sideLibrary='Course library'; sideUpdates='Updates'; soon='Soon'; sourceHeading='Skool source'; actionsHeading='Download controls'; activityHeading='Download activity'; browserHint='Courses open in your browser'
    language='Language'; courseUrl='Skool Classroom / course link'; subgroups='Choose sections'; allSections='Default: download the entire course. Optionally select specific sections.'
    archive='Course archive folder'; browse='Browse...'; start='Start'; pause='Pause'; resume='Resume'; stop='Stop'; login='Login Skool'; rebuild='Refresh course pages'; updates='Updates';
    ready='READY'; downloading='DOWNLOADING'; loggingin='SIGNING IN'; scanning='SCANNING SECTIONS'; indexing='REFRESHING COURSE PAGES'; paused='PAUSED'; stopping='STOPPING...'; finished='FINISHED'; failed='STOPPED / ERROR';
    waiting='Waiting...'; noActive='No active downloads'; finishedErrors='COMPLETED WITH ERRORS'; completedSuccess='Download completed successfully'; completedWithErrors='Download completed with errors:'; history='History - green: archived | orange: incomplete | red: failed'; colLesson='Lesson'; colStatus='Status'; colProgress='Progress'; colDetails='Details';
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
    appTitle='Instant Downloader'; subtitle='Spațiu pentru descărcări'; sideDownloads='Descărcări'; sideLibrary='Biblioteca'; sideUpdates='Actualizări'; soon='În curând'; sourceHeading='Sursă Skool'; actionsHeading='Comenzi descărcare'; activityHeading='Activitate descărcări'; browserHint='Cursurile se deschid în browser'
    language='Limbă'; courseUrl='Link Skool Classroom / curs'; subgroups='Alege subgrupe'; allSections='Implicit: se descarcă întregul curs. Poți selecta doar anumite subgrupe.';
    archive='Folder arhivă cursuri'; browse='Alege...'; start='Start'; pause='Pauză'; resume='Continuă'; stop='Stop'; login='Login Skool'; rebuild='Actualizează paginile'; updates='Actualizări';
    ready='PREGĂTIT'; downloading='DESCĂRCARE'; loggingin='AUTENTIFICARE'; scanning='CITIRE SUBGRUPE'; indexing='ACTUALIZARE PAGINI'; paused='PAUZĂ'; stopping='OPRIRE...'; finished='FINALIZAT'; failed='OPRIT / EROARE';
    waiting='În așteptare...'; noActive='Nicio descărcare activă'; finishedErrors='FINALIZAT CU ERORI'; completedSuccess='Descărcare finalizată cu succes'; completedWithErrors='Descărcare finalizată cu erori:'; history='Istoric - verde: arhivat | portocaliu: incomplet | roșu: eroare'; colLesson='Lecție'; colStatus='Status'; colProgress='Progres'; colDetails='Detalii';
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
  $d.BackColor=Color '#F7FAFE'
  $label=MakeLabel ([string]$catalog.name+' - '+$catalog.items.Count+' '+(Tr 'selectAvailable')) 17 13 615 28 11 $true
  $d.Controls.Add($label)
  $list=New-Object Windows.Forms.CheckedListBox
  $list.SetBounds(17,48,615,393);$list.CheckOnClick=$true;$list.HorizontalScrollbar=$true
  $list.BackColor=Color '#FFFFFF';$list.BorderStyle=[Windows.Forms.BorderStyle]::FixedSingle
  $all=@($catalog.items)
  foreach($it in $all){$label=[string]$it.title+' ('+[string]$it.count+' '+(Tr 'selectLessons')+')';if([string]$it.accessStatus -eq 'unconfirmed'){$label+=' ['+(Tr 'accessUnconfirmed')+']'};[void]$list.Items.Add($label,$true)}
  $d.Controls.Add($list)
  $yes=MakeButton (Tr 'useSelection') 450 455 182 42
  $mark=MakeButton (Tr 'selectAll') 17 455 145 42
  $clear=MakeButton (Tr 'deselectAll') 176 455 145 42
  $yes.BackColor=Color '#D4E8FB';$yes.ForeColor=Color '#244E79'
  $yes.FlatAppearance.BorderColor=Color '#AFCBE7'
  $mark.BackColor=Color '#F0F6FD';$clear.BackColor=Color '#F0F6FD'
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
function RefreshProgressArea(){
  $visibleCount=0
  foreach($entry in $script:entries){
    $isActive=[bool]$entry.active
    $entry.name.Visible=$isActive
    $entry.bar.Visible=$isActive
    $entry.pct.Visible=$isActive
    if($isActive){$visibleCount++}
  }
  if($script:progressSummary){
    $script:progressSummary.Visible=($visibleCount -eq 0)
    $key=if($script:completionTextKey){$script:completionTextKey}else{'noActive'}
    $script:progressSummary.Text=Tr $key
    if($key -eq 'completedWithErrors'){$script:progressSummary.Text+=' '+$script:completeErrors}
    $script:progressSummary.ForeColor=if($key -eq 'completedSuccess'){Color '#147d43'}elseif($key -eq 'completedWithErrors'){Color '#aa3a32'}else{Color '#61738a'}
  }
}
function ResetSlots(){
  $script:slotItems.Clear();$script:slotOrder.Clear();$script:failedVideos.Clear()
  $script:completionTextKey=''
  foreach($entry in $script:entries){
    $entry.name.Text=''
    $entry.bar.Value=0
    $entry.pct.Text=''
    $entry.active=$false;$entry.finished=$false
  }
  RefreshProgressArea
}
function SetSlot($id,$title,$percent,$status='active'){
  $id=[string]$id
  if($status -ne 'active'){
    if($script:slotItems.ContainsKey($id)){
      $slot=[int]$script:slotItems[$id]
      [void]$script:slotItems.Remove($id)
      $entry=$script:entries[$slot]
      $entry.active=$false;$entry.finished=$false
      $entry.name.Text='';$entry.pct.Text='';$entry.bar.Value=0
    }
    RefreshProgressArea
    return
  }
  if(-not $script:slotItems.ContainsKey($id)){
    $free=@($script:entries | Where-Object {-not $_.active}) | Select-Object -First 1
    if(-not $free){return}
    $script:slotItems[$id]=[int]$free.index
  }
  $slot=[int]$script:slotItems[$id]
  $entry=$script:entries[$slot]
  $percent=[int][Math]::Max(0,[Math]::Min(100,[Math]::Round([double]$percent)))
  $entry.active=$true;$entry.finished=$false
  $entry.name.Text=[string]$title
  $entry.bar.Value=$percent
  $entry.pct.Text=$percent.ToString()+'%'
  RefreshProgressArea
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
    $script:completeErrors=0
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
$form.Text='Instant Downloader v1.8 RC15 - Skool'
$form.ClientSize=New-Object Drawing.Size(910,845)
$form.StartPosition='CenterScreen';$form.MaximizeBox=$false
$form.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.BackColor=Color '#f2f5f8';$form.Font=New-Object Drawing.Font('Segoe UI',10)
$brand=MakeLabel 'INSTANT DOWNLOADER' 24 15 575 40 21 $true;$form.Controls.Add($brand)
$languageCaption=MakeLabel (Tr 'language') 600 22 100 24 10;$form.Controls.Add($languageCaption)
$languageBox=New-Object Windows.Forms.ComboBox
$languageBox.SetBounds(708,17,168,30);$languageBox.DropDownStyle='DropDownList'
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
function ShowUpdatesView{
  $script:updatePanel.Visible=$true
  $script:updatePanel.BringToFront()
  $script:updateInstalledLabel.Text=(Tr 'installedVersion')+': '+[string]$script:cfg.version
  if(-not $script:updateChecked -and -not $script:updateProc){Start-UpdateWorker 'Check'}
}
$updatesBtn.Add_Click({ShowUpdatesView})

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

$script:progressSummary=MakeLabel (Tr 'noActive') 30 385 820 30 11 $true
$form.Controls.Add($script:progressSummary)
for($i=0;$i -lt 4;$i++){
  $y=367+$i*51
  $caption=MakeLabel '' 30 $y 445 22 10
  $bar=New-Object Windows.Forms.ProgressBar;$bar.SetBounds(30,($y+26),440,16);$bar.Minimum=0;$bar.Maximum=100;$bar.Value=0
  $pct=MakeLabel '' 489 ($y+22) 82 24 10 $true
  $pct.TextAlign=[Drawing.ContentAlignment]::MiddleRight
  $form.Controls.Add($caption);$form.Controls.Add($bar);$form.Controls.Add($pct)
  $caption.Visible=$false;$bar.Visible=$false;$pct.Visible=$false
  $script:entries+=@{index=$i;name=$caption;bar=$bar;pct=$pct;active=$false;finished=$false}
}
RefreshProgressArea
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
    if($code -eq 0 -and $script:completeErrors -eq 0){
      SetState 'finished';Trace ((Tr 'infoSession')+' - OK')
      if($script:runningMode -eq 'download'){$script:completionTextKey='completedSuccess'}
    }
    elseif($code -eq 0 -and $script:completeErrors -gt 0){
      SetState 'finishedErrors';Trace ((Tr 'completedWithErrors')+' '+$script:completeErrors)
      if($script:runningMode -eq 'download'){$script:completionTextKey='completedWithErrors'}
    }
    else {
      SetState 'failed';Trace ((Tr 'jobFailed')+' (exit '+$code+')')
      if($script:runningMode -eq 'download'){$script:completionTextKey='completedWithErrors';$script:completeErrors=[Math]::Max(1,$script:completeErrors)}
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

    # A terminated worker cannot have any active transfers. Keep completed
    # lesson records in History and show the final result instead.
    $script:slotItems.Clear()
    foreach($entry in $script:entries){$entry.active=$false;$entry.finished=$false}
    RefreshProgressArea
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
  if($script:navDownloads){$script:navDownloads.Text=Tr 'sideDownloads';$script:navLibrary.Text=Tr 'sideLibrary';$script:navUpdates.Text=Tr 'sideUpdates'}
  if($script:sourceHeading){$script:sourceHeading.Text=Tr 'sourceHeading';$script:actionsHeading.Text=Tr 'actionsHeading';$script:activityHeading.Text=Tr 'activityHeading';$script:sideHint.Text=Tr 'browserHint';$script:sourceTemp.Text=(Tr 'tempLabel')+': '+$script:cfg.tempPath}
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
  RefreshProgressArea
}
$languageBox.Add_SelectedIndexChanged({
  $script:language=if($languageBox.SelectedIndex -eq 1){'ro'}else{'en'}
  Set-ExistingLanguagePreference $script:language
  try{SaveConfig}catch{Trace ('Unable to save language preference: '+$_)}
  Refresh-Language
})
# RC15 Learning Workspace v2: structural WinForms layout, not just recoloring.
# Keep core downloader, update worker and external browser handling unchanged.
$form.ClientSize=New-Object Drawing.Size(1190,908)
$form.BackColor=Color '#F4F7FC'
$form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox=$false
$script:mainContent=New-Object Windows.Forms.Panel
$script:mainContent.SetBounds(204,0,986,908)
$script:mainContent.BackColor=Color '#F7F9FD'
# On smaller displays, scrolling is preferable to clipped controls.
$script:mainContent.AutoScroll=$true
$script:mainContent.AutoScrollMinSize=New-Object Drawing.Size(978,901)
foreach($c in @($form.Controls)){
  if($c -eq $script:updatePanel){continue}
  [void]$form.Controls.Remove($c)
  $script:mainContent.Controls.Add($c)
}
$form.Controls.Add($script:mainContent)

function Move-WorkspaceControl($control,$parent,$x,$y,$w,$h){
  if(-not $control){return}
  if($control.Parent){[void]$control.Parent.Controls.Remove($control)}
  $control.SetBounds([int]$x,[int]$y,[int]$w,[int]$h)
  $parent.Controls.Add($control)
}
function Round-WorkspaceControl($control,[int]$radius=13){
  $bounds=$control.ClientRectangle
  if($bounds.Width -le 0 -or $bounds.Height -le 0){return}
  $d=[Math]::Max(2,[Math]::Min(($radius*2),([Math]::Min($bounds.Width,$bounds.Height)-1)))
  $p=New-Object Drawing.Drawing2D.GraphicsPath
  try{
    $w=$bounds.Width-1;$h=$bounds.Height-1
    $p.AddArc(0,0,$d,$d,180,90)
    $p.AddArc(($w-$d),0,$d,$d,270,90)
    $p.AddArc(($w-$d),($h-$d),$d,$d,0,90)
    $p.AddArc(0,($h-$d),$d,$d,90,90)
    $p.CloseFigure()
    $control.Region=New-Object Drawing.Region($p)
  }finally{$p.Dispose()}
}
function New-WorkspaceCard($x,$y,$w,$h){
  $card=New-Object Windows.Forms.Panel
  $card.SetBounds($x,$y,$w,$h)
  $card.BackColor=Color '#FFFFFF'
  $script:mainContent.Controls.Add($card)
  Round-WorkspaceControl $card 14
  $card.Add_Paint({
    param($sender,$e)
    $e.Graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path=New-Object Drawing.Drawing2D.GraphicsPath
    $pen=New-Object Drawing.Pen((Color '#DFE7F2'),1.0)
    try{
      $w=$sender.ClientSize.Width-2;$h=$sender.ClientSize.Height-2;$d=26
      $path.AddArc(1,1,$d,$d,180,90)
      $path.AddArc(($w-$d),1,$d,$d,270,90)
      $path.AddArc(($w-$d),($h-$d),$d,$d,0,90)
      $path.AddArc(1,($h-$d),$d,$d,90,90)
      $path.CloseFigure()
      $e.Graphics.DrawPath($pen,$path)
    }finally{$pen.Dispose();$path.Dispose()}
  })
  return $card
}
function Set-WorkspaceButton($button,$background='#F1F5FC',$foreground='#365371'){
  $button.Font=New-Object Drawing.Font('Segoe UI',9)
  $button.FlatStyle=[Windows.Forms.FlatStyle]::Flat
  $button.FlatAppearance.BorderSize=1
  $button.FlatAppearance.BorderColor=Color '#D7E2F0'
  $button.BackColor=Color $background
  $button.ForeColor=Color $foreground
  $button.UseVisualStyleBackColor=$false
  Round-WorkspaceControl $button 8
}
# Header and platform switcher.
Move-WorkspaceControl $brand $script:mainContent 32 20 590 42
$brand.Text='Instant Downloader'
$brand.Font=New-Object Drawing.Font('Segoe UI',21,[Drawing.FontStyle]::Bold)
$brand.ForeColor=Color '#21344C'
$subtitleLabel.Visible=$false
Move-WorkspaceControl $languageCaption $script:mainContent 688 30 94 26
Move-WorkspaceControl $languageBox $script:mainContent 787 24 158 32
$languageBox.BackColor=Color '#FFFFFF'
$languageBox.ForeColor=Color '#3B4F66'
$script:platformTabs=@()
foreach($tab in @(
  @{name='Skool';x=32;w=132;enabled=$true},
  @{name='YouTube';x=174;w=171;enabled=$false},
  @{name='Instagram';x=355;w=171;enabled=$false},
  @{name='TikTok';x=536;w=162;enabled=$false}
)){
  $label=[string]$tab.name
  if(-not $tab.enabled){$label+='  ('+(Tr 'soon')+')'}
  $button=MakeButton $label $tab.x 82 $tab.w 39
  Set-WorkspaceButton $button $(if($tab.enabled){'#D8E8FA'}else{'#F1F4F9'})
  if(-not $tab.enabled){$button.ForeColor=Color '#74849B'}
  $button.Enabled=[bool]$tab.enabled
  if($tab.enabled){$button.Add_Click({$script:urlText.Focus()})}
  $script:mainContent.Controls.Add($button)
  $script:platformTabs+=,$button
}
# Skool source card, with non-overlapping labels and full input borders.
$script:sourceCard=New-WorkspaceCard 24 142 937 230
$script:sourceHeading=MakeLabel (Tr 'sourceHeading') 24 12 500 27 12 $true
$script:sourceHeading.ForeColor=Color '#273F5A'
$script:sourceCard.Controls.Add($script:sourceHeading)
Move-WorkspaceControl $urlLabel $script:sourceCard 24 45 430 20
Move-WorkspaceControl $urlText $script:sourceCard 24 67 706 34
Move-WorkspaceControl $selectBtn $script:sourceCard 747 67 166 34
Move-WorkspaceControl $script:selectionSummary $script:sourceCard 24 106 873 22
Move-WorkspaceControl $archiveLabel $script:sourceCard 24 132 440 21
Move-WorkspaceControl $archiveText $script:sourceCard 24 156 706 34
Move-WorkspaceControl $browseBtn $script:sourceCard 747 156 166 34
foreach($field in @($urlText,$archiveText)){
  $field.BorderStyle=[Windows.Forms.BorderStyle]::FixedSingle
  $field.BackColor=Color '#FCFDFF'
  $field.ForeColor=Color '#24354A'
  $field.Font=New-Object Drawing.Font('Segoe UI',10)
}
$script:sourceTemp=MakeLabel ((Tr 'tempLabel')+': '+$script:cfg.tempPath) 24 196 870 22 9
$script:sourceTemp.ForeColor=Color '#71849B'
$script:sourceCard.Controls.Add($script:sourceTemp)
foreach($control in @($script:mainContent.Controls)){
  if($control -is [Windows.Forms.Label] -and $control -ne $script:sourceTemp -and
     $control.Text -like 'TEMP:*'){$control.Visible=$false}
}
Set-WorkspaceButton $selectBtn '#E0ECFA'
Set-WorkspaceButton $browseBtn '#F2F6FC'
# One grouped action toolbar instead of buttons scattered across the old form.
$script:actionsCard=New-WorkspaceCard 24 384 937 91
$script:actionsHeading=MakeLabel (Tr 'actionsHeading') 24 10 690 25 11 $true
$script:actionsHeading.ForeColor=Color '#2C486A'
$script:actionsCard.Controls.Add($script:actionsHeading)
Move-WorkspaceControl $startBtn $script:actionsCard 24 42 130 38
Move-WorkspaceControl $pauseBtn $script:actionsCard 164 42 97 38
Move-WorkspaceControl $resumeBtn $script:actionsCard 271 42 106 38
Move-WorkspaceControl $stopBtn $script:actionsCard 387 42 90 38
Move-WorkspaceControl $loginBtn $script:actionsCard 494 42 170 38
Move-WorkspaceControl $indexBtn $script:actionsCard 678 42 235 38
foreach($b in @($startBtn,$pauseBtn,$resumeBtn,$stopBtn,$loginBtn,$indexBtn)){
  Set-WorkspaceButton $b
}
Set-WorkspaceButton $startBtn '#CCE5FA' '#22547D'
Set-WorkspaceButton $stopBtn '#FCECEC' '#9C4652'
$startBtn.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
# Activity panel: the four slots are still present, but invisible when idle.
$script:activityCard=New-WorkspaceCard 24 487 937 192
$script:activityHeading=MakeLabel (Tr 'activityHeading') 24 12 220 27 12 $true
$script:activityHeading.ForeColor=Color '#2C486A'
$script:activityCard.Controls.Add($script:activityHeading)
Move-WorkspaceControl $stateLabel $script:activityCard 237 14 176 28
Move-WorkspaceControl $script:elapsedLabel $script:activityCard 434 14 217 27
Move-WorkspaceControl $script:activityLabel $script:activityCard 657 14 253 27
$stateLabel.ForeColor=Color '#4A7599'
Move-WorkspaceControl $script:progressSummary $script:activityCard 24 77 860 34
foreach($entry in $script:entries){
  $i=[int]$entry.index
  Move-WorkspaceControl $entry.name $script:activityCard 24 (53+$i*32) 354 23
  Move-WorkspaceControl $entry.bar $script:activityCard 392 (55+$i*32) 421 17
  Move-WorkspaceControl $entry.pct $script:activityCard 830 (53+$i*32) 72 23
  $entry.bar.ForeColor=Color '#87B7DE'
  $entry.name.ForeColor=Color '#3F566F'
}
RefreshProgressArea
# History, as a distinct section, without the old oversized blank area.
$script:historyCard=New-WorkspaceCard 24 692 937 139
Move-WorkspaceControl $historyLabel $script:historyCard 24 10 870 25
$historyLabel.ForeColor=Color '#526E8D'
Move-WorkspaceControl $historyList $script:historyCard 24 39 889 91
$historyList.GridLines=$false
$historyList.BorderStyle=[Windows.Forms.BorderStyle]::None
$historyList.BackColor=Color '#FAFCFF'
# Accessible footer toolbar: log and local file actions.
$script:logCard=New-WorkspaceCard 24 842 937 55
Move-WorkspaceControl $logBox $script:logCard 17 11 610 34
Move-WorkspaceControl $logBtn $script:logCard 638 11 125 34
Move-WorkspaceControl $folderBtn $script:logCard 773 11 145 34
Set-WorkspaceButton $logBtn
Set-WorkspaceButton $folderBtn
$logBox.BackColor=Color '#F8FAFE'
$logBox.BorderStyle=[Windows.Forms.BorderStyle]::None
$openIndexBtn.Visible=$false
$updatesBtn.Visible=$false
# Sidebar: course library keeps opening the system browser (not an embedded page).
$script:sideNav=New-Object Windows.Forms.Panel
$script:sideNav.SetBounds(0,0,203,908)
$script:sideNav.BackColor=Color '#EAF2FA'
$form.Controls.Add($script:sideNav)
$script:sideMark=MakeLabel 'instant' 22 25 154 30 18 $true
$script:sideMark.ForeColor=Color '#346A9A'
$script:sideNav.Controls.Add($script:sideMark)
$script:sideCaption=MakeLabel 'DOWNLOADER' 24 55 150 24 9 $true
$script:sideCaption.ForeColor=Color '#7A91AB'
$script:sideNav.Controls.Add($script:sideCaption)
$script:navDownloads=MakeButton (Tr 'sideDownloads') 12 122 178 45
$script:navLibrary=MakeButton (Tr 'sideLibrary') 12 176 178 45
$script:navUpdates=MakeButton (Tr 'sideUpdates') 12 230 178 45
foreach($b in @($script:navDownloads,$script:navLibrary,$script:navUpdates)){
  $b.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
  $b.Padding=New-Object Windows.Forms.Padding(14,0,0,0)
  $b.FlatAppearance.BorderSize=0
  Set-WorkspaceButton $b '#EAF2FA' '#3B5C7A'
  $b.FlatAppearance.BorderSize=0
  $script:sideNav.Controls.Add($b)
}
$script:navDownloads.BackColor=Color '#D5E7F8'
$script:navDownloads.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$script:navDownloads.Add_Click({$script:urlText.Focus()})
$script:navLibrary.Add_Click({
  $file=Join-Path $script:archiveText.Text 'index.html'
  if(Test-Path -LiteralPath $file -PathType Leaf){Start-Process -FilePath $file}
  else{Trace (Tr 'missingIndex')}
})
$script:navUpdates.Add_Click({if($updatesBtn.Enabled){ShowUpdatesView}})
$script:sideHint=MakeLabel (Tr 'browserHint') 19 815 169 45 9
$script:sideHint.ForeColor=Color '#637E9A'
$script:sideNav.Controls.Add($script:sideHint)
# Existing Updates stays inside the same Form as a separate in-place view.
$script:updatePanel.SetBounds(204,0,986,908)
$script:updatePanel.BackColor=Color '#F7FAFD'
$script:updatePanel.BringToFront()
$script:updatePanel.Visible=$false
# Resize content viewport to the actual screen. The full layout remains
# scrollable even on 1024x768 or when Windows display scaling is increased.
$form.Add_ClientSizeChanged({
  if($script:mainContent){
    $viewportWidth=[Math]::Max(300,($form.ClientSize.Width-204))
    $viewportHeight=[Math]::Max(300,$form.ClientSize.Height)
    $script:mainContent.SetBounds(204,0,$viewportWidth,$viewportHeight)
    if($script:sideNav){$script:sideNav.Height=$viewportHeight}
    if($script:updatePanel){$script:updatePanel.SetBounds(204,0,$viewportWidth,$viewportHeight)}
  }
})
$script:mainContent.SetBounds(204,0,([Math]::Max(300,($form.ClientSize.Width-204))),([Math]::Max(300,$form.ClientSize.Height)))
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
