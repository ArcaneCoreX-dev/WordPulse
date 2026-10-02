# smoke-test.ps1  WordPulse 核心引擎冒烟测试
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

Write-Host "=== 1. 词库加载 ==="
$books = Get-WPBooks
foreach ($lv in $script:WP_BookLevels) {
    $b = $books[$lv]
    if ($b) {
        Write-Host ("[{0}] {1} 词" -f $b.meta.levelName, $b.meta.count)
    } else {
        Write-Host "[$lv] 加载失败"
    }
}

Write-Host "=== 2. 每日计划 ==="
$plan = Get-WPDailyPlan
Write-Host ("级别: {0} | 新词 {1} | 复习 {2} | 今日 {3}" -f $plan.levelName, $plan.newWords.Count, $plan.reviewWords.Count, $plan.today)
Write-Host ("新词列表: {0}" -f (($plan.newWords | ForEach-Object { $_.word }) -join ", "))
Write-Host ("复习列表: {0}" -f (($plan.reviewWords | ForEach-Object { $_.word }) -join ", "))

Write-Host "=== 3. 答题记录 + 打卡 ==="
$word1 = $plan.newWords[0].word
$prog = Submit-WPAnswer $word1 $true $plan
Write-Host ("答对 [{0}] 后：streak={1} lastStudy={2}" -f $word1, $prog.streak, $prog.lastStudyDate)

$word2 = $plan.newWords[1].word
$prog = Submit-WPAnswer $word2 $false $plan
Write-Host ("答错 [{0}] 后：streak={1}" -f $word2, $prog.streak)

Write-Host "=== 4. 进度摘要 ==="
$summary = Get-WPTodaySummary $plan
Write-Host ("streak={0} done={1}/{2} 新词={3} 复习={4}" -f $summary.streak, $summary.done, $summary.total, $summary.newCount, $summary.reviewCount)

Write-Host "=== 5. SM-2 状态验证 ==="
$st = $prog.words.$word1
Write-Host ("[{0}] level={1} interval={2} reps={3} due={4} lastResult={5}" -f $word1, $st.level, $st.interval, $st.reps, $st.due, $st.lastResult)
$st2 = $prog.words.$word2
Write-Host ("[{0}] level={1} interval={2} lapses={3} lastResult={4}" -f $word2, $st2.level, $st2.interval, $st2.lapses, $st2.lastResult)

Write-Host "=== 6. 词条详情 ==="
$entry = Get-WPEntry $word1 $plan
Write-Host ("[{0}] 音标={1} 释义={2}" -f $entry.word, $entry.phoneticUs, $entry.meaning)
Write-Host ("例句1: {0} -> {1}" -f $entry.examples[0].en, $entry.examples[0].cn)

Write-Host "=== 冒烟测试完成 ==="
