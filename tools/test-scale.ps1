#requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$script:Root=Split-Path -Parent $PSScriptRoot
$script:DataRoot=Join-Path $script:Root ('data\scale-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:DataRoot)
$script:ConfigPath=Join-Path $script:DataRoot 'config.json'
$script:Preview=$false
function Write-WidgetLog($context,$record) { throw $record }
foreach ($module in @('config','i18n','format','theme','window','mascot-activity','mascot','skins','settings-controls','settings')) {
    . (Join-Path $script:Root "src\lib\$module.ps1")
}
function Sync-Mascot {}
function Build-TrayMenu {}
function New-MascotMenu { New-Object Windows.Controls.ContextMenu }
$win.Show()
try {
    foreach ($value in @(0.6,0.8,1.15,1.35,1.5,1.75,2)) {
        if ((Limit-Number $value 0.6 4 1.35) -ne $value) { throw "Fractional value changed: $value" }
    }
    if ((Limit-Number 0.7 0.3 1 1) -ne 0.7) { throw 'Opacity was rounded' }
    if ((Limit-Number 8 0.6 4 1.35) -ne 4) { throw 'Upper bound not enforced' }
    if ((Limit-Number 0.1 0.6 4 1.35) -ne 0.6) { throw 'Lower bound not enforced' }
    if ((Limit-Number ([double]::NaN) 0.6 4 1.35) -ne 1.35) { throw 'NaN fallback failed' }
    foreach ($scale in @(2,1.5,2,1.35,1.5)) {
        Show-Settings -SmokeTest -SmokeScale $scale
        $saved=Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        $script:Cfg=Load-Config
        Apply-Settings
        $win.UpdateLayout()
        Write-Output "requested=$scale saved=$($saved.scale) loaded=$($script:Cfg.scale) transform=$($win.Content.LayoutTransform.Value.M11) width=$($win.ActualWidth)"
        if ($saved.scale -ne $scale -or $script:Cfg.scale -ne $scale) { throw 'Scale did not persist' }
        if ([math]::Abs($win.ActualWidth-262*$scale) -gt 2) { throw 'Window size does not match scale' }
    }
    $script:Cfg.opacity=0.7
    Save-Config $script:Cfg
    $script:Cfg=Load-Config
    Apply-Settings
    if ($script:Cfg.opacity -ne 0.7 -or $win.Opacity -ne 0.7) { throw 'Opacity did not survive a reload' }
    'PASS: fractional scales, opacity, bounds and fallback values'
    Set-MascotMood @([pscustomobject]@{busy=$true;waiting=$false}) @{session=24}
    if ($script:Mz.mood -ne 'work') { throw 'Active work did not select running animation' }
    Set-MascotMood @() @{session=24}
    if ($script:Mz.mood -eq 'work') { throw 'Running did not stop after completion' }
    Set-MascotMood @([pscustomobject]@{busy=$true;waiting=$false}) @{session=100}
    if ($script:Mz.mood -ne 'dead') { throw 'Exhausted limit must take precedence' }
    Set-MascotMood @() @{session=24}
    'PASS: running animation starts/stops and respects quota exhaustion'
    foreach ($candidateTheme in @('auto')+@($Themes.Keys)) {
        Show-Settings -SmokeTest -SmokeTheme $candidateTheme
        $saved=Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        $script:Cfg=Load-Config
        Apply-Settings
        if ($saved.theme -ne $candidateTheme -or $script:Cfg.theme -ne $candidateTheme) { throw "Theme did not persist: $candidateTheme" }
    }
    "PASS: all $($Themes.Count+1) themes are selectable and survive reload"
    Set-Setting 'theme' 'classic'
    Set-Setting 'scale' 1.15
    Show-Settings
    foreach ($previewTab in @('look','window','data')) {
        Set-SettingsTab $previewTab
        Export-SettingsPreview (Join-Path $script:Root "docs\settings-$previewTab.png")
    }
    $setWin.Hide()
} finally {
    $script:Closing=$true
    if ($setWin) { $setWin.Close() }
    $win.Close()
    foreach ($p in @(Get-ChildItem -LiteralPath $script:DataRoot -File)) { [IO.File]::Delete($p.FullName) }
    [IO.Directory]::Delete($script:DataRoot)
}
