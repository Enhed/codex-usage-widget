function L([string]$ru,[string]$en) { if ((Get-Lang) -eq 'ru') { return $ru }; return $en }
function Apply-Settings {
    Set-Theme; Set-Skin; Set-Scale ([double]$script:Cfg.scale)
    $win.Topmost=[bool]$script:Cfg.topmost; $win.Opacity=[double]$script:Cfg.opacity
    $UI.Details.Visibility=if ($script:Cfg.expanded) { 'Visible' } else { 'Collapsed' }
    $UI.HistPanel.Visibility=if ($script:Cfg.showHistory) { 'Visible' } else { 'Collapsed' }
    $UI.SessionsPanel.Visibility=if ($script:Cfg.showSessions) { 'Visible' } else { 'Collapsed' }
    $UI.StatusRow.Visibility=if ($script:Cfg.showStatus) { 'Visible' } else { 'Collapsed' }
    $UI.LblSessions.Text=L 'ЧАТЫ' 'THREADS'; $UI.LblHist.Text=L 'ЛИМИТЫ · 7 ДНЕЙ' 'QUOTAS · 7 DAYS'
    $UI.BtnSettings.ToolTip=L 'Настройки' 'Settings'; $UI.BtnToggle.ToolTip=L 'Подробнее' 'Details'
    $UI.BtnHide.ToolTip=L 'Скрыть в трей' 'Minimize to tray'; $UI.BtnExit.ToolTip=L 'Выход' 'Exit'
    $UI.LineClawdVer.Text='Widget v0.2.0'
    $UI.LineVersion.Text=L 'Обновить сейчас ↻' 'Refresh now ↻'
    $UI.Mascot.ContextMenu=New-MascotMenu; $UI.Sky.ContextMenu=$UI.Mascot.ContextMenu
    Sync-Mascot
    if ($script:LastResult) { Show-Usage $script:LastResult }
    Build-TrayMenu
    Update-Settings
}

# The original tabbed settings shell and controls, adapted to this widget.
$setMarkup=[xml](Convert-ThemeXaml (Get-Content (Join-Path $script:Root 'ui\settings.xaml') -Raw -Encoding UTF8))
$setWin=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $setMarkup))
Add-ThemeTo $setWin -Pattern
foreach ($n in @('SetTitle','SetHeader','SetClose','SetTabLook','SetTabWindow','SetTabData','SetScroll','SetPage','SetMore')) { $UI[$n]=$setWin.FindName($n) }
$Languages=[ordered]@{ru='Русский';en='English'}
$script:SetTab='look'
$script:SetKey=$null
$script:SettingsThemes=@{}
$UI.SetHeader.Add_MouseLeftButtonDown({ param($s,$e) if ($e.OriginalSource -ne $UI.SetClose) { $setWin.DragMove() } })
$UI.SetClose.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled=$true; $setWin.Hide() })
$setWin.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Escape') { $setWin.Hide() } })
$setWin.Add_Closing({ param($s,$e) if (-not $script:Closing) { $e.Cancel=$true; $setWin.Hide() } })
foreach ($tabSpec in @(@('SetTabLook','look'),@('SetTabWindow','window'),@('SetTabData','data'))) {
    $UI[$tabSpec[0]].Tag=$tabSpec[1]
    $UI[$tabSpec[0]].Add_MouseLeftButtonDown({ param($s,$e) $e.Handled=$true; Set-SettingsTab $s.Tag })
}
$UI.SetMore.Add_MouseLeftButtonDown({
    param($s,$e) $e.Handled=$true
    if (-not (Test-Path $script:ConfigPath)) { Save-Config $script:Cfg }
    Start-Process notepad.exe -ArgumentList ('"'+$script:ConfigPath+'"')
})
function Set-Setting([string]$key,$value) {
    $script:Cfg[$key]=$value
    Save-Config $script:Cfg
    Apply-Settings
}
function Set-SettingsTab([string]$tab) {
    $script:SetTab=$tab
    Update-Settings
    $UI.SetScroll.ScrollToTop()
}
function Add-SetWindowPage($p) {
    $scaleRow=New-SetStepper (T 'set.size') ('{0:N0}%' -f (100*[double]$script:Cfg.scale)) {
        param($s,$e) $e.Handled=$true
        Set-Setting 'scale' ([math]::Max(0.6,[math]::Round([double]$script:Cfg.scale-0.1,2)))
    } {
        param($s,$e) $e.Handled=$true
        Set-Setting 'scale' ([math]::Min(4.0,[math]::Round([double]$script:Cfg.scale+0.1,2)))
    }
    $script:SettingScaleMinus=$scaleRow.Children[1].Children[0]
    $script:SettingScalePlus=$scaleRow.Children[1].Children[2]
    [void]$p.Children.Add($scaleRow)
    [void]$p.Children.Add((New-SetStepper (T 'set.opacity') ('{0:N0}%' -f (100*[double]$script:Cfg.opacity)) {
        param($s,$e) $e.Handled=$true
        Set-Setting 'opacity' ([math]::Max(0.3,[math]::Round([double]$script:Cfg.opacity-0.05,2)))
    } {
        param($s,$e) $e.Handled=$true
        Set-Setting 'opacity' ([math]::Min(1.0,[math]::Round([double]$script:Cfg.opacity+0.05,2)))
    }))
    [void]$p.Children.Add((New-SetToggle 'topmost' (T 'set.topmost')))
    [void]$p.Children.Add((New-SetHeader (T 'set.shown')))
    foreach ($key in @('showMascot','showSky','showStatus','showSessions','showAccount','showHistory')) {
        [void]$p.Children.Add((New-SetToggle $key (T "set.$key")))
    }
}
function Add-SetDataPage($p) {
    [void]$p.Children.Add((New-SetHeader (L 'Обновление лимитов' 'Quota refresh')))
    $choices=New-Object Windows.Controls.WrapPanel
    foreach ($seconds in @(30,60,120,300)) {
        [void]$choices.Children.Add((New-ListChip (('{0} ' -f $seconds)+(L 'сек' 'sec')) ($script:Cfg.usageIntervalSeconds -eq $seconds) $seconds {
            param($s,$e) $e.Handled=$true
            Set-Setting 'usageIntervalSeconds' ([double]$s.Tag)
            $script:NextRefresh=[datetime]::MinValue
        }))
    }
    [void]$p.Children.Add($choices)
    [void]$p.Children.Add((New-SetHeader (L 'Пороги предупреждений' 'Warning thresholds')))
    $text=(L 'Жёлтый: {0}% · красный: {1}%' 'Yellow: {0}% · red: {1}%') -f $script:Cfg.warnPercent,$script:Cfg.critPercent
    [void]$p.Children.Add((New-PanelText $text))
    $note=New-PanelText (L 'Погода определяется по IP. Координаты и пороги можно изменить в config.json.' 'Weather uses your IP location. Coordinates and thresholds can be changed in config.json.') 10 '#FF8B8B94'
    $note.Margin='0,12,0,0'; [void]$p.Children.Add($note)
}
function Update-Settings {
    if (-not $setWin -or -not $setWin.IsVisible) { return }
    $scale=[math]::Min(2.0,[double]$script:Cfg.scale)
    $setWin.Content.LayoutTransform=[Windows.Media.ScaleTransform]::new($scale,$scale)
    $setWin.Topmost=$win.Topmost
    $UI.SetScroll.MaxHeight=[math]::Max(120.0,[math]::Min(460.0,([Windows.SystemParameters]::WorkArea.Height-100)/$scale-100))
    $key="$script:SetTab|$($script:Cfg | ConvertTo-Json -Compress)"
    if ($key -eq $script:SetKey) { return }
    $script:SetKey=$key
    $UI.SetTitle.Text=(T 'set.title')+' · CODEX'
    $UI.SetMore.Text=L 'Остальные настройки — в config.json ↗' 'More settings in config.json ↗'
    foreach ($spec in @(@('SetTabLook','look',(T 'set.tabLook')),@('SetTabWindow','window',(T 'set.tabWindow')),@('SetTabData','data',(L 'Данные' 'Data')))) {
        $tab=$UI[$spec[0]]; $tab.Text=$spec[2]
        $active=$spec[1] -eq $script:SetTab
        $tab.Foreground=New-Brush $(if ($active) { '#FFF4F4F5' } else { '#FF6B7280' })
        if ($active) { $tab.TextDecorations=[Windows.TextDecorations]::Underline } else { $tab.TextDecorations=$null }
    }
    $UI.SetPage.Children.Clear()
    switch ($script:SetTab) {
        look { $script:SettingsThemes=@{}; Add-SetLookPage $UI.SetPage }
        window { Add-SetWindowPage $UI.SetPage }
        data { Add-SetDataPage $UI.SetPage }
    }
}
function Invoke-SettingsClick($element) {
    $event=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
    $event.RoutedEvent=[Windows.UIElement]::MouseLeftButtonDownEvent
    $element.RaiseEvent($event)
}
function Show-Settings {
    param([switch]$SmokeTest,[Nullable[double]]$SmokeScale,[string]$SmokeTheme,[string]$SmokeScreenshot)
    $setWin.Owner=$win
    $setWin.Show(); Update-Settings; $setWin.UpdateLayout()
    $area=[Windows.SystemParameters]::WorkArea
    $setWin.Left=[math]::Max($area.Left,[math]::Min($area.Right-$setWin.ActualWidth,$win.Left-$setWin.ActualWidth+10))
    $setWin.Top=[math]::Max($area.Top,[math]::Min($area.Bottom-$setWin.ActualHeight,$win.Top))
    [void]$setWin.Activate()
    if (-not $SmokeTest) { return }
    Set-SettingsTab 'look'
    foreach ($candidate in @('auto')+@($Themes.Keys)) {
        if (-not $script:SettingsThemes.ContainsKey($candidate)) { throw "Missing theme chip: $candidate" }
    }
    if ($SmokeTheme) { Invoke-SettingsClick $script:SettingsThemes[$SmokeTheme] }
    Set-SettingsTab 'window'
    if ($null -ne $SmokeScale) { Set-Setting 'scale' ([double]$SmokeScale) }
    $before=[double]$script:Cfg.scale
    Invoke-SettingsClick $script:SettingScaleMinus
    if ($script:Cfg.scale -ne [math]::Max(0.6,[math]::Round($before-0.1,2))) { throw 'Scale minus control failed' }
    Set-Setting 'scale' $before
    Set-SettingsTab 'data'
    Set-SettingsTab 'look'
    if ($SmokeScreenshot) { Export-SettingsPreview $SmokeScreenshot }
    $setWin.Hide()
}
function Export-SettingsPreview([string]$path) {
    $setWin.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][math]::Ceiling($setWin.ActualWidth),[int][math]::Ceiling($setWin.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($setWin)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
