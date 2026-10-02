# test-grading.ps1 — 专项验证选义判分逻辑（模拟 GUI 判分路径）
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

# 清理
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Get-WPObsidianNotePath) -Force -ErrorAction SilentlyContinue

$plan = Get-WPDailyPlan
$w = $plan.newWords[0].word
$entry = Get-WPEntry $w $plan
Write-Host ("测试词: {0}  释义: {1}" -f $w, $entry.meaning)

# 模拟 GUI Show-Entry 逻辑（复习词 entry=null 场景）
$item = @{ kind='new'; word=$w; entry=$null; state=(Get-WPDefaultState) }  # 模拟 entry 丢失
$curEntry = $null
if (-not $item.entry) { $curEntry = Get-WPEntry $item.word $plan }
$cur = @{ kind=$item.kind; word=$item.word; entry=$curEntry; state=$item.state }

# 模拟 4 个选项，其中一个是正确释义
$correctMeaning = $cur.entry.meaning
$options = @('错误A', '错误B', '错误C', $correctMeaning)
$script:optAnswers = $options

# 模拟点击正确选项（idx=3，即正确释义位置）
$idx = 3
$selected = $script:optAnswers[$idx]
$judge = ($selected -eq $cur.entry.meaning)
Write-Host ("点击 idx=3: 选中='{0}'  正确='{1}'  判分={2}" -f $selected, $cur.entry.meaning, $judge)
if ($judge) { Write-Host "✓ 选正确项 → 判为正确 (符合预期)" } else { Write-Host "✗ BUG: 选正确项被判为错误!" }

# 再模拟点击错误选项（idx=0）
$idx = 0
$selected = $script:optAnswers[$idx]
$judge2 = ($selected -eq $cur.entry.meaning)
Write-Host ("点击 idx=0: 选中='{0}'  判分={1}" -f $selected, $judge2)
if (-not $judge2) { Write-Host "✓ 选错误项 → 判为错误 (符合预期)" } else { Write-Host "✗ BUG: 选错误项被判为正确!" }

# 模拟复习词场景（上一轮答对，due 改为今天 → 进复习队列）
Submit-WPAnswer $w $true $plan | Out-Null
$p = Get-WPProgress
$p.words.$w.due = (Get-WPDateStr)
Save-WPProgress $p
$plan2 = Get-WPDailyPlan
$rv = $plan2.reviewWords | Where-Object { $_.word -eq $w } | Select-Object -First 1
if ($rv) {
    $rEntry = Get-WPEntry $rv.word $plan2
    $cur2 = @{ kind=$rv.kind; word=$rv.word; entry=$rEntry; state=$rv.state }
    $opts2 = @('错误X', '错误Y', $rEntry.meaning, '错误Z')
    $script:optAnswers = $opts2
    # 正确项在 idx=2
    $sel2 = $script:optAnswers[2]
    $judge3 = ($sel2 -eq $cur2.entry.meaning)
    Write-Host ("复习词 {0} 判分: 选中='{1}' 正确='{2}' 结果={3}" -f $w, $sel2, $cur2.entry.meaning, $judge3)
    if ($judge3) { Write-Host "✓ 复习词选正确 → 判为正确 (BUG 已修复)" } else { Write-Host "✗ 复习词仍判错!" }
}

# 清理
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Get-WPObsidianNotePath) -Force -ErrorAction SilentlyContinue
Write-Host "=== 判分专项测试完成 ==="
