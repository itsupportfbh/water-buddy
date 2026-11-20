[xml]$dashboardXml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Dashboard.xaml') -Raw
$dashboardReader = New-Object Xml.XmlNodeReader($dashboardXml)
$script:dashboard = [Windows.Markup.XamlReader]::Load($dashboardReader)
$dashboardReader.Close()
$dashboard.FindName('DashboardMascot').Source = $script:mascotFrames[8]
[Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($dashboard)
function Open-Dashboard {
    Hide-Mascot
    $dashboard.FindName('PrefAmount').Text = $amount.Value.ToString()
    $dashboard.FindName('PrefPlan').Text = $script:data.PlanMl.ToString()
    $dashboard.FindName('PrefSound').IsChecked = $sound.Checked
    $dashboard.FindName('PrefStartup').IsChecked = $startup.Checked
    $dashboard.Show()
    $dashboard.Activate() | Out-Null
    Update-Dashboard
    if (-not $SmokeTest) {
        @{ ProcessId = $PID; DashboardVisible = $dashboard.IsVisible; Design = 'Today dashboard with water-fill progress'; ShownAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime-status.json') -Encoding UTF8
    }
}
function Update-Dashboard {
    if ($null -eq $script:dashboard -or -not $dashboard.IsVisible) { return }
    $now = Get-Date
    $todayEntries = @($script:data.Entries | Where-Object { ([datetime]$_.Time).Date -eq $now.Date })
    $sum = ($todayEntries | ForEach-Object { [int]$_.Ml } | Measure-Object -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }
    $ratio = [Math]::Min(1.0, [double]$sum / $script:data.PlanMl)
    $dashboard.FindName('DashDate').Text = $now.ToString('dddd, d MMMM')
    $dashboard.FindName('DashTotal').Text = ([int]$sum).ToString('N0')
    $dashboard.FindName('DashPercent').Text = ([int]([double]$sum / $script:data.PlanMl * 100)).ToString() + '% of reminder plan'
    $dashboard.FindName('DashPlan').Text = 'Reminder plan: ' + $script:data.PlanMl.ToString('N0') + ' ml'
    $dashboard.FindName('WaterFill').Height = $ratio * 180
    $next = Get-NextSlot $now
    if ($null -ne $script:snoozeUntil -and $script:snoozeUntil -lt $next) { $next = $script:snoozeUntil }
    $dashboard.FindName('DashNext').Text = 'Next: ' + $next.ToString('h:mm tt')
    if ($next.Date -gt $now.Date) { $dashboard.FindName('DashNext').Text = 'Tomorrow: ' + $next.ToString('h:mm tt') }
    $history = @($todayEntries | Sort-Object { [datetime]$_.Time } -Descending | ForEach-Object { ([datetime]$_.Time).ToString('h:mm tt').PadRight(12) + $_.Ml.ToString() + ' ml' })
    if ($history.Count -eq 0) { $history = @('Your first sip starts here.') }
    $dashboard.FindName('DrinkHistory').ItemsSource = $history
    $bars = $dashboard.FindName('WeekBars')
    $bars.Children.Clear()
    $totals = @(for ($i = 6; $i -ge 0; $i--) {
        $date = $now.Date.AddDays(-$i)
        $daySum = ($script:data.Entries | Where-Object { ([datetime]$_.Time).Date -eq $date } | ForEach-Object { [int]$_.Ml } | Measure-Object -Sum).Sum
        if ($null -eq $daySum) { $daySum = 0 }
        @{ Day = $date; Ml = [double]$daySum }
    })
    $max = [Math]::Max(1.0, [double]($totals.Ml | Measure-Object -Maximum).Maximum)
    foreach ($item in $totals) {
        $column = New-Object Windows.Controls.StackPanel
        $column.VerticalAlignment = 'Bottom'
        $value = New-Object Windows.Controls.TextBlock
        $value.Text = ([int]$item.Ml).ToString()
        $value.FontSize = 9
        $value.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6D8A92')
        $value.HorizontalAlignment = 'Center'
        $column.Children.Add($value) | Out-Null
        $bar = New-Object Windows.Controls.Border
        $bar.Width = 30
        $bar.Height = [Math]::Max(4.0, $item.Ml / $max * 44)
        $bar.CornerRadius = New-Object Windows.CornerRadius(8)
        $bar.Margin = New-Object Windows.Thickness(0, 5, 0, 6)
        $color = '#D7E9EE'
        if ($item.Day -eq $now.Date) { $color = '#34A6B5' }
        $bar.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
        $column.Children.Add($bar) | Out-Null
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $item.Day.ToString('ddd')
        $label.FontSize = 9
        $label.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6D8A92')
        $label.HorizontalAlignment = 'Center'
        $column.Children.Add($label) | Out-Null
        $bars.Children.Add($column) | Out-Null
    }
}
$dashboard.FindName('NavToday').Add_Click({
    $dashboard.FindName('NavToday').Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#187C87')
    $dashboard.FindName('NavToday').Foreground = [Windows.Media.Brushes]::White
    $dashboard.FindName('NavPrefs').Background = [Windows.Media.Brushes]::Transparent
    $dashboard.FindName('NavPrefs').Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#24535D')
    $dashboard.FindName('TodayPanel').Visibility = 'Visible'
    $dashboard.FindName('PrefsPanel').Visibility = 'Collapsed'
    Update-Dashboard
})
$dashboard.FindName('NavPrefs').Add_Click({
    $dashboard.FindName('NavPrefs').Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#187C87')
    $dashboard.FindName('NavPrefs').Foreground = [Windows.Media.Brushes]::White
    $dashboard.FindName('NavToday').Background = [Windows.Media.Brushes]::Transparent
    $dashboard.FindName('NavToday').Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#24535D')
    $dashboard.FindName('TodayPanel').Visibility = 'Collapsed'
    $dashboard.FindName('PrefsPanel').Visibility = 'Visible'
})
$dashboard.FindName('Log150').Add_Click({ Record-Drink 150; $dashboard.FindName('DashFeedback').Text = '150 ml logged. Nice little water break.' })
$dashboard.FindName('Log200').Add_Click({ Record-Drink 200; $dashboard.FindName('DashFeedback').Text = '200 ml logged. Nice little water break.' })
$dashboard.FindName('Log250').Add_Click({ Record-Drink 250; $dashboard.FindName('DashFeedback').Text = '250 ml logged. Nice little water break.' })
$dashboard.FindName('DashUndo').Add_Click({ Undo-LastDrink; $dashboard.FindName('DashFeedback').Text = 'Last drink removed.' })
$dashboard.FindName('DashPreview').Add_Click({ $dashboard.Hide(); Show-Reminder $true; Complete-Walk; $reactionPopup.IsOpen = $true })
$dashboard.FindName('DashHide').Add_Click({ $dashboard.Hide() })
$dashboard.FindName('DashExit').Add_Click({ $script:exitApp = $true; $form.Close() })
$dashboard.FindName('SavePrefs').Add_Click({
    $glass = 0
    $plan = 0
    if (-not [int]::TryParse($dashboard.FindName('PrefAmount').Text, [ref]$glass) -or $glass -lt 50 -or $glass -gt 500 -or -not [int]::TryParse($dashboard.FindName('PrefPlan').Text, [ref]$plan) -or $plan -lt 500 -or $plan -gt 4000) {
        $dashboard.FindName('PrefFeedback').Text = 'Use 50-500 ml for a glass and 500-4000 ml for the reminder plan.'
        return
    }
    $script:data.PlanMl = $plan
    $amount.Value = $glass
    $sound.Checked = [bool]$dashboard.FindName('PrefSound').IsChecked
    $startup.Checked = [bool]$dashboard.FindName('PrefStartup').IsChecked
    Save-Data
    Update-View
    $dashboard.FindName('PrefFeedback').Text = 'Saved. Your reminders will use these preferences.'
})
$dashboard.Add_Closing({ param($sender, $e); if (-not $script:exitApp) { $e.Cancel = $true; $dashboard.Hide() } })

$dashboard.FindName('OpenWebDashboard').Add_Click({ Open-WebDashboard })
