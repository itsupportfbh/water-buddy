param([switch]$SelfTest, [switch]$SmokeTest, [switch]$Background, [switch]$Preview, [switch]$ShowDashboard)
$ErrorActionPreference = 'Stop'

function Get-Slots([datetime]$Day) {
    @(7..16 | ForEach-Object { $Day.Date.AddHours($_) })
}
function Get-NextSlot([datetime]$Now) {
    $next = @(Get-Slots $Now | Where-Object { $_ -gt $Now })
    if ($next.Count) { return $next[0] }
    return $Now.Date.AddDays(1).AddHours(7)
}
function Get-DueSlot([datetime]$Now) {
    if ($Now.Hour -lt 7 -or $Now.Hour -gt 16) { return $null }
    $slot = $Now.Date.AddHours($Now.Hour)
    if (($Now - $slot).TotalMinutes -lt 2) { return $slot }
    return $null
}
if ($SelfTest) {
    $d = [datetime]'2026-11-17'
    if ((Get-Slots $d).Count -ne 10) { throw 'Expected ten slots' }
    if ((Get-NextSlot ($d.AddHours(6))).Hour -ne 7) { throw 'Morning boundary' }
    if ((Get-NextSlot ($d.AddHours(7))).Hour -ne 8) { throw 'Exact boundary' }
    if ((Get-NextSlot ($d.AddHours(16))) -ne $d.AddDays(1).AddHours(7)) { throw 'Next day boundary' }
    if ($null -ne (Get-DueSlot ($d.AddHours(6)))) { throw 'Too early' }
    if ($null -eq (Get-DueSlot ($d.AddHours(16).AddSeconds(30)))) { throw 'Last slot missing' }
    if ($null -ne (Get-DueSlot ($d.AddHours(16).AddMinutes(3)))) { throw 'Stale reminder' }
    if ($null -ne (Get-DueSlot ($d.AddHours(17)))) { throw 'Too late' }
    Write-Output 'PASS: 8 schedule checks; 10 reminders x 150 ml = 1500 ml.'
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$mutexName = 'Local\ThanniWaterReminderV1'
if ($SmokeTest) { $mutexName += '-SmokeTest' }
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show('Water Reminder is already running. Open it from the blue information icon in the system tray.', 'Water Reminder') | Out-Null
    exit
}
$script:dataPath = Join-Path $PSScriptRoot 'data.json'
$script:data = @{ Amount = 150; PlanMl = 1500; Sound = $true; Entries = @(); LastReminder = ''; PositionX = $null; PositionY = $null }
if (Test-Path -LiteralPath $dataPath) {
    try {
        $saved = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
        if ($saved.Amount -ge 50 -and $saved.Amount -le 500) { $data.Amount = [int]$saved.Amount }
        if ($saved.PlanMl -ge 500 -and $saved.PlanMl -le 4000) { $data.PlanMl = [int]$saved.PlanMl }
        $data.Sound = [bool]$saved.Sound
        $data.Entries = @($saved.Entries | Where-Object { $null -ne $_ })
        $data.LastReminder = [string]$saved.LastReminder
        if ($null -ne $saved.PositionX -and $null -ne $saved.PositionY) {
            $data.PositionX = [double]$saved.PositionX
            $data.PositionY = [double]$saved.PositionY
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show('Saved data could not be read. A backup will be kept; the app will use defaults.', 'Water Reminder') | Out-Null
        Copy-Item -LiteralPath $dataPath -Destination ($dataPath + '.backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    }
}
# Give historical drinks permanent identifiers so repeated sync cannot duplicate them.
$script:data.Entries = @($script:data.Entries | ForEach-Object {
    @{ Id = $(if ($_.Id) { [string]$_.Id } else { [guid]::NewGuid().ToString() }); Time = $_.Time; Ml = [int]$_.Ml }
})
. (Join-Path $PSScriptRoot 'DesktopSync.ps1')
function Save-Data {
    if ($SmokeTest) { return }
    $temp = $script:dataPath + '.tmp'
    $script:data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $script:dataPath -Force
    Publish-DesktopSync
}
$script:snoozeUntil = $null
$script:reminderOpen = $false
$script:previewOnly = $false
$script:exitApp = $false
$script:lastDate = (Get-Date).Date
$script:appScriptPath = $PSCommandPath
$script:appFolder = $PSScriptRoot
$startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Thanni Water Reminder.lnk'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Water Buddy | Water Reminder'
$form.ClientSize = New-Object System.Drawing.Size(600, 660)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = [Drawing.Color]::FromArgb(241, 247, 250)
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.Icon = [Drawing.SystemIcons]::Information
function Add-Label($Text, $X, $Y, $W, $H, $Size = 10) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.SetBounds($X, $Y, $W, $H)
    $label.Font = New-Object Drawing.Font('Segoe UI', $Size)
    $label.ForeColor = [Drawing.Color]::FromArgb(26, 55, 68)
    $form.Controls.Add($label)
    return $label
}
function Add-Button($Text, $X, $Y, $W, $Action) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.SetBounds($X, $Y, $W, 38)
    $button.FlatStyle = 'Flat'
    $button.BackColor = [Drawing.Color]::White
    $button.Add_Click($Action)
    $form.Controls.Add($button)
    return $button
}
$null = Add-Label 'THANNI' 26 18 530 42 25
$null = Add-Label 'A little water. A healthy habit.' 28 64 530 28 12
$null = Add-Label 'Every day  |  7:00 AM - 4:00 PM  |  Every hour' 28 100 540 26
$script:totalLabel = Add-Label '' 28 138 540 40 21
$script:nextLabel = Add-Label '' 28 183 540 27 11
$script:notice = Add-Label 'Reminders are on. Closing this window keeps the app in the tray.' 28 217 540 48 11
$notice.ForeColor = [Drawing.Color]::FromArgb(0, 105, 125)
function Record-Drink([int]$Ml = 0) {
    if ($script:previewOnly) { return }
    if ($Ml -eq 0) { $Ml = [int]$amount.Value }
    $script:data.Entries = @($script:data.Entries) + @(@{ Id = [guid]::NewGuid().ToString(); Time = (Get-Date).ToString('o'); Ml = $Ml })
    $script:snoozeUntil = $null
    $script:reminderOpen = $false
    $form.TopMost = $false
    Save-Data
    $notice.Text = 'Saved! Enjoy your work until the next reminder.'
    Update-View
    if ($buddy.IsVisible) {
        Show-BuddyConfirmation 'Great! Water logged!' ($amount.Value.ToString() + ' ml saved. See you at the next reminder!')
        Show-Celebration
    }
}
$script:drinkButton = Add-Button 'I drank water - log 150 ml' 28 274 252 { Record-Drink }
$drinkButton.BackColor = [Drawing.Color]::FromArgb(0, 108, 125)
$drinkButton.ForeColor = [Drawing.Color]::White
function Snooze-Reminder([int]$Minutes = 10) {
    if ($script:previewOnly) { return }
    $snoozePopup.IsOpen = $false
    $script:mood = 'sad'
    $script:arrivedAt = Get-Date
    $sparkles.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $sparkles.Opacity = 0
    Set-MascotFrame 16
    $later = (Get-Date).AddMinutes($Minutes)
    if ($later -le (Get-Date).Date.AddHours(16)) {
        $script:snoozeUntil = $later
        $notice.Text = 'Snoozed until ' + $later.ToString('h:mm tt')
    } else {
        $script:snoozeUntil = $null
        $notice.Text = 'Reminder dismissed. Next reminder: tomorrow at 7:00 AM.'
    }
    $script:reminderOpen = $false
    $form.TopMost = $false
    Update-View
    if ($buddy.IsVisible) {
        if ($null -ne $script:snoozeUntil) {
            Show-BuddyConfirmation 'Okay... I will be back.' ($Minutes.ToString() + ' minutes later, at ' + $script:snoozeUntil.ToString('h:mm tt') + '.')
        } else {
            Show-BuddyConfirmation 'See you tomorrow!' 'All done for today. Next: tomorrow, 7 AM.'
        }
    }
}
$snooze = Add-Button 'Remind later' 294 274 132 { Snooze-Reminder }
function Undo-LastDrink {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $items = @($script:data.Entries)
    for ($i = $items.Count - 1; $i -ge 0; $i--) {
        if (([datetime]$items[$i].Time).ToString('yyyy-MM-dd') -eq $today) {
            $script:data.Entries = @($items | Select-Object -First $i) + @($items | Select-Object -Skip ($i + 1))
            Save-Data
            break
        }
    }
    Update-View
}
$null = Add-Button 'Undo last' 438 274 132 { Undo-LastDrink }
$null = Add-Label 'Glass size (ml)' 28 333 130 26
$script:amount = New-Object Windows.Forms.NumericUpDown
$amount.SetBounds(163, 330, 82, 30)
$amount.Minimum = 50
$amount.Maximum = 500
$amount.Increment = 25
$amount.Value = $data.Amount
$form.Controls.Add($amount)
$script:planLabel = Add-Label '' 265 333 310 26
$amount.Add_ValueChanged({
    $script:data.Amount = [int]$amount.Value
    Save-Data
    Update-View
})
$sound = New-Object Windows.Forms.CheckBox
$sound.Text = 'Reminder sound'
$sound.SetBounds(28, 376, 180, 28)
$sound.Checked = $data.Sound
$sound.Add_CheckedChanged({ $script:data.Sound = $sound.Checked; Save-Data })
$form.Controls.Add($sound)
$startup = New-Object Windows.Forms.CheckBox
$startup.Text = 'Start when I sign in to Windows'
$startup.SetBounds(235, 376, 340, 28)
$startup.Checked = Test-Path -LiteralPath $startupPath
$startup.Add_CheckedChanged({
    try {
        if ($startup.Checked) {
            $ws = New-Object -ComObject WScript.Shell
            $link = $ws.CreateShortcut($startupPath)
            $link.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $link.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script:appScriptPath + '" -Background'
            $link.WorkingDirectory = $script:appFolder
            $link.Save()
        } elseif (Test-Path -LiteralPath $startupPath) {
            Remove-Item -LiteralPath $startupPath
        }
    } catch {
        [Windows.Forms.MessageBox]::Show('Could not change startup setting: ' + $_.Exception.Message) | Out-Null
        $startup.Checked = Test-Path -LiteralPath $startupPath
    }
})
$form.Controls.Add($startup)
$null = Add-Label "This is a flexible reminder plan, not a personal medical target. Tea, coffee and milk count too. Drink to thirst after 4 PM as well. If your doctor limits fluids, follow that limit." 28 421 540 75 10
$null = Add-Label 'Needs vary with heat, activity and health. NHS guidance: 6-8 cups of fluid across the whole day.' 28 500 540 45 9
$source = New-Object Windows.Forms.LinkLabel
$source.Text = 'Read NHS hydration guidance'
$source.SetBounds(28, 547, 340, 24)
$source.Add_LinkClicked({ Start-Process 'https://www.nhs.uk/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/' })
$form.Controls.Add($source)
$null = Add-Button 'Meet your buddy' 28 590 168 { Show-Reminder $true }
$null = Add-Button 'Hide to tray' 210 590 168 { $form.TopMost = $false; $form.Hide() }
$null = Add-Button 'Exit app' 392 590 178 { $script:exitApp = $true; $form.Close() }

$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.SystemIcons]::Information
$tray.Text = 'Water Buddy - Water Reminder'
$tray.Visible = $true
$menu = New-Object Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Open Water Reminder')
$openItem.Add_Click({ Open-Dashboard })
$previewItem = $menu.Items.Add('Preview buddy reactions')
$previewItem.Add_Click({ Show-Reminder $true; Complete-Walk; $reactionPopup.IsOpen = $true })
$exitItem = $menu.Items.Add('Exit')
$exitItem.Add_Click({ $script:exitApp = $true; $form.Close() })
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({ Open-Dashboard })

# WPF provides real per-pixel transparency and smooth rounded floating controls.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName WindowsFormsIntegration
[xml]$buddyXaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Buddy.xaml') -Raw
$xmlReader = New-Object Xml.XmlNodeReader($buddyXaml)
$buddy = [Windows.Markup.XamlReader]::Load($xmlReader)
$xmlReader.Close()
$buddyTitle = $buddy.FindName('BuddyTitle')
$buddyText = $buddy.FindName('BuddyText')
$headerKicker = $buddy.FindName('HeaderKicker')
$picture = $buddy.FindName('Picture')
$bob = $buddy.FindName('Bob')
$walkTilt = $buddy.FindName('WalkTilt')
$walkFlip = $buddy.FindName('WalkFlip')
$reminderPanels = @('Bubble', 'BubbleTail', 'BuddyClose', 'AmountCard', 'ActionCard') | ForEach-Object { $buddy.FindName($_) }
$buddyDrink = $buddy.FindName('BuddyDrink')
$buddyLater = $buddy.FindName('BuddyLater')
$snoozePopup = $buddy.FindName('SnoozePopup')
$snoozePopup.PlacementTarget = $buddyLater
$reactionPopup = $buddy.FindName('ReactionPopup')
$reactionPopup.PlacementTarget = $buddy.FindName('TryReactions')
$sparkles = $buddy.FindName('Sparkles')
$sparkleLift = $buddy.FindName('SparkleLift')
$buddyProgress = $buddy.FindName('BuddyProgress')
$drinkAmount = $buddy.FindName('DrinkAmount')
$amountBadge = $buddy.FindName('AmountBadge')
$mascotPath = Join-Path $PSScriptRoot 'mascot-sprites.png'
$bitmap = New-Object Windows.Media.Imaging.BitmapImage
$bitmap.BeginInit()
$bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$bitmap.UriSource = New-Object Uri($mascotPath)
$bitmap.EndInit()
$bitmap.Freeze()
$script:mascotFrames = @()
for ($i = 0; $i -lt 16; $i++) {
    $column = $i % 4
    $row = [Math]::Floor($i / 4)
    $x0 = [int][Math]::Floor($column * $bitmap.PixelWidth / 4)
    $y0 = [int][Math]::Floor($row * $bitmap.PixelHeight / 4)
    $x1 = [int][Math]::Floor(($column + 1) * $bitmap.PixelWidth / 4)
    $y1 = [int][Math]::Floor(($row + 1) * $bitmap.PixelHeight / 4)
    $rect = New-Object Windows.Int32Rect($x0, $y0, ($x1 - $x0), ($y1 - $y0))
    $frame = New-Object Windows.Media.Imaging.CroppedBitmap($bitmap, $rect)
    $frame.Freeze()
    $script:mascotFrames += $frame
}
$sadBitmap = New-Object Windows.Media.Imaging.BitmapImage
$sadBitmap.BeginInit()
$sadBitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$sadBitmap.UriSource = New-Object Uri((Join-Path $PSScriptRoot 'mascot-sad.png'))
$sadBitmap.EndInit()
$sadBitmap.Freeze()
for ($i = 0; $i -lt 4; $i++) {
    $column = $i % 2
    $row = [Math]::Floor($i / 2)
    $x0 = [int][Math]::Floor($column * $sadBitmap.PixelWidth / 2)
    $y0 = [int][Math]::Floor($row * $sadBitmap.PixelHeight / 2)
    $x1 = [int][Math]::Floor(($column + 1) * $sadBitmap.PixelWidth / 2)
    $y1 = [int][Math]::Floor(($row + 1) * $sadBitmap.PixelHeight / 2)
    $rect = New-Object Windows.Int32Rect($x0, $y0, ($x1 - $x0), ($y1 - $y0))
    $frame = New-Object Windows.Media.Imaging.CroppedBitmap($sadBitmap, $rect)
    $frame.Freeze()
    $script:mascotFrames += $frame
}
$script:activeFrame = -1
$script:mood = 'greeting'
$script:arrivedAt = Get-Date
function Set-MascotFrame([int]$Index) {
    if ($script:activeFrame -ne $Index) {
        $picture.Source = $script:mascotFrames[$Index]
        $script:activeFrame = $Index
    }
}
function Update-IdlePose([double]$Seconds) {
    if ($script:mood -eq 'happy') {
        Set-MascotFrame (12 + [Math]::Min(3, [int][Math]::Floor($Seconds * 2.2)))
    } elseif ($script:mood -eq 'sad') {
        Set-MascotFrame 16
    } else {
        $waveTime = $Seconds % 7.0
        if ($waveTime -lt 1.6) { Set-MascotFrame (8 + [int][Math]::Floor($waveTime * 2.5)) }
        else { Set-MascotFrame 8 }
    }
}
Set-MascotFrame 8
[Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($buddy)
$buddyDrink.Add_Click({ Record-Drink })
$buddyLater.Add_Click({ $snoozePopup.IsOpen = $true })
$buddy.FindName('Snooze5').Add_Click({ Snooze-Reminder 5 })
$buddy.FindName('Snooze10').Add_Click({ Snooze-Reminder 10 })
$buddy.FindName('Snooze15').Add_Click({ Snooze-Reminder 15 })
$buddy.FindName('BuddyClose').Add_Click({ Hide-Mascot })
$buddy.FindName('BuddySettings').Add_Click({ Open-Dashboard })
$buddy.FindName('TryReactions').Add_Click({ $snoozePopup.IsOpen = $false; $reactionPopup.IsOpen = $true })
$buddy.FindName('PreviewWalk').Add_Click({ Show-ReactionPreview 'walk' })
$buddy.FindName('PreviewHappy').Add_Click({ Show-ReactionPreview 'happy' })
$buddy.FindName('PreviewSad').Add_Click({ Show-ReactionPreview 'sad' })
$buddy.FindName('Walker').Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($script:leaving) { return }
    if ($e.ClickCount -eq 2) {
        if (-not $confirmationTimer.Enabled) {
            $script:arrivedAt = Get-Date
            $script:mood = 'greeting'
            Set-MascotFrame 9
            $buddyTitle.Text = 'Hi! I am right here.'
            $buddyText.Text = 'Bottle ready! Drag me to move me around.'
        }
        $e.Handled = $true
        return
    }
    if ($script:walking) { Complete-Walk }
    $script:targetX = $buddy.Left
    $animation.Stop()
    $buddy.DragMove()
    $script:targetX = $buddy.Left
    $script:data.PositionX = $buddy.Left
    $script:data.PositionY = $buddy.Top
    Save-Data
    $animation.Start()
})
function Show-ReactionPreview([string]$Mood) {
    $reactionPopup.IsOpen = $false
    Show-Reminder $true
    $script:previewOnly = $true
    $headerKicker.Text = 'PREVIEW ONLY - NO WATER LOGGED'
    $buddyDrink.IsEnabled = $false
    $buddyLater.IsEnabled = $false
    if ($Mood -eq 'walk') { return }
    Complete-Walk
    if ($Mood -eq 'happy') {
        Show-BuddyConfirmation 'Happy buddy!' 'Preview only. Your water count stays the same.'
        Show-Celebration
    } else {
        $script:mood = 'sad'
        $script:arrivedAt = Get-Date
        Set-MascotFrame 16
        Show-BuddyConfirmation 'Sad buddy...' 'Snooze preview. Your reminder time stays the same.'
    }
}
$confirmationTimer = New-Object Windows.Forms.Timer
$confirmationTimer.Interval = 2200
$confirmationTimer.Add_Tick({ Start-WalkAway })
function Show-Celebration {
    $script:mood = 'happy'
    $script:arrivedAt = Get-Date
    Set-MascotFrame 12
    $sparkles.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $sparkleLift.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $null)
    $sparkles.Opacity = 1
    $sparkleLift.Y = 0
    $fade = New-Object Windows.Media.Animation.DoubleAnimation(1.0, 0.0, [Windows.Duration]::new([TimeSpan]::FromSeconds(1.8)))
    $rise = New-Object Windows.Media.Animation.DoubleAnimation(0.0, -45.0, [Windows.Duration]::new([TimeSpan]::FromSeconds(1.8)))
    $sparkles.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
    $sparkleLift.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $rise)
}
function Show-BuddyConfirmation($Title, $Message) {
    $buddyTitle.Text = $Title
    $buddyText.Text = $Message
    $buddyDrink.IsEnabled = $false
    $buddyLater.IsEnabled = $false
    $confirmationTimer.Start()
}
$script:bounce = 0
$script:targetX = 0
$script:buddyShownAt = Get-Date
$script:walking = $false
$script:leaving = $false
$script:walkDuration = 3.2
function Start-WalkAway {
    $confirmationTimer.Stop()
    $snoozePopup.IsOpen = $false
    $reactionPopup.IsOpen = $false
    if (-not [Windows.SystemParameters]::ClientAreaAnimation) { Hide-Mascot; return }
    $script:walking = $false
    $script:leaving = $true
    $walkFlip.ScaleX = -1
    $script:exitStartedAt = Get-Date
    $script:exitStartX = $buddy.Left
    $script:exitEndX = [Windows.SystemParameters]::WorkArea.Right
    $script:exitDuration = 1.8
    if ($script:mood -eq 'sad') { $script:exitDuration = 2.6 }
    $animation.Start()
}
function Update-ExitFrame([double]$Elapsed) {
    $p = [Math]::Min(1.0, [Math]::Max(0.0, $Elapsed / $script:exitDuration))
    Set-ReminderPanels ([Math]::Max(0.0, 1.0 - $Elapsed / 0.25))
    $buddy.Left = $script:exitStartX + ($script:exitEndX - $script:exitStartX) * $p * $p
    if ($script:mood -eq 'sad') {
        Set-MascotFrame (16 + ([int][Math]::Floor($Elapsed * 5) % 4))
    } else {
        Set-MascotFrame ([int][Math]::Floor($Elapsed * 9) % 8)
    }
    $step = [Math]::Sin($p * [Math]::PI * 6)
    $walkTilt.Angle = 2.4 * $step
    $bob.Y = -3 * [Math]::Abs($step)
    if ($p -ge 1) { Hide-Mascot }
}
function Set-ReminderPanels([double]$Opacity) {
    foreach ($panel in $reminderPanels) {
        $panel.Opacity = $Opacity
        $panel.IsHitTestVisible = ($Opacity -ge 0.95)
    }
}
function Complete-Walk {
    $walkFlip.ScaleX = 1
    $script:mood = 'greeting'
    $script:arrivedAt = Get-Date
    Set-MascotFrame 8
    $script:walking = $false
    $buddy.Left = $script:targetX
    $walkTilt.Angle = 0
    $bob.Y = 0
    Set-ReminderPanels 1
}
function Update-WalkFrame([double]$Elapsed) {
    $progress = [Math]::Min(1.0, [Math]::Max(0.0, $Elapsed / $script:walkDuration))
    $travel = $progress * $progress * (3 - 2 * $progress)
    $buddy.Left = $script:walkStartX + ($script:targetX - $script:walkStartX) * $travel
    if ($progress -lt 1) {
        Set-MascotFrame ([int][Math]::Floor($Elapsed * 9) % 8)
        $phase = $progress * [Math]::PI * 8
        $step = [Math]::Sin($phase)
        $walkTilt.Angle = 2.4 * $step
        $bob.Y = -3 * [Math]::Abs([Math]::Sin($phase))
    } else {
        $walkTilt.Angle = 0
        $bob.Y = 0
        Set-ReminderPanels ([Math]::Min(1.0, ($Elapsed - $script:walkDuration) / 0.35))
        if ($Elapsed -ge ($script:walkDuration + 0.35)) {
            Complete-Walk
            if ($script:data.Sound -and -not $SmokeTest) { [System.Media.SystemSounds]::Asterisk.Play() }
        }
    }
}
$animation = New-Object Windows.Forms.Timer
$animation.Interval = 25
$animation.Add_Tick({
    if ($script:leaving) {
        Update-ExitFrame (((Get-Date) - $script:exitStartedAt).TotalSeconds)
    } elseif ($script:walking) {
        Update-WalkFrame (((Get-Date) - $script:walkStartedAt).TotalSeconds)
    } else {
        Update-IdlePose (((Get-Date) - $script:arrivedAt).TotalSeconds)
        $script:bounce += 0.08
        $bob.Y = 1.5 * [Math]::Sin($script:bounce)
    }
    # Let a forgotten reminder leave after two minutes without logging a drink.
    if (((Get-Date) - $script:buddyShownAt).TotalMinutes -ge 2) { Hide-Mascot }
})
function Hide-Mascot {
    $confirmationTimer.Stop()
    $animation.Stop()
    $buddy.Hide()
    $snoozePopup.IsOpen = $false
    $reactionPopup.IsOpen = $false
    $script:previewOnly = $false
    $script:leaving = $false
    $script:walking = $false
    $script:reminderOpen = $false
}
$buddy.Add_Closing({ param($sender, $e); if (-not $script:exitApp) { $e.Cancel = $true; Hide-Mascot } })

function Update-View {
    $now = Get-Date
    $today = $now.ToString('yyyy-MM-dd')
    $entries = @($script:data.Entries | Where-Object { ([datetime]$_.Time).ToString('yyyy-MM-dd') -eq $today })
    $total = ($entries | ForEach-Object { [int]$_.Ml } | Measure-Object -Sum).Sum
    if ($null -eq $total) { $total = 0 }
    $totalLabel.Text = "Today: $total ml logged"
    $drinkButton.Text = 'I drank water - log ' + $amount.Value + ' ml'
    $drinkAmount.Text = 'Save ' + $amount.Value + ' ml'
    $amountBadge.Text = $amount.Value.ToString() + ' ml'
    $buddyProgress.Text = $total.ToString() + ' ml today'
    $buddy.FindName('BuddyFill').Width = 328 * [Math]::Min(1.0, [double]$total / $script:data.PlanMl)
    $planLabel.Text = '10 reminders = ' + ([int]$amount.Value * 10) + ' ml in this window'
    $next = Get-NextSlot $now
    if ($null -ne $script:snoozeUntil -and $script:snoozeUntil -lt $next) { $next = $script:snoozeUntil }
    $nextLabel.Text = 'Next reminder: ' + $next.ToString('ddd, h:mm tt') + '  |  Computer local time'
    if ($null -ne $script:dashboard) { Update-Dashboard }
}
function Show-Reminder([bool]$Test = $false) {
    $confirmationTimer.Stop()
    $script:leaving = $false
    $snoozePopup.IsOpen = $false
    $reactionPopup.IsOpen = $false
    $script:previewOnly = $false
    $headerKicker.Text = 'YOUR LITTLE WATER BUDDY'
    $sparkles.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $sparkles.Opacity = 0
    $buddyDrink.IsEnabled = $true
    $buddyLater.IsEnabled = $true
    $script:reminderOpen = $true
    $notice.Text = 'Time for water! Sip ' + $amount.Value + ' ml if you need it.'
    if ($Test) { $notice.Text = 'TEST - ' + $notice.Text }
    $buddyTitle.Text = 'Ready for a sip?'
    $buddyText.Text = 'Your bottle is here! ' + $amount.Value + " ml for a little water break."
    if ($Test) {
        $buddyTitle.Text = 'Ready for a sip?'
        $buddyText.Text = "Your bottle is here! Take a little water break."
    }
    $area = [Windows.SystemParameters]::WorkArea
    $script:targetX = $area.Right - $buddy.Width - 16
    $targetY = $area.Bottom - $buddy.Height - 12
    if ($null -ne $script:data.PositionX -and $null -ne $script:data.PositionY) {
        $script:targetX = [Math]::Max([double]$area.Left, [Math]::Min([double]$script:data.PositionX, [double]($area.Right - $buddy.Width)))
        $targetY = [Math]::Max([double]$area.Top, [Math]::Min([double]$script:data.PositionY, [double]($area.Bottom - $buddy.Height)))
    }
    $script:walkStartX = $area.Right - 50
    $buddy.Left = $script:walkStartX
    $buddy.Top = $targetY
    $script:buddyShownAt = Get-Date
    $script:bounce = 0
    $script:walking = $true
    $walkFlip.ScaleX = 1
    $script:mood = 'greeting'
    $script:walkStartedAt = Get-Date
    Set-ReminderPanels 0
    Update-WalkFrame 0
    if (-not [Windows.SystemParameters]::ClientAreaAnimation) { Complete-Walk }
    $buddy.Show()
    $animation.Start()
    if (-not $SmokeTest) {
        @{ ProcessId = $PID; BuddyVisible = $buddy.IsVisible; ShownAt = (Get-Date).ToString('o'); X = $buddy.Left; Y = $buddy.Top; ImageLoaded = ($null -ne $picture.Source); Buttons = @('I drank water', 'Remind me later'); Design = '16-pose animated bottle buddy'; AnimationFrames = $script:mascotFrames.Count; WalkDurationSeconds = $script:walkDuration } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime-status.json') -Encoding UTF8
    }
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({
    $now = Get-Date
    if ($script:lastDate -ne $now.Date) {
        $script:lastDate = $now.Date
        $script:snoozeUntil = $null
        $script:reminderOpen = $false
        $form.TopMost = $false
        Hide-Mascot
        $notice.Text = 'A new day. Reminders are on from 7 AM to 4 PM.'
    }
    $due = Get-DueSlot $now
    if ($null -ne $due -and $script:data.LastReminder -ne $due.ToString('o')) {
        $script:data.LastReminder = $due.ToString('o')
        Save-Data
        if ($null -eq $script:snoozeUntil -or $script:snoozeUntil -le $now) {
            $script:snoozeUntil = $null
            Show-Reminder
        }
    } elseif ($null -ne $script:snoozeUntil -and $now -ge $script:snoozeUntil) {
        $script:snoozeUntil = $null
        if ($now -le $now.Date.AddHours(16)) { Show-Reminder }
    }
    Update-View
})
$form.Add_FormClosing({
    param($sender, $e)
    if (-not $script:exitApp) {
        $e.Cancel = $true
        $form.TopMost = $false
        $form.Hide()
        $tray.ShowBalloonTip(3000, 'Reminders still running', 'Open the tray icon to return. Choose Exit to stop reminders.', [Windows.Forms.ToolTipIcon]::Info)
    }
})
Save-Data
Start-DesktopSync
. (Join-Path $PSScriptRoot 'Dashboard.ps1')
Update-View
$timer.Start()
$form.Add_Shown({
    $form.Hide()
    if ($Preview) { Show-Reminder $true }
    if ($ShowDashboard -or (-not $Background -and -not $Preview -and -not $SmokeTest)) { Open-Dashboard }
})
if ($SmokeTest) {
    $smoke = New-Object Windows.Forms.Timer
    $smoke.Interval = 1500
    $smoke.Add_Tick({
        $smoke.Stop()
        try {
        $originalEntries = @($script:data.Entries)
        Show-Reminder $true
        if ($form.Controls.Count -lt 15) { throw 'Missing UI controls' }
        Update-WalkFrame 0
        if ($reminderPanels[0].Opacity -ne 0) { throw 'Reminder visible before arrival' }
        Update-WalkFrame 0.2
        if ($script:activeFrame -ne 1) { throw 'Walk sprite did not advance' }
        if ($buddy.Left -ge $script:walkStartX -or $buddy.Left -le $script:targetX) { throw 'Walking position invalid' }
        Update-WalkFrame 3.7
        if ($script:walking -or $reminderPanels[0].Opacity -ne 1 -or $buddy.Left -ne $script:targetX) { throw 'Arrival failed' }
        Update-IdlePose 0.9
        if ($script:activeFrame -ne 10) { throw 'Wave/blink frame missing' }
        Update-IdlePose 2.0
        if ($script:activeFrame -ne 8) { throw 'Idle frame missing' }
        $buddy.UpdateLayout()
        $previewBitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap(800, 1088, 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
        $previewBitmap.Render($buddy.Content)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($previewBitmap))
        $previewStream = [IO.File]::Create((Join-Path $PSScriptRoot 'buddy-preview.png'))
        $encoder.Save($previewStream)
        $previewStream.Close()
        $form.Hide()
        $before = @($script:data.Entries).Count
        $buddyDrink.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if (@($script:data.Entries).Count -ne ($before + 1)) { throw 'Buddy log button failed while dashboard hidden' }
        if ($buddyDrink.IsEnabled -or -not $confirmationTimer.Enabled) { throw 'Confirmation missing' }
        if ($script:activeFrame -ne 12 -or $script:mood -ne 'happy') { throw 'Happy expression missing' }
        Show-Reminder $true
        Update-WalkFrame 3.7
        $before = @($script:data.Entries).Count
        $buddyLater.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if (-not $snoozePopup.IsOpen) { throw 'Snooze choices missing' }
        $buddy.FindName('Snooze10').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if (@($script:data.Entries).Count -ne $before) { throw 'Snooze incorrectly logged water' }
        if (-not $confirmationTimer.Enabled) { throw 'Snooze confirmation missing' }
        Update-IdlePose 0.8
        if ($script:mood -ne 'sad' -or $script:activeFrame -ne 16) { throw 'Snooze must show sad expression' }
        Start-WalkAway
        # Explicitly exercise exit frames even when Windows animations are disabled.
        $script:exitStartX = $buddy.Left
        $script:exitEndX = [Windows.SystemParameters]::WorkArea.Right
        $script:exitDuration = 2.6
        Update-ExitFrame 0.9
        if ($script:activeFrame -lt 16 -or $script:activeFrame -gt 19) { throw 'Sad departure used happy frame' }
        if ($buddy.Left -le $script:exitStartX) { throw 'Exit movement failed' }
        Update-ExitFrame 2.7
        if ($buddy.IsVisible) { throw 'Exit did not finish' }
        Show-Reminder $true
        Update-WalkFrame 3.7
        if ($script:mood -ne 'greeting' -or $script:activeFrame -ne 8) { throw 'Next reminder failed to reset expression' }
        $before = @($script:data.Entries).Count
        $snoozeBefore = $script:snoozeUntil
        Show-ReactionPreview 'happy'
        Record-Drink
        if (@($script:data.Entries).Count -ne $before -or $script:mood -ne 'happy') { throw 'Happy preview changed water log' }
        Show-ReactionPreview 'sad'
        Snooze-Reminder 5
        if ($script:snoozeUntil -ne $snoozeBefore -or $script:mood -ne 'sad') { throw 'Sad preview changed snooze' }
        $script:data.PositionX = [Windows.SystemParameters]::WorkArea.Left + 40
        $script:data.PositionY = [Windows.SystemParameters]::WorkArea.Top + 30
        Show-Reminder $true
        Complete-Walk
        if ($buddy.Left -ne $script:data.PositionX -or $buddy.Top -ne $script:data.PositionY) { throw 'Saved position was not restored' }
        $script:data.Entries = $originalEntries
        Open-Dashboard
        $before = @($script:data.Entries).Count
        $dashboard.FindName('Log200').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if (@($script:data.Entries).Count -ne ($before + 1) -or $script:data.Entries[-1].Ml -ne 200) { throw 'Dashboard quick log failed' }
        $dashboard.FindName('DashUndo').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
        if (@($script:data.Entries).Count -ne $before) { throw 'Dashboard undo failed' }
        $dashboard.UpdateLayout()
        $dashBitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap(900, 654, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $dashBitmap.Render($dashboard.Content)
        $dashEncoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $dashEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($dashBitmap))
        $dashStream = [IO.File]::Create((Join-Path $PSScriptRoot 'dashboard-preview.png'))
        $dashEncoder.Save($dashStream)
        $dashStream.Close()
        $script:exitApp = $true
        $form.Close()
        } catch {
            $script:smokeFailure = $_.Exception.Message
            $script:exitApp = $true
            $form.Close()
        }
    })
    $smoke.Start()
}
try { [Windows.Forms.Application]::Run($form) }
finally {
    $timer.Stop()
    if ($null -ne $script:syncBridge) { $script:syncBridge.Dispose() }
    $animation.Stop()
    $confirmationTimer.Stop()
    $script:exitApp = $true
    $buddy.Close()
    if ($null -ne $script:dashboard) { $dashboard.Close() }
    $tray.Visible = $false
    $tray.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
if ($SmokeTest) {
    if ($script:smokeFailure) { throw $script:smokeFailure }
    Write-Output 'PASS: walking arrival, celebration/log action, snooze picker, walk-away and clean shutdown.'
}
