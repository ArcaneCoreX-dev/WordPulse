# test-article.ps1 — 验证语境文章生成质量
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue

$plan = Get-WPDailyPlan
Write-Host ("今日词条数: {0}" -f @($plan.all).Count)

# 抽取 New-WPArticle 逻辑做独立验证（与 GUI 同逻辑，模拟）
foreach ($w in @($plan.all | Select-Object -First 3)) {
    $e = $w.entry
    if (-not $e) { $e = Get-WPEntry $w.word $plan }
    $word = $e.word
    $title = 'The Story of "' + $word + '"'
    $meaning = $e.meaning
    $meaningEn = $e.meaningEn
    $lead = if ($meaningEn) { '"' + $word + '" is a word worth knowing. In plain terms, it means: ' + $meaningEn.TrimEnd('.') + '.' } else { '"' + $word + '" is a word worth knowing. It means: ' + $meaning + '.' }
    Write-Host ""
    Write-Host "===== $title ====="
    Write-Host $lead
    $cnt = 0
    foreach ($s in $e.examples) {
        if ($cnt -ge 3) { break }
        if ($s.en) { Write-Host ("  • " + $s.en); if ($s.cn) { Write-Host ("    " + $s.cn) } }
        $cnt++
    }
    if ($cnt -eq 0) { Write-Host "  • (无例句，使用占位语境)" }
    if ($e.phrases.Count -gt 0) {
        Write-Host "  搭配: " + (($e.phrases | Select-Object -First 2 | ForEach-Object { $_.en }) -join " / ")
    }
    Write-Host ("  收尾: Now you have met `"{0}`" in real context..." -f $word)
}

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "=== 文章生成验证完成 ==="
