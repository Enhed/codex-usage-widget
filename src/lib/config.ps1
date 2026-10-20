$DefaultConfig = [ordered]@{
    usageIntervalSeconds = 60; scale = 1.35; opacity = 1.0; topmost = $false
    warnPercent = 75; critPercent = 90; expanded = $false
    language = 'ru'; theme = 'classic'; accent = $null; skin = 'classic'
    showMascot = $true; showSky = $true; showHistory = $true
    showSessions = $true; showAccount = $true; showStatus = $true
    weatherIntervalSeconds = 900; weatherLat = $null; weatherLon = $null
    left = $null; top = $null
}
function Load-Config {
    $cfg = [ordered]@{}
    foreach ($k in $DefaultConfig.Keys) { $cfg[$k] = $DefaultConfig[$k] }
    if (Test-Path $script:ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $raw.PSObject.Properties) { if ($cfg.Contains($p.Name)) { $cfg[$p.Name] = $p.Value } }
        } catch { Write-WidgetLog 'config' $_ }
    }
    $cfg.scale = Limit-Number $cfg.scale 0.6 4 1.35
    $cfg.opacity = Limit-Number $cfg.opacity 0.3 1 1
    $cfg.usageIntervalSeconds = Limit-Number $cfg.usageIntervalSeconds 30 3600 60
    $cfg.weatherIntervalSeconds = Limit-Number $cfg.weatherIntervalSeconds 300 86400 900
    $cfg.warnPercent = Limit-Number $cfg.warnPercent 0 100 75
    $cfg.critPercent = Limit-Number $cfg.critPercent $cfg.warnPercent 100 90
    return $cfg
}
function Limit-Number($value, [double]$min, [double]$max, [double]$fallback) {
    # Both bounds must be doubles: an integer first argument makes Math.Min
    # select its integer overload and round fractional settings on every reload.
    try { $v = [double]$value; if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) { return $fallback }; return [math]::Max($min,[math]::Min($max,$v)) }
    catch { return $fallback }
}
function Save-Config($cfg) {
    if ($script:Preview) { return }
    $temp = $script:ConfigPath + '.tmp'
    [IO.File]::WriteAllText($temp, ($cfg | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $true))
    Move-Item -LiteralPath $temp -Destination $script:ConfigPath -Force
}
$script:Cfg = Load-Config
# Migrate the small predecessor's window position without modifying its file.
if ($null -eq $script:Cfg.left) {
    foreach ($path in @('data\window-position.json','window-position.json')) {
        try {
            $p = Get-Content (Join-Path $script:Root $path) -Raw | ConvertFrom-Json
            $script:Cfg.left = $p.left; $script:Cfg.top = $p.top; break
        } catch {}
    }
}
