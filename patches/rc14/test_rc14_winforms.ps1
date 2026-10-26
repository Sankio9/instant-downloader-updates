# RC14 PowerShell 5.1 WinForms visual layout smoke test; no Skool login/network.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Instant_Downloader.ps1') -Raw -Encoding UTF8
$start=$source.IndexOf('# Learning Workspace (pastel)')
$stop=$source.IndexOf('$script:trayIcon=New-Object Windows.Forms.NotifyIcon',$start)
if($start -lt 0 -or $stop -le $start){throw 'RC14 shell missing'}
if(-not $source.Contains('Start-Process -FilePath $p')){throw 'Archived courses must open in default browser'}
if($source.Contains('New-Object Windows.Forms.WebBrowser')){throw 'Embedded browser is disallowed'}
if(-not $source.Contains("ShowSelectionDialog $script:catalogResult")){throw 'Choose sections modal was disconnected'}
if(-not $source.Contains('$script:updatePanel.BringToFront()')){throw 'Embedded updates panel missing'}
function Color([string]$hex){return [Drawing.ColorTranslator]::FromHtml($hex)}
function Tr([string]$key){
 $words=@{sideDownloads='Downloads';sideLibrary='Course library';sideUpdates='Updates';soon='Coming soon'}
 if($words.ContainsKey($key)){return $words[$key]}
 return $key
}
function MakeLabel($text,$x,$y,$w,$h,$size=10,$bold=$false){
 $label=New-Object Windows.Forms.Label
 $label.Text=[string]$text;$label.SetBounds($x,$y,$w,$h)
 return $label
}
function MakeButton($text,$x,$y,$w,$h){
 $button=New-Object Windows.Forms.Button
 $button.Text=[string]$text;$button.SetBounds($x,$y,$w,$h)
 $button.FlatStyle=[Windows.Forms.FlatStyle]::Flat
 return $button
}
function Refresh-Language{}
$form=New-Object Windows.Forms.Form
$form.ClientSize=New-Object Drawing.Size(910,845)
$script:updatePanel=New-Object Windows.Forms.Panel
$script:updatePanel.SetBounds(0,0,910,845)
$form.Controls.Add($script:updatePanel)
$brand=MakeLabel 'INSTANT DOWNLOADER' 24 15 575 40
$subtitleLabel=MakeLabel 'original subtitle' 27 55 830 26
$languageBox=New-Object Windows.Forms.ComboBox
$languageBox.SetBounds(708,17,168,30)
$urlText=New-Object Windows.Forms.TextBox;$urlText.SetBounds(27,126,678,31)
$script:urlText=$urlText
$archiveText=New-Object Windows.Forms.TextBox;$archiveText.SetBounds(27,196,730,30)
$script:selectionSummary=MakeLabel 'Default all' 27 157 848 18
$historyLabel=MakeLabel 'History' 27 578 848 18
$historyList=New-Object Windows.Forms.ListView;$historyList.SetBounds(27,599,848,124)
$logBox=New-Object Windows.Forms.TextBox
$logBox.SetBounds(27,765,690,57)
$script:entries=@()
$progressBar=New-Object Windows.Forms.ProgressBar
$script:entries+=@{bar=$progressBar}
$buttons=@{
 startBtn=@('Start',27,274,135,41);pauseBtn=@('Pause',174,274,128,41);
 resumeBtn=@('Resume',314,274,128,41);stopBtn=@('Stop',454,274,110,41);
 loginBtn=@('Login Skool',577,274,142,41);indexBtn=@('Refresh',733,274,142,41);
 selectBtn=@('Choose sections',717,126,158,31);browseBtn=@('Browse',771,195,104,32);
 folderBtn=@('Open folder',731,766,144,29);openIndexBtn=@('Open library',731,799,144,29);
 logBtn=@('Open log',731,731,144,29);updatesBtn=@('Updates',731,329,144,30)
}
foreach($name in $buttons.Keys){
 $spec=$buttons[$name]
 Set-Variable -Name $name -Value (MakeButton $spec[0] $spec[1] $spec[2] $spec[3] $spec[4]) -Scope Script
}
foreach($v in @('brand','subtitleLabel','languageBox','urlText','archiveText','historyLabel','historyList','logBox')){
 $form.Controls.Add((Get-Variable -Name $v -Scope Script).Value)
}
$form.Controls.Add($script:selectionSummary)
foreach($name in $buttons.Keys){$form.Controls.Add((Get-Variable -Name $name -Scope Script).Value)}
. ([scriptblock]::Create($source.Substring($start,$stop-$start)))
if($form.ClientSize.Width -ne 1085 -or $form.ClientSize.Height -ne 875){throw 'Workspace window geometry incorrect'}
if($script:mainContent.Controls.Count -lt 14){throw 'Existing actions were not preserved in the main panel'}
if($script:mainContent.Controls.Contains($script:updatePanel)){throw 'Update panel incorrectly reparented'}
if($script:updatePanel.Bounds.X -ne 175){throw 'Embedded updater must align with workspace'}
if($script:sideNav.Controls.Count -lt 4){throw 'Pastel navigation not built'}
if($script:platformTabs.Count -ne 4){throw 'Exactly four platform tabs expected'}
if(@($script:platformTabs|Where-Object {$_.Enabled}).Count -ne 1){throw 'Only Skool should be enabled'}
if($script:platformTabs[0].Text -ne 'Skool'){throw 'The active platform is not Skool'}
if($script:mainContent.Controls.Contains($urlText) -ne $true){throw 'Skool link input missing'}
if($script:mainContent.Controls.Contains($selectBtn) -ne $true){throw 'Choose sections action missing'}
if($script:mainContent.Controls.Contains($archiveText) -ne $true){throw 'Archive folder input missing'}
if($script:navLibrary.Text -ne 'Course library'){throw 'Library navigation missing'}
if($script:navUpdates.Text -ne 'Updates'){throw 'Updates navigation missing'}
if($archiveText.BorderStyle -ne [Windows.Forms.BorderStyle]::FixedSingle){throw 'Archive folder border fix missing'}
if($subtitleLabel.Visible){throw 'Old subtitle conflicts with tabs'}
if($script:platformTabs[1].Enabled -or $script:platformTabs[2].Enabled -or $script:platformTabs[3].Enabled){throw 'Upcoming services must be inert'}
if($script:mainContent.Controls.Contains($logBox) -ne $true){throw 'Existing journal missing'}
if($script:mainContent.Controls.Contains($historyList) -ne $true){throw 'Existing download history missing'}
Write-Host 'PASS: pastel UI shell, Skool only active, Choose sections, updater, history, browser archive, border'
$form.Dispose()
