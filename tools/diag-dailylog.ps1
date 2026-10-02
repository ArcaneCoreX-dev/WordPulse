# diag-dailylog.ps1 — 诊断 dailyLog 数据完整性
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

# 清理后重建
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue

$plan = Get-WPDailyPlan
Write-Host ("计划: 新词 {0} 复习 {1}" -f $plan.newWords.Count, $plan.reviewWords.Count)
$w1 = $plan.newWords[0].word
$w2 = $plan.newWords[1].word
Write-Host ("答题: {0} (对), {1} (错)" -f $w1, $w2)
Submit-WPAnswer $w1 $true $plan | Out-Null
Submit-WPAnswer $w2 $false $plan | Out-Null

$prog = Get-WPProgress
Write-Host ("dailyLog 条数: {0}" -f $prog.dailyLog.Count)
Write-Host ("今日记录: date={0} newWords={1} reviewWords={2} correctNew={3} correctReview={4}" -f $prog.dailyLog[0].date, $prog.dailyLog[0].newWords, $prog.dailyLog[0].reviewWords, $prog.dailyLog[0].correctNew, $prog.dailyLog[0].correctReview)
Write-Host ("今日 words 明细数: {0}" -f $prog.dailyLog[0].words.Count)
$prog.dailyLog[0].words | ForEach-Object { Write-Host ("  - {0} ({1}) {2}" -f $_.word, $_.kind, $_.result) }

# 检查笔记文件
$np = Get-WPObsidianNotePath
if (Test-Path $np) {
    $c = [IO.File]::ReadAllText($np, [Text.Encoding]::UTF8)
    $tableRows = @($c -split "`r?`n" | Where-Object { $_ -match '^\| ' -and $_ -notmatch '^\| 单词' -and $_ -notmatch '^\|--' })
    Write-Host ("笔记表格数据行数: {0}" -f $tableRows.Count)
}

# 清理
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item $np -Force -ErrorAction SilentlyContinue
Write-Host "已清理，恢复全新状态"
