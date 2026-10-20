#requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$parseCount=0
foreach ($file in @(Get-ChildItem (Join-Path $project 'src') -Recurse -Filter *.ps1)+@(Get-ChildItem (Join-Path $project 'tools') -Filter *.ps1)+@(Get-Item (Join-Path $project 'widget.ps1'))) {
    $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$errors)
    if ($errors) { throw "$($file.FullName): $errors" }
    if ([IO.File]::ReadAllBytes($file.FullName)[0] -ne 239) { throw "Missing UTF-8 BOM: $($file.Name)" }
    $parseCount++
}
"PASS: $parseCount PowerShell files parse"
& (Join-Path $PSScriptRoot 'test-data.ps1')
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-scale.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Scale regression test failed' }
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('codex-widget-smoke-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$oldTestData=$env:CODEX_WIDGET_TEST_DATA
$env:CODEX_WIDGET_TEST_DATA=$testRoot
try {
    # Isolate persistence from a real widget that may refresh while tests run.
    $config=Join-Path $testRoot 'config.json'
    $history=Join-Path $testRoot 'usage-history.json'
    [IO.File]::WriteAllText($config,'{"scale":1.35,"language":"ru"}')
    [IO.File]::WriteAllText($history,'[]')
    $before=@{}
    foreach ($p in @($config,$history)) { $before[$p]=(Get-FileHash $p).Hash }
    foreach ($theme in @('classic','space','ocean','halloween','cyberpunk')) {
        $png=Join-Path $project "docs\preview-$theme.png"
        & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $project 'widget.ps1') -SmokeTest -Theme $theme -Screenshot $png
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $png)) { throw "Smoke failed: $theme" }
        "PASS: $theme, settings, skins and moods"
    }
    foreach ($p in @($config,$history)) {
        if ((Get-FileHash $p).Hash -ne $before[$p]) { throw "Preview changed persistent data: $p" }
    }
    'PASS: previews did not change config or history'
    if (Test-Path (Join-Path $testRoot 'widget-error.log')) { throw 'Errors were logged during smoke tests' }
    'PASS: no UI or timer errors were logged'
} finally {
    $env:CODEX_WIDGET_TEST_DATA=$oldTestData
    foreach ($p in @(Get-ChildItem -LiteralPath $testRoot -File)) { [IO.File]::Delete($p.FullName) }
    [IO.Directory]::Delete($testRoot)
}
