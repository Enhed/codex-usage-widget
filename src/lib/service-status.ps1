$script:StatusTask=$null; $script:StatusTry=[datetime]::MinValue
function Update-ServiceStatus {
    if (-not $script:Cfg.showStatus -or $script:Preview) { return }
    if ($script:StatusTask -and $script:StatusTask.IsCompleted) {
        try {
            $s=$script:StatusTask.GetAwaiter().GetResult() | ConvertFrom-Json
            $UI.LineStatus.Text=$s.status.description
            $color=if ($s.status.indicator -eq 'none') { '#FF4ADE80' } else { '#FFFBBF24' }
            $UI.StatusDot.Fill=New-Brush $color
            $UI.StatusRow.ToolTip=L 'Общий статус OpenAI · открыть status.openai.com' 'Overall OpenAI status · open status.openai.com'
        } catch {
            $UI.LineStatus.Text=L 'Статус OpenAI недоступен' 'OpenAI status unavailable'
            $UI.StatusDot.Fill=New-Brush '#FF6B7280'
        } finally { $script:StatusTask=$null }
    }
    if (-not $script:StatusTask -and ((Get-Date)-$script:StatusTry).TotalSeconds -ge 120) {
        $script:StatusTry=Get-Date
        try { $script:StatusTask=(New-WebClient).DownloadStringTaskAsync('https://status.openai.com/api/v2/status.json') } catch {}
    }
}
