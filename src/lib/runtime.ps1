$script:Worker=$null; $script:Pending=$null
$script:NextRefresh=[datetime]::MinValue; $script:LastSuccess=$null; $script:LastResult=$null
$script:QuotaRows=@(); $script:ConfigStamp=[datetime]::MinValue
$script:ActivityWorker=$null; $script:ActivityPending=$null; $script:NextActivity=[datetime]::MinValue
function Update-MascotActivityProbe {
    if ($script:Preview) { return }
    if ($script:ActivityPending -and $script:ActivityPending.IsCompleted) {
        $retry=5
        try {
            $snapshot=$script:ActivityWorker.EndInvoke($script:ActivityPending)
            if ($script:ActivityWorker.HadErrors) { throw $script:ActivityWorker.Streams.Error[0] }
            Set-MascotChatActivity $snapshot[0].widgetThreads
            Set-MascotMood @(Get-MascotSessions $snapshot[0].widgetThreads) @{session=$script:Mz.pct}
        } catch {
            # Do not keep running forever on a stale working-state snapshot.
            Set-MascotMood @() @{session=$script:Mz.pct}
            $retry=30
            Write-WidgetLog 'activity' $_
        } finally {
            $script:ActivityWorker.Dispose(); $script:ActivityWorker=$null; $script:ActivityPending=$null
            $script:NextActivity=(Get-Date).AddSeconds($retry)
        }
    }
    if (-not $script:ActivityPending -and (Get-Date) -ge $script:NextActivity) {
        $script:ActivityWorker=[PowerShell]::Create()
        [void]$script:ActivityWorker.AddScript('param($path) . $path; Get-CodexUsage -ActivityOnly -TimeoutSeconds 12').AddArgument((Join-Path $script:Root 'src\usage.ps1'))
        $script:ActivityPending=$script:ActivityWorker.BeginInvoke()
    }
}
function Save-Position {
    if ($script:Preview -or $win.WindowState -ne 'Normal') { return }
    $script:Cfg.left=$win.Left; $script:Cfg.top=$win.Top
    Save-Config $script:Cfg
}
function Restore-Position {
    if ($script:Preview) { $win.WindowStartupLocation='CenterScreen'; return }
    if ($null -eq $script:Cfg.left -or $null -eq $script:Cfg.top) { return }
    try {
        $left=[double]$script:Cfg.left; $top=[double]$script:Cfg.top
        if ([double]::IsNaN($left) -or [double]::IsNaN($top) -or [double]::IsInfinity($left) -or [double]::IsInfinity($top)) { throw 'Invalid position' }
        $transform=[Windows.PresentationSource]::FromVisual($win).CompositionTarget.TransformFromDevice
        $header=[Windows.Rect]::new($left,$top,160,32)
        foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
            $a=$screen.WorkingArea
            $origin=$transform.Transform([Windows.Point]::new($a.Left,$a.Top))
            $end=$transform.Transform([Windows.Point]::new($a.Right,$a.Bottom))
            $visible=[Windows.Rect]::Intersect($header,[Windows.Rect]::new($origin,$end))
            if (-not $visible.IsEmpty -and $visible.Width -ge 64 -and $visible.Height -ge 24) { $win.Left=$left; $win.Top=$top; return }
        }
    } catch {}
    $win.Left=[Windows.SystemParameters]::WorkArea.Left+30
    $win.Top=[Windows.SystemParameters]::WorkArea.Top+30
}
function Update-Widget {
    if (-not $script:Preview -and (Test-Path $script:ConfigPath)) {
        $stamp=(Get-Item $script:ConfigPath).LastWriteTimeUtc
        if ($stamp -ne $script:ConfigStamp) {
            $script:ConfigStamp=$stamp; $script:Cfg=Load-Config; Apply-Settings
        }
    }
    Collect-WeatherProbe
    if (-not $script:Preview -and $script:Cfg.showSky -and $script:Cfg.showMascot -and
        ((Get-Date)-$script:WxTry).TotalSeconds -ge $script:Cfg.weatherIntervalSeconds) { Start-WeatherProbe }
    Update-ServiceStatus
    Update-MascotActivityProbe
    if ($script:Pending -and $script:Pending.IsCompleted) {
        try {
            $result=$script:Worker.EndInvoke($script:Pending)
            if ($script:Worker.HadErrors) { throw $script:Worker.Streams.Error[0] }
            Show-Usage $result[0]
            $script:LastResult=$result[0]; $script:LastSuccess=Get-Date
            Add-History $script:QuotaRows
            Draw-History
            $UI.LineStamp.Text=$script:LastSuccess.ToString('HH:mm:ss')
            $UI.LineStamp.ToolTip=L 'Последнее успешное обновление' 'Last successful refresh'
        } catch {
            $UI.LineStamp.Text=L 'Нет связи' 'Offline'
            $UI.LineStamp.ToolTip=$_.Exception.Message
            if (-not $script:LastSuccess) { $UI.LineReset.Text=$_.Exception.Message }
            else { $UI.LineStamp.Text=(L 'Устарело · ' 'Stale · ')+$script:LastSuccess.ToString('HH:mm') }
            Write-WidgetLog 'usage' $_
        } finally {
            $script:Worker.Dispose(); $script:Worker=$null; $script:Pending=$null
            $script:NextRefresh=(Get-Date).AddSeconds($script:Cfg.usageIntervalSeconds)
        }
    }
    if (-not $script:Preview -and -not $script:Pending -and (Get-Date) -ge $script:NextRefresh) {
        $UI.LineStamp.Text=L 'Обновление…' 'Updating…'
        $script:Worker=[PowerShell]::Create()
        [void]$script:Worker.AddScript('param($path) . $path; Get-CodexUsage').AddArgument((Join-Path $script:Root 'src\usage.ps1'))
        $script:Pending=$script:Worker.BeginInvoke()
    }
    # Countdowns are refreshed without additional network traffic.
    if ($script:QuotaRows.Count -and $script:LastSuccess) { $UI.LineReset.Text=Get-ResetText $script:QuotaRows[0] }
    Sync-Mascot
}
$UI.Header.Add_MouseLeftButtonDown({ param($s,$e)
    if ($e.OriginalSource -eq $s -or ($e.OriginalSource -is [Windows.Controls.TextBlock] -and -not $e.OriginalSource.Name)) {
        $win.DragMove(); Save-Position
    }
})
$UI.BtnSettings.Add_MouseLeftButtonUp({ Show-Settings })
$UI.BtnToggle.Add_MouseLeftButtonUp({ $script:Cfg.expanded=-not $script:Cfg.expanded; Save-Config $script:Cfg; Apply-Settings })
$UI.BtnHide.Add_MouseLeftButtonUp({ $win.Hide() })
$UI.BtnExit.Add_MouseLeftButtonUp({ $win.Close() })
$UI.LineVersion.Add_MouseLeftButtonUp({ $script:NextRefresh=[datetime]::MinValue })
$UI.StatusRow.Add_MouseLeftButtonUp({ Start-Process 'https://status.openai.com' })
$UI.Mascot.Add_MouseLeftButtonUp({ Start-MascotClick })
$win.Add_SourceInitialized({ Restore-Position })
$win.Add_Closing({ $script:Closing=$true; Save-Position })
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({ try { Update-Widget } catch { Write-WidgetLog 'tick' $_ } })
