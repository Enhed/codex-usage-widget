. (Join-Path $PSScriptRoot '..\src\usage.ps1')
. (Join-Path $PSScriptRoot '..\src\lib\mascot-activity.ps1')
$result=Get-CodexUsage
$threads=@($result.widgetThreads | Where-Object { $_ })
Set-MascotChatActivity $result.widgetThreads
"Now UTC: $([DateTimeOffset]::UtcNow.ToString('s'))"
"Threads returned: $($threads.Count)"
"Newest updatedAt: $script:LastChatUpdate"
if ($script:LastChatUpdate) { "Last update UTC: $([DateTimeOffset]::FromUnixTimeSeconds($script:LastChatUpdate).ToString('s'))" }
"Automatic mood: $(Get-MascotActivityMood $script:LastChatUpdate)"
if ($threads.Count) { 'Thread fields: '+($threads[0].PSObject.Properties.Name -join ', ') }
$threads | Group-Object { $_.status.type } | ForEach-Object { "Status $($_.Name): $($_.Count)" }
$sessions=@(Get-MascotSessions $threads)
"Running: $(@($sessions | Where-Object busy).Count)"
"Waiting: $(@($sessions | Where-Object waiting).Count)"
$threads | Group-Object widgetTurnStatus | ForEach-Object { "Stored turn status $($_.Name): $($_.Count)" }
$fastWatch=[Diagnostics.Stopwatch]::StartNew()
$fast=Get-CodexUsage -ActivityOnly
$fastWatch.Stop()
"Local activity check: $($fastWatch.ElapsedMilliseconds) ms; running $(@(Get-MascotSessions $fast.widgetThreads | Where-Object busy).Count)"
