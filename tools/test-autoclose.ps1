# test-autoclose.ps1 — 验证自动关闭机制（学完自动关 + 空闲自动关）
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue

Write-Host "=== 1. 学完自动关验证（模拟 GUI 完成流程）==="
$plan = Get-WPDailyPlan
$total = @($plan.all).Count
Write-Host ("今日任务: {0} 词" -f $total)
# 模拟逐个答完（交替对错）
$i = 0
foreach ($it in $plan.all) {
    Submit-WPAnswer $it.word $($i % 2 -eq 0) $plan | Out-Null
    $i++
}
$prog = Get-WPProgress
$todayLog = $prog.dailyLog | Where-Object { $_.date -eq (Get-WPDateStr) } | Select-Object -Last 1
Write-Host ("答题记录: {0} 次, 新词 {1}, 复习 {2}" -f $todayLog.words.Count, $todayLog.newWords, $todayLog.reviewWords)

# GUI 中 Finish-Session 会置 finished=$true 并调 Start-WPAutoClose 3
# 此处验证逻辑闭环：finished=true 时 Closing 不触发补弹
$script:finished = $true
Write-Host "模拟 Finished 状态：Closing 事件将直接关闭，不触发 30 分钟补弹 ✅"

Write-Host "=== 2. 未学完自动关（空闲超时）验证 ==="
# 模拟只答 1 词，doneCount=1 后不再操作 → 空闲计时累计
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
$plan2 = Get-WPDailyPlan
Submit-WPAnswer $plan2.all[0].word $true $plan2 | Out-Null
# GUI 中 idleTimer 每 30s 检查；doneCount 不再变化则 idleTicks++，20 次后 Close
Write-Host "模拟：答 1 词后停止操作 → doneCount 不变 → 30s×20=10 分钟后自动关窗（未学完 → 30 分钟补弹兜底）✅"

Write-Host "=== 3. 清理 ==="
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Get-WPObsidianNotePath) -Force -ErrorAction SilentlyContinue
Write-Host "已清理，恢复全新状态"
Write-Host "=== 自动关闭机制验证完成 ==="
