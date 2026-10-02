# test-note-consistency.ps1 — 验证修复后：今日单词 = 训练记录 = 实际所学
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Get-WPObsidianNotePath) -Force -ErrorAction SilentlyContinue

$plan = Get-WPDailyPlan
Write-Host ("今日计划: {0} 词（但只学其中一部分，验证导出只列实际所学的）" -f @($plan.all).Count)

# 只答 3 个词（模拟学到一半）
Submit-WPAnswer -word $plan.all[0].word -correct $true  -plan $plan -mode '选义' -question '请选择「ruler」的正确释义' -userInput '尺子' | Out-Null
Submit-WPAnswer -word $plan.all[1].word -correct $false -plan $plan -mode '拼写' -question '根据释义拼写出单词：铅笔' -userInput 'pencel' | Out-Null
Submit-WPAnswer -word $plan.all[2].word -correct $true  -plan $plan -mode '填空' -question '看例句填空：Press to bring up the ______ tool.' -userInput 'eraser' | Out-Null

$note = Get-WPObsidianNotePath
$content = [IO.File]::ReadAllText($note, [Text.Encoding]::UTF8)

Write-Host ""
Write-Host "=== ① 今日单词部分（### 词条）==="
$wordSection = ($content -split "`r?`n") | Where-Object { $_ -match '^### ' }
$wordSection
Write-Host ""
Write-Host "=== ② 训练记录（表格单词列）==="
$trainWords = @($content -split "`r?`n") | Where-Object { $_ -match '^\| \d+ \|' } | ForEach-Object { ($_ -split '\|')[2].Trim() }
$trainWords -join ', '
Write-Host ""
Write-Host "=== ③ 一致性检查 ==="
$secWords = @($wordSection | ForEach-Object { if ($_ -match '\*\*([^*]+)\*\*') { $matches[1].Trim() } })
$secWords -join ', '
$consistent = ($secWords.Count -eq $trainWords.Count)
if ($consistent) {
    for ($i = 0; $i -lt $secWords.Count; $i++) {
        if ($secWords[$i] -ne $trainWords[$i]) { $consistent = $false; break }
    }
}
"今日单词数: $($secWords.Count) | 训练记录数: $($trainWords.Count)"
"今日单词与训练记录一致: $(if($consistent){'✅ 一致'}else{'❌ 不一致'})"
"未学的词(yellow等)是否出现在今日单词: $(if($content -match 'yellow'){'❌ 出现(错误)'}else{'✅ 未出现(正确)'})"

# 清理
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item $note -Force -ErrorAction SilentlyContinue
Write-Host "=== 一致性验证完成 ==="
