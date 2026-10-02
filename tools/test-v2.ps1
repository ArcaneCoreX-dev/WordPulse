# test-v2.ps1 — WordPulse v2 回归测试：判分修复 + Obsidian 导出
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

# 清理旧状态，保证可重复
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Get-WPObsidianNotePath) -Force -ErrorAction SilentlyContinue

Write-Host "=== 1. 复习词判分修复验证 ==="
# 模拟：新词答对 -> 变成复习词（due 明天，但强制改 due 到今天来制造复习场景）
$plan1 = Get-WPDailyPlan
$w1 = $plan1.newWords[0].word
Submit-WPAnswer $w1 $true $plan1 | Out-Null
$w2 = $plan1.newWords[1].word
Submit-WPAnswer $w2 $false $plan1 | Out-Null

# 把 w1/w2 的 due 改成今天，模拟次日复习
$prog = Get-WPProgress
$prog.words.$w1.due = (Get-WPDateStr)
$prog.words.$w2.due = (Get-WPDateStr)
Save-WPProgress $prog

$plan2 = Get-WPDailyPlan
$reviewHits = @($plan2.reviewWords | Where-Object { $_.word -in @($w1, $w2) })
Write-Host ("复习队列应包含 $w1 和 $w2：实际 {0}" -f (($reviewHits | ForEach-Object { $_.word }) -join ','))
foreach ($r in $reviewHits) {
    $entry = Get-WPEntry $r.word $plan2
    $meaning = $entry.meaning
    $hasMeaning = (-not [string]::IsNullOrWhiteSpace($meaning))
    Write-Host ("  [{0}] entry解析: 有释义={1} 释义='{2}'" -f $r.word, $hasMeaning, $meaning)
}

Write-Host "=== 2. Obsidian 每日记录导出验证 ==="
$notePath = Get-WPObsidianNotePath
Write-Host ("目标文件: {0}" -f $notePath)
Write-Host ("文件存在: {0}" -f (Test-Path $notePath))
if (Test-Path $notePath) {
    $content = [IO.File]::ReadAllText($notePath, [Text.Encoding]::UTF8)
    Write-Host ("--- 文件内容预览（前 30 行）---")
    ($content -split "`r?`n") | Select-Object -First 30
}

Write-Host "=== 3. 清理测试数据 ==="
# 还原干净状态：删除 progress 与测试笔记（保留目录）
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item $notePath -Force -ErrorAction SilentlyContinue
Write-Host "已清理测试进度与测试笔记，恢复全新状态"
Write-Host "=== 回归测试完成 ==="
