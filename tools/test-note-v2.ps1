# test-note-v2.ps1 — 端到端验证 Obsidian 每日记录文档（三部分结构）
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item (Get-WPObsidianNotePath) -Force -ErrorAction SilentlyContinue

$plan = Get-WPDailyPlan
Write-Host ("今日任务: {0} 词" -f @($plan.all).Count)

# 模拟三种题型答题（含对错，带用户输入）
# 选义对 / 拼写错 / 填空对
Submit-WPAnswer -word $plan.all[0].word -correct $true  -plan $plan -mode '选义' -question '请选择「ruler」的正确释义：A. 尺子  B. 苹果  C. 桌子  D. 铅笔' -userInput '尺子' | Out-Null
Submit-WPAnswer -word $plan.all[1].word -correct $false -plan $plan -mode '拼写' -question '根据释义拼写出单词：铅笔' -userInput 'pencel' | Out-Null
Submit-WPAnswer -word $plan.all[2].word -correct $true  -plan $plan -mode '填空' -question '看例句填空：Press to bring up the ______ tool.' -userInput 'eraser' | Out-Null

$note = Get-WPObsidianNotePath
Write-Host ("文档生成: {0}" -f (Test-Path $note))
if (-not (Test-Path $note)) { exit 1 }

$content = [IO.File]::ReadAllText($note, [Text.Encoding]::UTF8)
Write-Host "=== 文档预览（前 55 行）==="
($content -split "`r?`n") | Select-Object -First 55

Write-Host ""
Write-Host "=== 结构完整性检查 ==="
$checks = @{
    '① 今日单词部分'   = $content -match '## 一、今日单词'
    '② 训练记录部分'   = $content -match '## 二、训练记录'
    '③ 答题明细部分'   = $content -match '## 三、答题明细'
    '语境文章标题'     = $content -match 'The Story of'
    '例句列出'         = $content -match '例句：'
    '我的错误输入(pencel)' = $content -match 'pencel'
    '我的正确输入(eraser)' = $content -match 'eraser'
    '判错标记'         = $content -match '❌'
}
foreach ($k in $checks.Keys) { "{0,-22}: {1}" -f $k, $(if($checks[$k]){'✅'}else{'❌ 缺失'}) }

# 清理测试数据
Remove-Item (Join-Path (Split-Path -Parent $PSScriptRoot) 'data\progress.json') -Force -ErrorAction SilentlyContinue
Remove-Item $note -Force -ErrorAction SilentlyContinue
Write-Host "=== 端到端验证完成（测试数据已清理）==="
