# diag2.ps1 — 精确复现 test-v2 场景，dump 中间状态定位 12 行之谜
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue

Write-Host "=== 初始计划 ==="
$plan1 = Get-WPDailyPlan
Write-Host ("newWords 前5: {0}" -f (($plan1.newWords | Select-Object -First 5 | ForEach-Object { $_.word }) -join ','))
Write-Host ("reviewWords: {0}" -f (($plan1.reviewWords | ForEach-Object { $_.word }) -join ','))

$w1 = $plan1.newWords[0].word
$w2 = $plan1.newWords[1].word
Write-Host ("w1={0} w2={1}" -f $w1, $w2)

Submit-WPAnswer $w1 $true $plan1 | Out-Null
Write-Host "--- 答完 w1 后 dailyLog ---"
$p = Get-WPProgress
Write-Host ("dailyLog.Count={0} words明细={1}" -f $p.dailyLog.Count, $p.dailyLog[0].words.Count)

Submit-WPAnswer $w2 $false $plan1 | Out-Null
Write-Host "--- 答完 w2 后 dailyLog ---"
$p = Get-WPProgress
Write-Host ("dailyLog.Count={0} words明细={1}" -f $p.dailyLog.Count, $p.dailyLog[0].words.Count)
$p.dailyLog[0].words | ForEach-Object { Write-Host ("   {0}/{1}/{2}" -f $_.word, $_.kind, $_.result) }

# 改 due 为今天
$p = Get-WPProgress
$p.words.$w1.due = (Get-WPDateStr)
$p.words.$w2.due = (Get-WPDateStr)
Save-WPProgress $p
Write-Host "--- 改 due 后（未答题） ---"
$p2 = Get-WPProgress
Write-Host ("dailyLog.Count={0} words明细={1}" -f $p2.dailyLog.Count, $p2.dailyLog[0].words.Count)

$plan2 = Get-WPDailyPlan
Write-Host ("plan2: 新词 {0} 复习 {1}" -f $plan2.newWords.Count, $plan2.reviewWords.Count)

Write-Host "=== 手动 Export 后看文件 ==="
$np = Export-WPDailyNote
$c = [IO.File]::ReadAllText($np, [Text.Encoding]::UTF8)
$rows = @($c -split "`r?`n" | Where-Object { $_ -match '^\| ' -and $_ -notmatch '^\| 单词' -and $_ -notmatch '^\|--' })
Write-Host ("表格行数: {0}" -f $rows.Count)
$c -split "`r?`n" | Select-Object -First 8

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item $np -Force -ErrorAction SilentlyContinue
Write-Host "已清理"
