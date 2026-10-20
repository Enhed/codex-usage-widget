# Called by the cyberpunk preview with actual WPF scene objects already loaded.
function Test-MascotSleepScene {
    $savedUpdate=$script:LastChatUpdate
    $savedConfigTheme=$script:Cfg.theme
    try {
        Stop-MascotDemo
        $script:Cfg.theme='cyberpunk'; Set-Theme; $win.UpdateLayout()
        $script:LastChatUpdate=[DateTimeOffset]::UtcNow.AddMinutes(-21).ToUnixTimeSeconds()
        Set-MascotMood @() @{session=24}
        Step-Mascot
        if ($script:Mz.mood -ne 'sleep' -or $script:Mz.cur -ne 'sleep') { throw 'Animation did not enter sleep after 20 minutes' }
        # Override the clock only inside this function. Do not change system time.
        function Get-Date {
            param([string]$Format)
            if ($Format) { return $script:SceneTestClock.ToString($Format) }
            return $script:SceneTestClock
        }
        $script:Cyber.night=$null; $script:Cyber.relic=-1
        $script:SceneTestClock=[datetime]::new(2026,10,20,21,16,0)
        Step-Cyberpunk 10
        if ($script:Cyber.relic -ge 0) { throw 'Scene triggered before 21:17' }
        $script:SceneTestClock=[datetime]::new(2026,10,20,21,17,0)
        Step-Cyberpunk 20
        if ($script:Cyber.relic -lt 0) { throw 'Sleeping mascot did not trigger the 21:17 scene' }
        if ((T 'cyber.samurai') -eq 'cyber.samurai') { throw 'Scene text is missing' }
        Step-Relic -1 $CyberFx.ActualWidth $CyberFx.ActualHeight
        $script:Cyber.relic=-1
        Step-Cyberpunk 30
        if ($script:Cyber.relic -ge 0) { throw 'Scene triggered twice on the same evening' }
        'PASS: automatic sleep, scene timing, scene text and once-per-evening trigger'
    } finally {
        $script:Cyber.relic=-1
        Step-Relic -1 $CyberFx.ActualWidth $CyberFx.ActualHeight
        $script:LastChatUpdate=$savedUpdate
        $script:Cfg.theme=$savedConfigTheme
        Stop-MascotDemo
        Set-MascotMood @() @{session=24}
        Set-Theme
    }
}
