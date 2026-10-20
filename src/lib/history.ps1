$script:HistoryPath = Join-Path $script:DataRoot 'usage-history.json'
$script:History = @()
if (Test-Path $script:HistoryPath) {
    try {
        $parsed=Get-Content $script:HistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # Windows PowerShell 5.1 emits a JSON array as one pipeline object.
        # Flatten it explicitly, including wrappers written by early builds.
        $queue=New-Object Collections.Queue
        foreach ($sample in $parsed) { $queue.Enqueue($sample) }
        while ($queue.Count) {
            $sample=$queue.Dequeue()
            if ($null -ne $sample.at -and $sample.id) { $script:History += $sample }
            elseif ($sample.value) { foreach ($child in $sample.value) { $queue.Enqueue($child) } }
        }
    } catch { Write-WidgetLog 'history' $_ }
}
function Add-History($rows) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $script:History = @($script:History | Where-Object { $_.at -gt $now - 7*86400 })
    foreach ($q in $rows) {
        $script:History += [pscustomobject]@{ at=$now; id=$q.id; percent=$q.percent; name=(Format-QuotaName $q) }
    }
    if ($script:Preview) { return }
    try {
        $temp = $script:HistoryPath + '.tmp'
        [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject @($script:History) -Compress), (New-Object Text.UTF8Encoding $true))
        Move-Item -LiteralPath $temp -Destination $script:HistoryPath -Force
    } catch { Write-WidgetLog 'history-save' $_ }
}
function Draw-History {
    $UI.HistChart.Children.Clear(); $UI.HistDays.Children.Clear()
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $start=$now-7*86400
    foreach ($y in @(0,22,43)) {
        $line=New-Object Windows.Shapes.Line
        $line.X1=0; $line.X2=$BarWidth; $line.Y1=$y; $line.Y2=$y
        $line.Stroke=New-Brush '#26FFFFFF'; [void]$UI.HistChart.Children.Add($line)
    }
    $colors=@('#FF4ADE80','#FF60A5FA','#FFA78BFA','#FFFBBF24')
    $i=0
    foreach ($q in $script:QuotaRows) {
        $points=@($script:History | Where-Object { $_.id -eq $q.id } | Sort-Object at)
        $poly=New-Object Windows.Shapes.Polyline
        $poly.Stroke=New-Brush $colors[$i % $colors.Count]; $poly.StrokeThickness=1.5
        foreach ($p in $points) {
            $x=[math]::Max(0,($p.at-$start)/(7*86400.0)*$BarWidth)
            $y=43-[math]::Max(0,[math]::Min(100,$p.percent))*0.43
            $poly.Points.Add([Windows.Point]::new($x,$y))
            $dot=New-Object Windows.Shapes.Ellipse
            $dot.Width=3; $dot.Height=3; $dot.Fill=$poly.Stroke
            $dot.ToolTip = '{0} · {1:0.#}% · {2}' -f $p.name,$p.percent,([DateTimeOffset]::FromUnixTimeSeconds($p.at).ToLocalTime().ToString('dd.MM HH:mm'))
            [Windows.Controls.Canvas]::SetLeft($dot,$x-1.5); [Windows.Controls.Canvas]::SetTop($dot,$y-1.5)
            [void]$UI.HistChart.Children.Add($dot)
        }
        [void]$UI.HistChart.Children.Add($poly); $i++
    }
    # Daily labels use local time; recorded samples keep UTC timestamps.
    for ($day=0; $day -le 6; $day++) {
        $label=New-Object Windows.Controls.TextBlock
        $label.Text=(Get-Date).AddDays($day-6).ToString('dd.MM'); $label.FontSize=7; $label.Foreground=New-Brush '#FF6B7280'
        [Windows.Controls.Canvas]::SetLeft($label,$day*$BarWidth/7)
        [void]$UI.HistDays.Children.Add($label)
    }
    $UI.HistCaption.Text=L 'История с первого запуска · наведи на точку' 'Recorded since first launch · hover over a point'
}
