#requires -Version 5.1
[CmdletBinding()]
param([switch]$Check,[switch]$SmokeTest,[string]$Screenshot,[string]$Theme,[string]$Mood)
$ErrorActionPreference='Stop'
$script:Root=Split-Path -Parent $PSScriptRoot
$script:DataRoot=Join-Path $script:Root 'data'
$script:Preview=[bool]($SmokeTest -or $Screenshot)
if ($script:Preview -and $env:CODEX_WIDGET_TEST_DATA) { $script:DataRoot=$env:CODEX_WIDGET_TEST_DATA }
$script:ConfigPath=Join-Path $script:DataRoot 'config.json'
[void][IO.Directory]::CreateDirectory($script:DataRoot)
function Write-WidgetLog($context,$errorRecord) {
    try {
        $message='{0:s} {1}: {2} {3}' -f (Get-Date),$context,$errorRecord.Exception.Message,$errorRecord.InvocationInfo.PositionMessage
        $message | Out-File (Join-Path $script:DataRoot 'widget-error.log') -Append -Encoding utf8
    } catch {}
}
trap { Write-WidgetLog 'start' $_; Write-Error $_ -ErrorAction Continue; exit 1 }
. (Join-Path $PSScriptRoot 'usage.ps1')
if ($Check) { Format-CodexUsage (Get-CodexUsage); return }
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Win32 -Name IconUtil -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr handle);
'@
$created=$false
$name='Local\codex-usage-widget'
if ($script:Preview) { $name += '-preview-' + $PID }
$mutex=New-Object Threading.Mutex($false,$name,[ref]$created)
if (-not $created) { $mutex.Dispose(); return }
try {
    foreach ($module in @('config','i18n','format','theme','window','mascot-activity','mascot','skins','hearts','mascot-step',
        'weather','sky','scene','space','ocean','halloween','cyberpunk','mascot-menu',
        'codex-data','history','service-status','settings-controls','settings','tray','runtime')) {
        . (Join-Path $PSScriptRoot "lib\$module.ps1")
    }
    if ($Theme) { $script:Cfg.theme=$Theme }
    if ($script:Preview) {
        $script:Cfg.left=$null; $script:Cfg.top=$null; $script:Cfg.expanded=$true
        $script:Cfg.showHistory=$true
        $script:History=@()
        $script:LastResult=[pscustomobject]@{
            rateLimits=[pscustomobject]@{limitId='codex'
                primary=[pscustomobject]@{usedPercent=24;windowDurationMins=300;resetsAt=[DateTimeOffset]::UtcNow.AddHours(3).ToUnixTimeSeconds()}
                secondary=[pscustomobject]@{usedPercent=76;windowDurationMins=10080;resetsAt=[DateTimeOffset]::UtcNow.AddDays(4).ToUnixTimeSeconds()}}
            widgetAccount=[pscustomobject]@{planType='Plus';email='preview@example.com'}
            widgetThreads=@([pscustomobject]@{updatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()})
        }
        foreach ($i in 1..20) {
            foreach ($spec in @(@('codex/primary','Codex / 5h',(($i*7)%75)),@('codex/secondary','Codex / 7d',(30+$i*2)))) {
                $script:History += [pscustomobject]@{at=[DateTimeOffset]::UtcNow.AddHours(-168+$i*8).ToUnixTimeSeconds();id=$spec[0];name=$spec[1];percent=$spec[2]}
            }
        }
        $UI.LineStatus.Text='OpenAI · preview'; $UI.LineStamp.Text='Preview'
    }
    Apply-Settings
    if ($Mood) { $script:Mz.force=$Mood }
    $dispatcher=[Windows.Threading.Dispatcher]::CurrentDispatcher
    $dispatcher.Add_UnhandledException({param($s,$e) Write-WidgetLog 'ui' $e; $e.Handled=$true})
    $win.Add_Closed({ $timer.Stop(); $mascotTimer.Stop(); [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })
    $win.Show()
    if ($SmokeTest) {
        foreach ($moodId in $MascotMoods) {
            $script:Mz.force=$moodId
            1..3 | ForEach-Object { Step-Mascot }
        }
        foreach ($skinId in (Get-Skins).Keys) {
            $script:Cfg.skin=$skinId; Set-Skin; Step-Mascot
        }
        $script:Cfg.skin='classic'; Set-Skin
        Stop-MascotDemo
        Show-Settings -SmokeTest
        if ($Theme -eq 'cyberpunk') {
            . (Join-Path $script:Root 'tools\test-mascot-scene.ps1')
            Test-MascotSleepScene
        }
    }
    Update-Widget
    $timer.Start()
    if ($script:Preview) {
        $closer=New-Object Windows.Threading.DispatcherTimer
        $closer.Interval=[TimeSpan]::FromSeconds(3)
        $closer.Add_Tick({
            $closer.Stop()
            try {
                if ($Screenshot) {
                    $win.UpdateLayout()
                    if ([math]::Abs($win.Content.LayoutTransform.Value.M11 - [double]$script:Cfg.scale) -gt 0.01) { throw 'Scale setting was not applied' }
                    $image=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int][math]::Ceiling($win.ActualWidth)),([int][math]::Ceiling($win.ActualHeight)),96,96,([Windows.Media.PixelFormats]::Pbgra32)
                    $image.Render($win)
                    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
                    $stream=[IO.File]::Create($Screenshot)
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                }
                if ($script:Mz.broken -or $script:Sky.broken -or $script:Scene.broken.Count) { throw 'Animation failed; inspect data/widget-error.log' }
                Write-Output 'PASS: window, quota data, mascot, sky, scenes and tray initialized'
            } catch { Write-WidgetLog 'preview' $_; $script:PreviewFailed=$true }
            $win.Close()
        })
        $closer.Start()
    }
    [Windows.Threading.Dispatcher]::Run()
} finally {
    if ($timer) { $timer.Stop() }
    if ($mascotTimer) { $mascotTimer.Stop() }
    if ($script:Worker) { $script:Worker.Stop(); $script:Worker.Dispose() }
    if ($script:ActivityWorker) { $script:ActivityWorker.Stop(); $script:ActivityWorker.Dispose() }
    if ($notify) { $notify.Visible=$false; if ($notify.Icon) { $notify.Icon.Dispose() }; $notify.Dispose() }
    $mutex.Dispose()
}
if ($script:PreviewFailed) { exit 1 }
