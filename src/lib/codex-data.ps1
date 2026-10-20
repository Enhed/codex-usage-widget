function Get-QuotaWindows($usage) {
    $buckets = @()
    if ($usage.rateLimitsByLimitId) { $buckets = @($usage.rateLimitsByLimitId.PSObject.Properties | ForEach-Object { $_.Value }) }
    if (-not $buckets.Count -and $usage.rateLimits) { $buckets = @($usage.rateLimits) }
    # Put the main Codex bucket first without discarding additional quotas.
    $buckets = @($buckets | Sort-Object @{Expression={ if ($_.limitId -eq 'codex') { 0 } else { 1 } }}, limitId)
    foreach ($b in $buckets) {
        foreach ($key in @('primary','secondary')) {
            $q = $b.$key
            if ($null -eq $q -or $null -eq $q.usedPercent) { continue }
            $reset = $null
            if ($null -ne $q.resetsAt) { $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$q.resetsAt).UtcDateTime }
            $name = if ($b.limitName) { $b.limitName } elseif ($b.limitId) { $b.limitId } else { 'Codex' }
            [pscustomobject]@{ id = "$($b.limitId)/$key"; name = $name; key = $key
                percent = [math]::Max(0,[math]::Min(100,[double]$q.usedPercent))
                minutes = $q.windowDurationMins; reset = $reset; plan = $b.planType }
        }
    }
}
function Format-QuotaName($q) {
    $m = $q.minutes
    $duration = if (-not $m) { $q.key } elseif ($m % 1440 -eq 0) { '{0}d' -f ($m/1440) } elseif ($m % 60 -eq 0) { '{0}h' -f ($m/60) } else { '{0}m' -f $m }
    return "$($q.name) / $duration"
}
function Get-ResetText($q) {
    if (-not $q.reset) { return L 'Время сброса недоступно' 'Reset time unavailable' }
    $span = Format-Span $q.reset
    $clock = $q.reset.ToLocalTime().ToString('dd.MM HH:mm')
    if ($span) { return (L 'Сброс через {0} · {1}' 'Reset in {0} · {1}') -f $span,$clock }
    return L 'Ожидаем обновления лимита' 'Waiting for quota refresh'
}
function Show-Usage($result) {
    $rows = @(Get-QuotaWindows $result)
    if (-not $rows.Count) { throw (L 'Лимиты недоступны. Выполни codex login через ChatGPT.' 'No quotas. Run codex login with ChatGPT.') }
    $script:QuotaRows = $rows
    $main = $rows[0]
    $UI.QuotaLabel.Text = ((L 'ИСПОЛЬЗОВАНО · ' 'USED · ') + (Format-QuotaName $main)).ToUpperInvariant()
    $UI.PctText.Text = '{0:0.#}' -f $main.percent
    $UI.PctText.ToolTip = (Format-QuotaName $main) + ' · ' + (L 'использовано' 'used')
    $brush = New-Brush $Palette[(Get-Level $main.percent)].Wpf
    $UI.PctText.Foreground = $brush
    $UI.BarSession.Background = $brush
    $UI.BarSession.Width = $BarWidth * $main.percent / 100
    $UI.LineReset.Text = Get-ResetText $main
    $UI.LblWeek.Text = if ($rows.Count -gt 1) { Format-QuotaName $rows[1] } else { L 'ЛИМИТ' 'QUOTA' }
    $UI.LineWeek.Text = ''
    $UI.BarWeek.Width = 0
    $UI.WeekRow.Visibility = if ($rows.Count -gt 1) { 'Visible' } else { 'Collapsed' }
    $UI.WeekTrack.Visibility = $UI.WeekRow.Visibility
    if ($rows.Count -gt 1) {
        $second = $rows[1]
        $UI.LineWeek.Text = '{0:0.#}%' -f $second.percent
        $UI.LineWeek.ToolTip = Get-ResetText $second
        $UI.LineWeek.Text += ' · ' + $(if ($second.reset) { Format-ResetClock $second.reset } else { '--' })
        $UI.BarWeek.Width = $BarWidth * $second.percent / 100
    }
    $UI.AdditionalQuotas.Children.Clear()
    foreach ($q in @($rows | Select-Object -Skip 2)) {
        $label = New-Object Windows.Controls.TextBlock
        $label.FontSize = 10; $label.Margin = '0,4,0,3'; $label.Foreground = New-Brush '#FF8B8B94'
        $label.Text = '{0} · {1:0.#}%' -f (Format-QuotaName $q),$q.percent
        $label.ToolTip = Get-ResetText $q
        [void]$UI.AdditionalQuotas.Children.Add($label)
        $track = New-Object Windows.Controls.Border
        $track.Height=4; $track.Background=New-Brush '#26FFFFFF'; $track.CornerRadius=2
        $fill = New-Object Windows.Controls.Border
        $fill.Width=$BarWidth*$q.percent/100; $fill.HorizontalAlignment='Left'; $fill.CornerRadius=2
        $fill.Background=New-Brush $Palette[(Get-Level $q.percent)].Wpf
        $track.Child=$fill; [void]$UI.AdditionalQuotas.Children.Add($track)
    }
    $account = $result.widgetAccount
    $UI.SessionsPanel.Visibility = if ($script:Cfg.showSessions -and $null -ne $result.widgetThreads) { 'Visible' } else { 'Collapsed' }
    $UI.LineAccount.Text = if ($script:Cfg.showAccount) { @($account.planType,$account.email) | Where-Object { $_ } | Join-Text ' · ' } else { '' }
    $UI.LineAccount.ToolTip = $UI.LineAccount.Text
    $threads = @($result.widgetThreads | Where-Object { $_ })
    $recent = @($threads | Where-Object { $_.updatedAt -ge [DateTimeOffset]::UtcNow.AddDays(-1).ToUnixTimeSeconds() })
    $UI.LineSessions.Text = (L '{0} за 24 часа' '{0} in last 24 hours') -f $recent.Count
    $UI.SessionsPanel.ToolTip = L 'Недавно обновлённые локальные чаты Codex (до 100). Это не число работающих агентов.' 'Recently updated local Codex threads (up to 100). This is not an active-agent count.'
    $UI.Activity.Text=''
    $buckets=@($result.widgetActivity.dailyUsageBuckets | Where-Object { $null -ne $_ })
    if ($buckets.Count) {
        $today=(Get-Date).ToString('yyyy-MM-dd')
        $cutoff=(Get-Date).AddDays(-6).ToString('yyyy-MM-dd')
        $daily=($buckets | Where-Object { $_.startDate -eq $today } | Measure-Object -Property tokens -Sum).Sum
        $weekly=($buckets | Where-Object { $_.startDate -ge $cutoff -and $_.startDate -le $today } | Measure-Object -Property tokens -Sum).Sum
        $UI.Activity.Text=(L 'Токены аккаунта · сегодня {0:N0} · 7 дней {1:N0}' 'Account tokens · today {0:N0} · 7 days {1:N0}') -f $daily,$weekly
        $UI.Activity.ToolTip=L 'Дневные данные сервиса Codex; границы дня определяет сервис.' 'Daily data from Codex services; day boundaries are defined by the service.'
    }
    $UI.Projects.Children.Clear()
    $weekStart=[DateTimeOffset]::UtcNow.AddDays(-7).ToUnixTimeSeconds()
    $groups=@($threads | Where-Object { $_.cwd -and $_.updatedAt -ge $weekStart } | Group-Object cwd | Sort-Object Count -Descending | Select-Object -First 5)
    if ($groups.Count) {
        $caption=New-Object Windows.Controls.TextBlock; $caption.FontSize=9; $caption.Foreground=New-Brush '#FF6B7280'; $caption.Margin='0,0,0,4'
        $caption.Text=L 'ПРОЕКТЫ · ЧАТЫ ЗА 7 ДНЕЙ' 'PROJECTS · THREADS IN 7 DAYS'
        [void]$UI.Projects.Children.Add($caption)
        foreach ($g in $groups) {
            $label=New-Object Windows.Controls.TextBlock; $label.FontSize=10; $label.Foreground=New-Brush '#FF8B8B94'
            $label.Text='{0} · {1}' -f (Split-Path $g.Name -Leaf),$g.Count
            $label.ToolTip=$g.Name; $label.TextTrimming='CharacterEllipsis'
            [void]$UI.Projects.Children.Add($label)
        }
    }
    $ss = @(Get-MascotSessions $result.widgetThreads)
    Set-MascotChatActivity $result.widgetThreads
    $real = @{session=$main.percent;sessionReset=$main.reset}
    Set-MascotMood $ss $real
    Set-TrayIcon ('{0:0}' -f $main.percent) $Palette[(Get-Level $main.percent)].Drawing
    $tip = 'Codex: {0:0.#}% / {1}' -f $main.percent,(Format-QuotaName $main)
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0,63) }
    $notify.Text = $tip
    Draw-History
}
function Join-Text { param([string]$Separator, [Parameter(ValueFromPipeline=$true)]$Item) begin { $items=@() } process { $items += $Item } end { $items -join $Separator } }
