# Actual Windows Forms visual smoke test for RC15, entirely local mock values.
# This test never launches a browser, starts Skool, or reads user login/configuration.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Instant_Downloader.ps1') -Raw -Encoding UTF8
$start=$source.IndexOf('# RC15 Learning Workspace v2')
$stop=$source.IndexOf('$script:trayIcon=New-Object Windows.Forms.NotifyIcon',$start)
if($start -lt 0 -or $stop -le $start){throw 'RC15 UI block missing'}
if(-not $source.Contains('Start-Process -FilePath $p')){throw 'Course library should open local HTML in the system browser'}
if($source.Contains('New-Object Windows.Forms.WebBrowser')){throw 'Unexpected embedded browser'}
function Color([string]$hex){return [Drawing.ColorTranslator]::FromHtml($hex)}
function Tr([string]$key){
 $dictionary=@{
  soon='Soon';sideDownloads='Downloads';sideLibrary='Course library';sideUpdates='Updates';
  sourceHeading='Skool source';actionsHeading='Download controls';activityHeading='Download activity';
  browserHint='Courses open in your browser';tempLabel='TEMP';ready='READY'
 }
 if($dictionary.ContainsKey($key)){return [string]$dictionary[$key]}
 return $key
}
function MakeLabel($text,$x,$y,$w,$h,$size=10,$bold=$false){
 $control=New-Object Windows.Forms.Label
 $control.SetBounds($x,$y,$w,$h);$control.Text=[string]$text
 $control.Font=New-Object Drawing.Font('Segoe UI',$size)
 $control.ForeColor=Color '#233950'
 return $control
}
function MakeButton($text,$x,$y,$w,$h){
 $control=New-Object Windows.Forms.Button
 $control.Text=[string]$text;$control.SetBounds($x,$y,$w,$h)
 $control.FlatStyle=[Windows.Forms.FlatStyle]::Flat
 $control.BackColor=Color '#FFFFFF'
 return $control
}
function Refresh-Language{}
function RefreshProgressArea{}
function Trace([string]$message){$script:logMessage=$message}
function ShowUpdatesView{$script:openedUpdates=$true}
$script:cfg=@{tempPath='D:\TEMP\InstantDownloader';version='1.8.0-rc.15'}
$script:openedUpdates=$false
$form=New-Object Windows.Forms.Form
$form.Text='Instant Downloader v1.8 RC15 - Skool'
$form.ClientSize=New-Object Drawing.Size(910,845)
$script:updatePanel=New-Object Windows.Forms.Panel
$script:updatePanel.SetBounds(0,0,910,845)
$form.Controls.Add($script:updatePanel)
$brand=MakeLabel 'INSTANT DOWNLOADER' 24 15 575 40 21 $true
$subtitleLabel=MakeLabel 'Old subtitle' 27 55 830 26 10
$languageCaption=MakeLabel 'Language' 600 22 100 24 10
$languageBox=New-Object Windows.Forms.ComboBox
$languageBox.SetBounds(708,17,168,30)
$languageBox.DropDownStyle=[Windows.Forms.ComboBoxStyle]::DropDownList
[void]$languageBox.Items.Add('English');[void]$languageBox.Items.Add('Română');$languageBox.SelectedIndex=0
$urlLabel=MakeLabel 'Skool Classroom / course link' 27 100 360 22 10 $true
$urlText=New-Object Windows.Forms.TextBox
$urlText.SetBounds(27,126,678,31);$urlText.Text='https://www.skool.com/sample-classroom/classroom'
$script:urlText=$urlText
$archiveLabel=MakeLabel 'Course archive folder' 27 178 320 20 10 $true
$archiveText=New-Object Windows.Forms.TextBox;$archiveText.SetBounds(27,196,730,30);$archiveText.Text='G:\COURSE'
$script:archiveText=$archiveText
$script:selectionSummary=MakeLabel 'Default: download all courses. Select specific sections if needed.' 27 157 848 18 9
$historyLabel=MakeLabel 'History - green: archived | orange: incomplete | red: failed' 27 578 848 18 9 $true
$historyList=New-Object Windows.Forms.ListView;$historyList.SetBounds(27,599,848,124)
$historyList.View=[Windows.Forms.View]::Details
[void]$historyList.Columns.Add('Lesson',417)
[void]$historyList.Columns.Add('Status',120)
[void]$historyList.Columns.Add('Progress',80)
[void]$historyList.Columns.Add('Details',230)
$logBox=New-Object Windows.Forms.TextBox;$logBox.SetBounds(27,765,690,57)
$logBox.Multiline=$true;$logBox.ReadOnly=$true;$logBox.Text='[10:00:00] Application ready. Courses open in your browser.'
$script:progressSummary=MakeLabel 'No active downloads' 30 385 820 30 11 $true
$stateLabel=MakeLabel 'READY' 27 332 205 27 11 $true
$script:stateLabel=$stateLabel
$script:elapsedLabel=MakeLabel 'Elapsed: 00:00:00' 253 334 235 24 10 $true
$script:activityLabel=MakeLabel 'READY' 500 334 220 24 9
$script:entries=@()
foreach($i in 0..3){
 $caption=MakeLabel '' 30 (367+$i*51) 445 22 10
 $bar=New-Object Windows.Forms.ProgressBar;$bar.SetBounds(30,(393+$i*51),440,16)
 $pct=MakeLabel '' 489 (389+$i*51) 82 24 10 $true
 $caption.Visible=$false;$bar.Visible=$false;$pct.Visible=$false
 $script:entries+=@{index=$i;name=$caption;bar=$bar;pct=$pct;active=$false;finished=$false}
}
$buttons=@{
 startBtn=@('Start',27,274,135,41);pauseBtn=@('Pause',174,274,128,41);
 resumeBtn=@('Resume',314,274,128,41);stopBtn=@('Stop',454,274,110,41);
 loginBtn=@('Login Skool',577,274,142,41);indexBtn=@('Refresh course pages',733,274,142,41);
 selectBtn=@('Choose sections',717,126,158,31);browseBtn=@('Browse...',771,195,104,32);
 folderBtn=@('Open folder',731,766,144,29);openIndexBtn=@('Open course library',731,799,144,29);
 logBtn=@('Open log',731,731,144,29);updatesBtn=@('Updates',731,329,144,30)
}
foreach($name in $buttons.Keys){
 $spec=$buttons[$name]
 Set-Variable -Name $name -Value (MakeButton $spec[0] $spec[1] $spec[2] $spec[3] $spec[4]) -Scope Script
}
foreach($name in @('brand','subtitleLabel','languageCaption','languageBox','urlLabel','urlText','archiveLabel','archiveText','historyLabel','historyList','logBox','stateLabel')){
 $form.Controls.Add((Get-Variable -Name $name -Scope Script).Value)
}
foreach($control in @($script:selectionSummary,$script:progressSummary,$script:elapsedLabel,$script:activityLabel)){
 $form.Controls.Add($control)
}
$form.Controls.Add((MakeLabel 'TEMP: D:\TEMP\InstantDownloader' 27 234 820 24 9))
foreach($entry in $script:entries){foreach($n in @('name','bar','pct')){$form.Controls.Add($entry[$n])}}
foreach($name in $buttons.Keys){$form.Controls.Add((Get-Variable -Name $name -Scope Script).Value)}
. ([scriptblock]::Create($source.Substring($start,$stop-$start)))
if($form.ClientSize.Width -ne 1190 -or $form.ClientSize.Height -ne 908){throw 'Wrong RC15 form size'}
if($script:mainContent.Bounds.X -ne 204){throw 'Content does not align with sidebar'}
if($script:mainContent.Controls.Contains($script:sourceCard) -ne $true){throw 'Source card missing'}
if($script:mainContent.Controls.Contains($script:activityCard) -ne $true){throw 'Progress card missing'}
if($script:mainContent.Controls.Contains($script:historyCard) -ne $true){throw 'History card missing'}
if($script:sourceCard.Controls.Contains($selectBtn) -ne $true){throw 'Choose sections disconnected'}
if($script:sourceCard.Controls.Contains($archiveText) -ne $true){throw 'Archive folder disconnected'}
if($script:sourceCard.Controls.Contains($urlText) -ne $true){throw 'Skool URL disconnected'}
if($urlText.Bounds.Bottom -ge $script:selectionSummary.Bounds.Top){throw 'Choose sections note overlaps URL'}
if($archiveLabel.Bottom -gt $archiveText.Top){throw 'Archive label overlaps textbox'}
if($archiveText.Bounds.Bottom -gt $script:sourceTemp.Top){throw 'Archive input overlaps TEMP label'}
if($archiveText.BorderStyle -ne [Windows.Forms.BorderStyle]::FixedSingle){throw 'Archive input border missing'}
if(@($script:platformTabs|Where-Object {$_.Enabled}).Count -ne 1){throw 'Only Skool must be enabled'}
if($script:platformTabs.Count -ne 4){throw 'YouTube/Instagram/TikTok tabs missing'}
foreach($tab in $script:platformTabs){if($tab.Text.Length -gt 25){throw 'Platform label clipped risk: '+$tab.Text}}
if($script:platformTabs[1].Text -notmatch 'Soon'){throw 'Inactive tabs must be labelled'}
if($script:sideNav.Controls.Contains($script:navLibrary) -ne $true){throw 'Browser library link missing'}
if($script:sideNav.Controls.Contains($script:navUpdates) -ne $true){throw 'Updates sidebar missing'}
if($script:historyCard.Controls.Contains($historyList) -ne $true){throw 'History control missing'}
if($script:logCard.Controls.Contains($logBox) -ne $true){throw 'Log control missing'}
if($script:updatePanel.Bounds.X -ne 204 -or $script:updatePanel.Bounds.Width -ne 986){throw 'Embedded updater panel misaligned'}
if($script:activityCard.Bounds.Bottom -ge $script:historyCard.Bounds.Top){throw 'Progress and history cards overlap'}
if($script:historyCard.Bounds.Bottom -ge $script:logCard.Bounds.Top){throw 'History and log cards overlap'}
if($script:actionsCard.Bounds.Bottom -ge $script:activityCard.Bounds.Top){throw 'Actions and progress cards overlap'}
$form.ShowInTaskbar=$false
[void]$form.Show()
[Windows.Forms.Application]::DoEvents()
if(-not $script:mainContent.AutoScroll){throw 'Compact screens would clip the content'}
if($script:mainContent.Bounds.Right -gt $form.ClientSize.Width){throw 'Viewport is wider than form'}

# Draw the live initialized content and sidebar separately so small hosted-runner
# desktops do not clip the right-hand controls in a sanitized QA preview.
if($env:RC15_SCREENSHOT_PATH){
 $destination=$env:RC15_SCREENSHOT_PATH
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
 $script:mainContent.SetBounds(204,0,986,908)
 $script:sideNav.Height=908
 $script:mainContent.AutoScrollPosition=New-Object Drawing.Point(0,0)
 [Windows.Forms.Application]::DoEvents()
 $canvas=New-Object Drawing.Bitmap(1190,908)
 $navBmp=New-Object Drawing.Bitmap(203,908)
 $contentBmp=New-Object Drawing.Bitmap(986,908)
 $graphics=[Drawing.Graphics]::FromImage($canvas)
 try{
  $graphics.Clear((Color '#F4F7FC'))
  $script:sideNav.DrawToBitmap($navBmp,(New-Object Drawing.Rectangle(0,0,203,908)))
  $script:mainContent.DrawToBitmap($contentBmp,(New-Object Drawing.Rectangle(0,0,986,908)))
  $graphics.DrawImageUnscaled($navBmp,0,0)
  $graphics.DrawImageUnscaled($contentBmp,204,0)
  $canvas.Save($destination,[Drawing.Imaging.ImageFormat]::Png)
  Write-Host ('Full live control screenshot: '+$destination)
 }finally{
  $graphics.Dispose();$navBmp.Dispose();$contentBmp.Dispose();$canvas.Dispose()
 }
}

$script:navUpdates.PerformClick()
if(-not $script:openedUpdates){throw 'Updates side navigation does not open view'}
Write-Host 'PASS: RC15 structural card layout, input borders, no overlaps, four tabs, library browser, working sidebar, updates'
$form.Close()
$form.Dispose()
