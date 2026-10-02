# rebuild-note.ps1 — 重建 2026-10-01 学习记录（修复误删 + 按新逻辑修正一致性）
# 数据源：①词库 wordbook_primary.json ②之前检查时捕获的训练记录明细
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

$today = '2026-10-01'
$lv = 'primary'
$lvName = '小学'

# 实际所学 10 词 + 训练明细（来自旧文档训练记录表）
$studyLog = @(
    @{ word='ruler';      mode='选义'; question='请选择「ruler」的正确释义：A. 橡皮  B. 书  C. 尺子  D. 蓝色；蓝色的'; input='（旧版未记录）'; result='correct' },
    @{ word='pencil';     mode='拼写'; question='根据释义拼写出单词：铅笔'; input='pencil'; result='correct' },
    @{ word='eraser';     mode='填空'; question='看例句填空：Press to bring up the ______ tool, orfind it in your Toolbox.'; input='eraser'; result='correct' },
    @{ word='crayon';     mode='选义'; question='请选择「crayon」的正确释义：A. 蜡笔  B. 老虎  C. 眼睛  D. 橙色；橙色的'; input='（旧版未记录）'; result='correct' },
    @{ word='bag';        mode='拼写'; question='根据释义拼写出单词：包'; input='bag'; result='correct' },
    @{ word='pen';        mode='填空'; question='看例句填空：a ballpoint ______'; input='pen'; result='correct' },
    @{ word='pencil box'; mode='选义'; question='请选择「pencil box」的正确释义：A. 六  B. 蜡笔  C. 铅笔盒  D. 铅笔'; input='（旧版未记录）'; result='correct' },
    @{ word='book';       mode='拼写'; question='根据释义拼写出单词：书'; input='book'; result='correct' },
    @{ word='no';         mode='填空'; question='看例句填空：''Are you Italian?'' ''______, I''m Spanish.'''; input='no'; result='correct' },
    @{ word='your';       mode='选义'; question='请选择「your」的正确释义：A. 七  B. 你（们）的  C. 蓝色；蓝色的  D. 书'; input='（旧版未记录）'; result='correct' }
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# 每日英语学习 · $today")
[void]$sb.AppendLine()
[void]$sb.AppendLine("- 学习级别：$lvName")
[void]$sb.AppendLine("- 连续打卡：1 天")
[void]$sb.AppendLine("- 今日新词：10 个 / 答对 10")
[void]$sb.AppendLine("- 今日复习：0 个 / 答对 0")
[void]$sb.AppendLine("- 答题总数：10 次")
[void]$sb.AppendLine()
[void]$sb.AppendLine("---")
[void]$sb.AppendLine()

# ① 今日单词 + 例句 + 语境文章（实际所学 10 词）
[void]$sb.AppendLine("## 一、今日单词 · 例句 · 语境文章")
[void]$sb.AppendLine()
$idx = 1
foreach ($rec in $studyLog) {
    $w = $rec.word
    $entry = Get-WPEntry $w @{ level = $lv }
    $phon = if ($entry.phoneticUs) { ('/' + $entry.phoneticUs + '/') } else { '' }
    [void]$sb.AppendLine("### $idx. **$w** 🆕  $phon — $($entry.meaning)")
    [void]$sb.AppendLine()

    # 语境文章
    $art = New-WPArticle $entry
    [void]$sb.AppendLine("> **$($art.title)**")
    [void]$sb.AppendLine(">")
    [void]$sb.AppendLine("> $($art.lead)")
    foreach ($p in $art.paras) {
        [void]$sb.AppendLine("> - $($p.en)")
        if ($p.cn) { [void]$sb.AppendLine(">   $($p.cn)") }
    }
    if ($art.phrases.Count -gt 0) {
        $phStr = ($art.phrases | ForEach-Object { $_.en + $(if ($_.cn) { '（' + $_.cn + '）' } else { '' }) }) -join ' / '
        [void]$sb.AppendLine("> - 搭配：$phStr")
    }
    [void]$sb.AppendLine(">")
    [void]$sb.AppendLine("> $($art.outro)")
    [void]$sb.AppendLine()

    # 例句
    if ($entry.examples.Count -gt 0) {
        [void]$sb.AppendLine("例句：")
        foreach ($s in $entry.examples) {
            if ($s.en) {
                [void]$sb.AppendLine("- 「$($s.en)」")
                if ($s.cn) { [void]$sb.AppendLine("　　$($s.cn)") }
            }
        }
    }
    [void]$sb.AppendLine()
    $idx++
}
[void]$sb.AppendLine("---")
[void]$sb.AppendLine()

# ② 训练记录
[void]$sb.AppendLine("## 二、训练记录")
[void]$sb.AppendLine()
[void]$sb.AppendLine("| # | 单词 | 题型 | 题目 | 我的答案 | 判定 |")
[void]$sb.AppendLine("|---|------|------|------|---------|------|")
$qi = 1
foreach ($rec in $studyLog) {
    $q = $rec.question.Replace('|', '\|')
    $ans = $rec.input.Replace('|', '\|')
    $res = if ($rec.result -eq 'correct') { '✅ 对' } else { '❌ 错' }
    [void]$sb.AppendLine("| $qi | $($rec.word) | $($rec.mode) | $q | $ans | $res |")
    $qi++
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("---")
[void]$sb.AppendLine()

# ③ 答题明细
[void]$sb.AppendLine("## 三、答题明细（我的输入）")
[void]$sb.AppendLine()
$qi = 1
foreach ($rec in $studyLog) {
    $ans = $rec.input
    $res = if ($rec.result -eq 'correct') { '✅' } else { '❌' }
    [void]$sb.AppendLine("- $res **$($rec.word)** [$($rec.mode)]：我输入「$ans」")
    $qi++
}
[void]$sb.AppendLine()

# 写盘
$dir = $script:WP_DailyNoteDir
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$outFile = Join-Path $dir ($today + '.md')
[System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("已重建: {0} ({1} bytes)" -f $outFile, [IO.File]::ReadAllBytes($outFile).Length)
return $outFile
