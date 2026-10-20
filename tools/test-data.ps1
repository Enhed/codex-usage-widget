#requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'src\lib\codex-data.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
. (Join-Path $project 'src\lib\mascot-activity.ps1')
$activityNow=[DateTimeOffset]::Parse('2026-10-20T21:17:00+03:00')
foreach ($case in @(@(0,'idle'),@(599,'idle'),@(600,'doze'),@(1199,'doze'),@(1200,'sleep'),@(86400,'sleep'))) {
    $at=$activityNow.ToUnixTimeSeconds()-$case[0]
    Assert ((Get-MascotActivityMood $at $activityNow) -eq $case[1]) "Wrong activity mood at $($case[0]) seconds"
}
Set-MascotChatActivity @([pscustomobject]@{updatedAt=$activityNow.AddMinutes(-30).ToUnixTimeSeconds()},[pscustomobject]@{updatedAt=$activityNow.AddMinutes(-12).ToUnixTimeSeconds()})
Assert ((Get-MascotActivityMood $script:LastChatUpdate $activityNow) -eq 'doze') 'Latest chat must determine activity'
$remembered=$script:LastChatUpdate
Set-MascotChatActivity $null
Assert ($script:LastChatUpdate -eq $remembered) 'Failed refresh must retain known activity'
Set-MascotChatActivity @([pscustomobject]@{updatedAt=$activityNow.ToUnixTimeSeconds()})
Assert ((Get-MascotActivityMood $script:LastChatUpdate $activityNow) -eq 'idle') 'New chat update must wake the mascot'
Assert ((Get-MascotActivityMood $null $activityNow) -eq 'idle') 'Unknown activity must not invent sleep'
'PASS: activity boundaries at 10/20 minutes, latest chat, failed refresh and waking'
$sessionCases=@(
    [pscustomobject]@{status=[pscustomobject]@{type='notLoaded'};widgetTurnStatus='inProgress'},
    [pscustomobject]@{status=[pscustomobject]@{type='notLoaded'};widgetTurnStatus='completed'},
    [pscustomobject]@{status=[pscustomobject]@{type='active';activeFlags=@('waitingOnApproval')};widgetTurnStatus='inProgress'}
)
$sessions=@(Get-MascotSessions $sessionCases)
Assert ($sessions.Count -eq 2) 'Completed turns must not be counted as working'
Assert (@($sessions | Where-Object busy).Count -eq 1) 'External server work must be detected'
Assert (@($sessions | Where-Object waiting).Count -eq 1) 'Approval wait must not be counted as running'
Assert (@(Get-MascotSessions @()).Count -eq 0) 'No running turns must stop running'
'PASS: running, completed and approval-waiting states'
$zero=[pscustomobject]@{usedPercent=0;windowDurationMins=300;resetsAt=0}
$week=[pscustomobject]@{usedPercent=76;windowDurationMins=10080;resetsAt=1792800000}
$legacy=[pscustomobject]@{rateLimits=[pscustomobject]@{limitId='codex';primary=$zero;secondary=$week}}
$rows=@(Get-QuotaWindows $legacy)
Assert ($rows.Count -eq 2) 'Legacy quotas missing'
Assert ($rows[0].percent -eq 0) 'Zero usage must not be missing'
Assert ($rows[0].reset.Year -eq 1970) 'Epoch reset must not be missing'
$multi=[pscustomobject]@{rateLimits=$legacy.rateLimits;rateLimitsByLimitId=[pscustomobject]@{
    other=[pscustomobject]@{limitId='other';primary=[pscustomobject]@{usedPercent=180};secondary=$null}
    codex=$legacy.rateLimits
}}
$rows=@(Get-QuotaWindows $multi)
Assert ($rows.Count -eq 3) 'Multi-bucket quotas missing or duplicated'
Assert ($rows[0].id -eq 'codex/primary') 'Main bucket must sort first'
Assert ($rows[2].percent -eq 100) 'Out-of-range percentage must be clamped'
Assert ($null -eq $rows[2].reset) 'Missing reset must not become epoch'
$empty=[pscustomobject]@{rateLimitsByLimitId=[pscustomobject]@{};rateLimits=$legacy.rateLimits}
Assert (@(Get-QuotaWindows $empty).Count -eq 2) 'Empty map must fall back to legacy quotas'
$single=[pscustomobject]@{rateLimits=[pscustomobject]@{limitId='codex';secondary=$week}}
Assert (@(Get-QuotaWindows $single).Count -eq 1) 'Secondary-only accounts must work'
Assert (@(Get-QuotaWindows ([pscustomobject]@{})).Count -eq 0) 'Missing data must not become zero'
'PASS: quota fallbacks, multiple buckets, nulls, zero, reset times, ranges, secondary-only accounts'
$script:DataRoot=Join-Path ([IO.Path]::GetTempPath()) ('codex-widget-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:DataRoot)
$script:Preview=$false
function Write-WidgetLog($context,$record) { throw $record }
try {
    . (Join-Path $project 'src\lib\history.ps1')
    Add-History @(Get-QuotaWindows $legacy)
    Assert ($script:History.Count -eq 2) 'History must record both windows'
    . (Join-Path $project 'src\lib\history.ps1')
    Assert ($script:History.Count -eq 2) 'History must survive a reload without nesting'
    Add-History @(Get-QuotaWindows $single)
    . (Join-Path $project 'src\lib\history.ps1')
    Assert ($script:History.Count -eq 3) 'History samples lost across restart'
    Assert ($null -ne $script:History[0].at) 'History samples became array wrappers'
    'PASS: history round trip across two restarts'
} finally {
    foreach ($p in @(Get-ChildItem -LiteralPath $script:DataRoot -File)) { [IO.File]::Delete($p.FullName) }
    [IO.Directory]::Delete($script:DataRoot)
}
