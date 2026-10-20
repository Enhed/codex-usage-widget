# ------------------------------------------------------------------ XAML ----

# The window markup lives next door in widget.xaml.
$xamlText = Convert-ThemeXaml (Get-Content -Raw -Encoding UTF8 (Join-Path $script:Root 'ui\widget.xaml'))

[xml]$xaml = $xamlText
$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)
Add-ThemeTo $win -Pattern

$UI = @{}
foreach ($match in [regex]::Matches($xamlText, 'x:Name="([^"]+)"')) {
    $n=$match.Groups[1].Value
    $UI[$n] = $win.FindName($n)
}

$win.Opacity = [double]$script:Cfg.opacity
$win.Topmost = [bool]$script:Cfg.topmost
$BarWidth    = 238.0

# Scale is set by a transform on the root Border: LayoutTransform affects measuring,
# so SizeToContent grows the window by itself, and all layout stays in original
# units - no need to recompute bar widths.
function Set-Scale([double]$k) {
    if ($k -lt 0.6) { $k = 0.6 }
    if ($k -gt 4.0) { $k = 4.0 }
    $win.Content.LayoutTransform = New-Object System.Windows.Media.ScaleTransform $k, $k
}
Set-Scale ([double]$script:Cfg.scale)

$win.WindowStartupLocation = 'Manual'
$area = [System.Windows.SystemParameters]::WorkArea
$win.Left = $area.Right - 380
$win.Top  = $area.Top + 20
# runtime.ps1 validates the saved coordinates against connected screens.
