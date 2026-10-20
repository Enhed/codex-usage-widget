#requires -Version 5.1
. (Join-Path $PSScriptRoot 'lib\codex-running.ps1')
function Get-CodexUsage {
    [CmdletBinding()]
    param([int]$TimeoutSeconds = 25,[switch]$ActivityOnly)
    $ErrorActionPreference = 'Stop'
    if ($ActivityOnly) {
        $local=Get-LocalCodexActivity
        if ($null -ne $local) { return $local }
    }
    $command = Get-Command codex.exe, codex.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw 'Codex CLI not found. Install Codex and run codex login.' }
    $executable = $command.Source
    if ($executable.EndsWith('.ps1')) {
        # Prefer the npm package's native binary: PowerShell shims can consume stdin.
        $package = Join-Path (Split-Path $executable) 'node_modules\@openai\codex'
        if (Test-Path $package) {
            $native = Get-ChildItem $package -Filter codex.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($native) { $executable = $native.FullName }
        }
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    if ($executable.EndsWith('.exe')) {
        $info.FileName = $executable
        $info.Arguments = 'app-server'
    } else {
        $info.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $executable + '" app-server'
    }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $started = $false
    try {
        $null = $process.Start()
        $started = $true
        # Drain stderr so diagnostic output cannot fill the pipe and block the server.
        $stderr = $process.StandardError.ReadToEndAsync()
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        function Send-Rpc($message) {
            $process.StandardInput.WriteLine(($message | ConvertTo-Json -Depth 8 -Compress))
            $process.StandardInput.Flush()
        }
        function Receive-Rpc($id) {
            while ([DateTime]::UtcNow -lt $deadline) {
                $read = $process.StandardOutput.ReadLineAsync()
                while (-not $read.Wait(100)) {
                    if ([DateTime]::UtcNow -ge $deadline) { throw "Codex request $id timed out. Check Codex login and network access." }
                }
                if ($null -eq $read.Result) { throw 'Codex app-server closed the connection.' }
                try { $message = $read.Result | ConvertFrom-Json } catch { continue }
                if ($null -ne $message.id -and $message.id -eq $id) {
                    if ($message.error) { throw $message.error.message }
                    return $message.result
                }
            }
            throw 'Codex request timed out.'
        }
        function Read-ThreadActivity {
            Send-Rpc @{ id = 4; method = 'thread/list'; params = @{
                limit = 100; archived = $false; sortKey = 'updated_at'; useStateDbOnly = $true
                sourceKinds = @('cli','vscode','exec','appServer','subAgent','subAgentReview','subAgentCompact','subAgentThreadSpawn','subAgentOther','unknown')
            } }
            $items=@((Receive-Rpc 4).data)
            $local=Get-LocalCodexActivity
            $working=@{}
            foreach ($entry in $local.widgetThreads) { $working[$entry.id]=$entry.widgetTurnStatus }
            foreach ($thread in $items) {
                if ($working.ContainsKey($thread.id)) { $thread | Add-Member -NotePropertyName widgetTurnStatus -NotePropertyValue $working[$thread.id] -Force }
            }
            return $items
        }
        Send-Rpc @{ id = 1; method = 'initialize'; params = @{ clientInfo = @{ name = 'codex_usage_widget'; version = '0.1.0' } } }
        $initialized = Receive-Rpc 1
        Send-Rpc @{ method = 'initialized'; params = @{} }
        if ($ActivityOnly) {
            return [pscustomobject]@{widgetThreads=@(Read-ThreadActivity)}
        }
        Send-Rpc @{ id = 2; method = 'account/rateLimits/read' }
        $usage = Receive-Rpc 2
        # Optional metadata must never make a successful quota read fail.
        $account = $null; $threads = $null; $activity = $null
        try {
            Send-Rpc @{ id = 3; method = 'account/read'; params = @{ refreshToken = $false } }
            $account = (Receive-Rpc 3).account
            $threads = @(Read-ThreadActivity)
        } catch {}
        try {
            Send-Rpc @{ id = 5; method = 'account/usage/read' }
            $activity = Receive-Rpc 5
        } catch {}
        $usage | Add-Member -NotePropertyName widgetAccount -NotePropertyValue $account -Force
        $usage | Add-Member -NotePropertyName widgetThreads -NotePropertyValue $threads -Force
        $usage | Add-Member -NotePropertyName widgetServer -NotePropertyValue $initialized.userAgent -Force
        $usage | Add-Member -NotePropertyName widgetActivity -NotePropertyValue $activity -Force
        return $usage
    } finally {
        if ($started) {
            try { $process.StandardInput.Close() } catch {}
            if (-not $process.WaitForExit(1500)) {
                # Kill only our own process tree, including the npm shim's child.
                & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>$null | Out-Null
            }
        }
        $process.Dispose()
    }
}

function Format-CodexUsage {
    param($Usage)
    $buckets = @()
    if ($Usage.rateLimitsByLimitId) {
        $buckets = @($Usage.rateLimitsByLimitId.PSObject.Properties | ForEach-Object { $_.Value })
    }
    if (-not $buckets.Count -and $Usage.rateLimits) { $buckets = @($Usage.rateLimits) }
    foreach ($bucket in $buckets) {
        $name = if ($bucket.limitName) { $bucket.limitName } elseif ($bucket.limitId) { $bucket.limitId } else { 'Codex' }
        foreach ($key in @('primary', 'secondary')) {
            $window = $bucket.$key
            if ($null -eq $window -or $null -eq $window.usedPercent) { continue }
            $minutes = $window.windowDurationMins
            $duration = if (-not $minutes) { $key } elseif ($minutes % 1440 -eq 0) { '{0}d' -f ($minutes / 1440) } elseif ($minutes % 60 -eq 0) { '{0}h' -f ($minutes / 60) } else { '{0}m' -f $minutes }
            $reset = if ($null -ne $window.resetsAt) { [DateTimeOffset]::FromUnixTimeSeconds([long]$window.resetsAt).ToLocalTime().ToString('dd.MM HH:mm') } else { '--' }
            '{0} / {1}: {2:0.#}% used{3}Reset: {4}' -f $name, $duration, $window.usedPercent, [Environment]::NewLine, $reset
        }
    }
}
