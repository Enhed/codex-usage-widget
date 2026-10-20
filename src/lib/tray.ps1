$notify=New-Object Windows.Forms.NotifyIcon
$notify.Text='Codex usage'; $notify.Visible=-not $script:Preview
$script:LastIconHandle=[IntPtr]::Zero
$script:IconKey=''
function Set-TrayIcon([string]$text,[Drawing.Color]$color) {
    $key="$text|$($color.ToArgb())"
    if ($key -eq $script:IconKey) { return }; $script:IconKey=$key
    $bmp=New-Object Drawing.Bitmap 32,32
    $g=[Drawing.Graphics]::FromImage($bmp)
    $brush=New-Object Drawing.SolidBrush $color
    $font=New-Object Drawing.Font 'Segoe UI',15,([Drawing.FontStyle]::Bold),([Drawing.GraphicsUnit]::Pixel)
    $fmt=New-Object Drawing.StringFormat; $fmt.Alignment='Center'; $fmt.LineAlignment='Center'
    try {
        $g.SmoothingMode='AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
        $g.FillEllipse($brush,0,0,31,31)
        $g.DrawString($text,$font,[Drawing.Brushes]::Black,([Drawing.RectangleF]::new(0,0,32,32)),$fmt)
        $handle=$bmp.GetHicon(); $old=$notify.Icon
        $notify.Icon=[Drawing.Icon]::FromHandle($handle).Clone()
        [void][Win32.IconUtil]::DestroyIcon($handle)
        if ($old) { $old.Dispose() }
    } finally { $g.Dispose(); $bmp.Dispose(); $brush.Dispose(); $font.Dispose(); $fmt.Dispose() }
}
function Build-TrayMenu {
    $old=$notify.ContextMenuStrip
    $menu=New-Object Windows.Forms.ContextMenuStrip
    foreach ($spec in @(
        @((L 'Показать / скрыть' 'Show / hide'),'toggle'),
        @((L 'Обновить' 'Refresh'),'refresh'),
        @((L 'Настройки' 'Settings'),'settings'),
        @((L 'Выход' 'Exit'),'exit')
    )) {
        $item=$menu.Items.Add($spec[0]); $item.Tag=$spec[1]
        $item.Add_Click({ param($s,$e)
            switch ($s.Tag) {
                toggle { Toggle-Window }
                refresh { $script:NextRefresh=[datetime]::MinValue }
                settings { $win.Show(); $win.Activate() | Out-Null; Show-Settings }
                exit { $win.Close() }
            }
        })
    }
    $notify.ContextMenuStrip=$menu
    if ($old) { $old.Dispose() }
}
function Toggle-Window { if ($win.IsVisible) { $win.Hide() } else { $win.Show(); $win.Activate() | Out-Null } }
$notify.Add_DoubleClick({ Toggle-Window })
Set-TrayIcon '--' ([Drawing.Color]::FromArgb(116,215,186))
