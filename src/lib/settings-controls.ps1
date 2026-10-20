function New-PanelText([string]$text, [double]$size = 10.5, [string]$color = '#FFD4D4D8') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text         = $text
    $t.FontFamily   = 'Segoe UI'
    $t.FontSize     = $size
    $t.Foreground   = New-Brush $color
    $t.TextWrapping = 'Wrap'
    return $t
}

function New-PanelLink([string]$text, [string]$color, $tag, $onClick) {
    $t = New-PanelText $text 10 $color
    $t.Cursor     = [System.Windows.Input.Cursors]::Hand
    $t.Background = [System.Windows.Media.Brushes]::Transparent
    $t.Margin     = New-Object System.Windows.Thickness 0, 0, 12, 0
    $t.Tag        = $tag
    $t.add_MouseLeftButtonDown($onClick)
    return $t
}

# A message's text with its links clickable: a bare http(s) address or a markdown
# [text](url); a click opens it in the browser.
$ChatLinkRx = [regex]'\[([^\]\r\n]+)\]\((https?://[^\s)]+)\)|https?://[^\s<>"''`\[\]]+'
function New-ListChip([string]$text, [bool]$on, $tag, $onClick) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius 9
    $b.Padding      = New-Object System.Windows.Thickness 8, 2, 8, 3
    $b.Margin       = New-Object System.Windows.Thickness 0, 0, 5, 4
    $b.Background   = New-Brush $(if ($on) { '#FF2B3245' } else { '#FF26262C' })
    $b.Cursor       = [System.Windows.Input.Cursors]::Hand
    $b.Tag          = $tag
    $b.Child        = New-PanelText $text 10 $(if ($on) { '#FFF4F4F5' } else { '#FF8B8B94' })
    $b.add_MouseLeftButtonDown($onClick)
    return $b
}

function New-SetHeader([string]$text) {
    $t = New-PanelText $text.ToUpper() 9 '#FF6B7280'
    $t.FontWeight = 'SemiBold'
    $t.Margin = New-Object System.Windows.Thickness 0, 6, 0, 5
    return $t
}

function New-SetRow {
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness 0, 0, 0, 7
    $row.Background = [System.Windows.Media.Brushes]::Transparent
    $c = New-Object System.Windows.Controls.ColumnDefinition; $row.ColumnDefinitions.Add($c)
    $c = New-Object System.Windows.Controls.ColumnDefinition; $c.Width = 'Auto'; $row.ColumnDefinitions.Add($c)
    return $row
}

# A switch; the whole row is clickable, $tag goes to $onClick as $s.Tag.
function New-SetSwitch([string]$label, [bool]$on, [string]$tip, $tag, $onClick) {
    $row = New-SetRow
    $row.Cursor = [System.Windows.Input.Cursors]::Hand
    $row.Tag = $tag
    if ($tip) { $row.ToolTip = $tip }
    $t = New-PanelText $label 10.5 $(if ($on) { '#FFE4E4E7' } else { '#FFA1A1AA' })
    $t.VerticalAlignment = 'Center'
    $t.Margin = New-Object System.Windows.Thickness 0, 0, 10, 0
    [void]$row.Children.Add($t)
    $sw = New-Object System.Windows.Controls.Border
    $sw.Width = 24; $sw.Height = 13
    $sw.CornerRadius = New-Object System.Windows.CornerRadius 6.5
    $sw.Background = New-Brush $(if ($on) { '#FF60A5FA' } else { '#FF3F3F46' })
    $sw.VerticalAlignment = 'Center'
    $knob = New-Object System.Windows.Shapes.Ellipse
    $knob.Width = 9; $knob.Height = 9
    $knob.Fill = New-Brush '#FFF4F4F5'
    $knob.Margin = New-Object System.Windows.Thickness 2, 0, 2, 0
    $knob.HorizontalAlignment = $(if ($on) { 'Right' } else { 'Left' })
    $sw.Child = $knob
    [System.Windows.Controls.Grid]::SetColumn($sw, 1)
    [void]$row.Children.Add($sw)
    $row.add_MouseLeftButtonDown($onClick)
    return $row
}

# A switch for a yes/no key of config.json.
function New-SetToggle([string]$key, [string]$label, [string]$tip = '') {
    return New-SetSwitch $label ([bool]$script:Cfg[$key]) $tip $key {
        param($s, $e)
        $e.Handled = $true
        Set-Setting $s.Tag (-not [bool]$script:Cfg[$s.Tag])
    }
}

# "Size   -  135%  +": the value between two buttons.
function New-SetStepper([string]$label, [string]$value, $onMinus, $onPlus) {
    $row = New-SetRow
    $t = New-PanelText $label 10.5 '#FFE4E4E7'
    $t.VerticalAlignment = 'Center'
    [void]$row.Children.Add($t)
    $box = New-Object System.Windows.Controls.StackPanel
    $box.Orientation = 'Horizontal'
    [System.Windows.Controls.Grid]::SetColumn($box, 1)
    foreach ($part in @(@([string][char]0x2212, $onMinus), @($value, $null), @('+', $onPlus))) {
        $b = New-PanelText $part[0] $(if ($part[1]) { 13 } else { 10.5 }) $(if ($part[1]) { '#FF8B8B94' } else { '#FFE4E4E7' })
        $b.VerticalAlignment = 'Center'
        $b.TextAlignment = 'Center'
        if ($part[1]) {
            $b.Padding = New-Object System.Windows.Thickness 7, 0, 7, 1
            $b.Cursor = [System.Windows.Input.Cursors]::Hand
            $b.Background = [System.Windows.Media.Brushes]::Transparent
            $b.add_MouseLeftButtonDown($part[1])
        } else {
            $b.MinWidth = 36
        }
        [void]$box.Children.Add($b)
    }
    [void]$row.Children.Add($box)
    return $row
}

function New-SetLink([string]$text, $onClick) {
    $l = New-PanelLink $text '#FF60A5FA' $null $onClick
    $l.Margin = New-Object System.Windows.Thickness 0, -2, 0, 8
    return $l
}

# A theme chip with a swatch: the theme's background with its accent in the middle.
function New-ThemeChip([string]$id) {
    $on = ($id -eq ([string]$script:Cfg.theme).ToLower())
    $look = $(if ($id -eq 'auto') { Get-SeasonThemeId } else { $id })
    $t = $Themes[$look]
    $chip = New-ListChip '' $on $id {
        param($s, $e)
        $e.Handled = $true
        Set-Setting 'theme' $s.Tag
    }
    $sw = New-Object System.Windows.Controls.Border
    $sw.Width = 12; $sw.Height = 12
    $sw.CornerRadius = New-Object System.Windows.CornerRadius 6
    $sw.BorderThickness = New-Object System.Windows.Thickness 1
    $sw.BorderBrush = New-SkinBrush '#40FFFFFF'
    $sw.Background = New-SkinBrush $(if ($t.ContainsKey('bg')) { $t.bg } else { $ThemeBase.bg })
    $sw.VerticalAlignment = 'Center'
    $sw.Margin = New-Object System.Windows.Thickness 0, 1, 5, 0
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 5; $dot.Height = 5
    $dot.Fill = New-SkinBrush $(if ($t.ContainsKey('accent')) { $t.accent } else { $ThemeBase.accent })
    $sw.Child = $dot
    $box = New-Object System.Windows.Controls.StackPanel
    $box.Orientation = 'Horizontal'
    [void]$box.Children.Add($sw)
    [void]$box.Children.Add((New-PanelText (T "theme.$id") 10 $(if ($on) { '#FFF4F4F5' } else { '#FF8B8B94' })))
    $chip.Child = $box
    $script:SettingsThemes[$id]=$chip
    return $chip
}

# Clawd in a skin, for its card: Get-MascotGeo draws the accessories of $script:Skin.
function Get-SkinPreviewGeo($skin, [string]$pose) {
    $keep = $script:Skin
    $script:Skin = $skin
    try {
        $f = (New-ClawdFrames $pose)[0].Clone()
        $f.look = 0; $f.flip = $false; $f.dig = 0; $f.spray = 0
        return Get-MascotGeo $f
    } finally { $script:Skin = $keep }
}

function Set-SkinCardPose($card, [string]$pose) {
    $c = $card.Tag
    $g = Get-SkinPreviewGeo $c.skin $pose
    $c.body.Data = $g.body
    $c.eyes.Data = $g.eyes
    for ($i = 0; $i -lt $c.acc.Count; $i++) { $c.acc[$i].Data = $g.acc[$i] }
}

function New-SkinCardBox([bool]$on) {
    $card = New-Object System.Windows.Controls.Border
    $card.Width = 68
    $card.CornerRadius = New-Object System.Windows.CornerRadius 7
    $card.Padding = New-Object System.Windows.Thickness 2, 7, 2, 5
    $card.Margin = New-Object System.Windows.Thickness 0, 0, 5, 5
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.Background = New-Brush $(if ($on) { '#FF2B3245' } else { '#FF26262C' })
    $card.BorderBrush = New-Brush $(if ($on) { '#FF60A5FA' } else { '#1AFFFFFF' })
    $card.Cursor = [System.Windows.Input.Cursors]::Hand
    return $card
}

function New-SkinCardName([string]$text, [bool]$on) {
    $n = New-PanelText $text 9.5 $(if ($on) { '#FFF4F4F5' } else { '#FF8B8B94' })
    # Two lines at most, the same height in every card: the rows stay even.
    $n.TextTrimming = 'CharacterEllipsis'
    $n.Height = 26
    $n.TextAlignment = 'Center'
    $n.Margin = New-Object System.Windows.Thickness 2, 4, 2, 0
    return $n
}

# A skin's card: Clawd in it, raising his arms under the mouse; a click puts it on.
# $top - rows above his head, the same for all cards so that they line up.
function New-SkinCard($skin, [int]$top) {
    $on = ($skin.id -eq $script:Skin.id)
    $card = New-SkinCardBox $on
    $card.ToolTip = Get-SkinName $skin
    $cv = New-Object System.Windows.Controls.Canvas
    $cv.Width = $MascotW
    $cv.Height = (4 * $ClawdRows - 2 + $top) * $MascotPy
    $cv.HorizontalAlignment = 'Center'
    $cv.LayoutTransform = New-Object System.Windows.Media.ScaleTransform 1.4, 1.4
    $shift = New-Object System.Windows.Media.TranslateTransform 0, ($top * $MascotPy)
    $mk = {
        param([string]$hex)
        $p = New-Object System.Windows.Shapes.Path
        $p.Fill = New-SkinBrush $hex
        $p.RenderTransform = $shift
        $p.IsHitTestVisible = $false
        [void]$cv.Children.Add($p)
        $p
    }
    $tag = @{ skin = $skin; body = (& $mk $skin.body); eyes = (& $mk $skin.eyes); acc = @() }
    foreach ($l in $skin.layers) { $tag.acc += (& $mk $l.color) }
    $card.Tag = $tag
    $box = New-Object System.Windows.Controls.StackPanel
    [void]$box.Children.Add($cv)
    [void]$box.Children.Add((New-SkinCardName (Get-SkinName $skin) $on))
    $card.Child = $box
    Set-SkinCardPose $card 'default'
    $card.add_MouseEnter({ param($s, $e) Set-SkinCardPose $s 'arms-up' })
    $card.add_MouseLeave({ param($s, $e) Set-SkinCardPose $s 'default' })
    $card.add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        Set-Setting 'skin' $s.Tag.skin.id
    })
    return $card
}

function Add-SetLookPage($p) {
    [void]$p.Children.Add((New-SetHeader (T 'set.language')))
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($code in $Languages.Keys) {
        [void]$wrap.Children.Add((New-ListChip $Languages[$code] ($code -eq (Get-Lang)) $code {
            param($s, $e)
            $e.Handled = $true
            Set-Setting 'language' $s.Tag
        }))
    }
    [void]$p.Children.Add($wrap)

    [void]$p.Children.Add((New-SetHeader (T 'set.theme')))
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($id in @('auto') + @($Themes.Keys)) { [void]$wrap.Children.Add((New-ThemeChip $id)) }
    [void]$p.Children.Add($wrap)

    [void]$p.Children.Add((New-SetHeader (T 'set.skin')))
    # Drawn anew: a skin file may have changed since its last preview.
    $script:MascotGeo = @{}
    $script:Mz.key = $null
    $all = Get-Skins
    $top = 0
    foreach ($s in $all.Values) {
        foreach ($l in $s.layers) { foreach ($pt in $l.px) { if (-[int]$pt[1] -gt $top) { $top = -[int]$pt[1] } } }
    }
    $wrap = New-Object System.Windows.Controls.WrapPanel
    foreach ($s in $all.Values) { [void]$wrap.Children.Add((New-SkinCard $s ([math]::Min($top, 12)))) }
    # The last card opens the folder for your own skins.
    $more = New-SkinCardBox $false
    $more.ToolTip = T 'set.skinFolderTip'
    $box = New-Object System.Windows.Controls.StackPanel
    $box.VerticalAlignment = 'Center'
    $plus = New-PanelText '+' 22 '#FF6B7280'
    $plus.TextAlignment = 'Center'
    [void]$box.Children.Add($plus)
    [void]$box.Children.Add((New-SkinCardName (T 'set.skinFolder') $false))
    $more.Child = $box
    $more.add_MouseLeftButtonDown({
        param($s, $e)
        $e.Handled = $true
        $dir = Join-Path $script:Root 'assets\skins'
        [void][System.IO.Directory]::CreateDirectory($dir)
        Start-Process explorer.exe "`"$dir`""
    })
    [void]$wrap.Children.Add($more)
    [void]$p.Children.Add($wrap)
}
