# Last known chat update, rather than the time at which the quota was polled.
$script:LastChatUpdate=$null
function Set-MascotChatActivity($threads) {
    if ($null -eq $threads) { return }
    $latest=0L
    foreach ($thread in $threads) {
        if ($null -ne $thread.updatedAt -and [long]$thread.updatedAt -gt $latest) { $latest=[long]$thread.updatedAt }
    }
    $script:LastChatUpdate=$latest
}
function Get-MascotActivityMood($lastUpdate,[DateTimeOffset]$now=[DateTimeOffset]::UtcNow) {
    # An unavailable thread list must not invent an inactivity period.
    if ($null -eq $lastUpdate) { return 'idle' }
    $seconds=[math]::Max(0L,($now.ToUnixTimeSeconds()-[long]$lastUpdate))
    if ($seconds -ge 1200) { return 'sleep' }
    if ($seconds -ge 600) { return 'doze' }
    return 'idle'
}
function Get-MascotSessions($threads) {
    foreach ($thread in $threads) {
        if ($null -eq $thread) { continue }
        $active=$thread.status.type -eq 'active'
        $waiting=$active -and @($thread.status.activeFlags | Where-Object { $_ -in @('waitingOnApproval','waitingOnUserInput') }).Count -gt 0
        $running=$active -or $thread.widgetTurnStatus -eq 'inProgress'
        if ($running) { [pscustomobject]@{busy=($running -and -not $waiting);waiting=$waiting} }
    }
}
