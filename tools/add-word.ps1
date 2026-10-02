# add-word.ps1 — WordPulse 手动加词
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\tools\add-word.ps1 -Word perseverance
# 说明：把自定义词加入当前学习级别的词库（持久化到 progress.json 的 customWords）
param(
    [Parameter(Mandatory = $true)][string]$Word
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\wordpulse-core.ps1')

$ok = Add-WPCustomWord $Word
if ($ok) {
    Write-Host ("✓ 已加入自定义词：{0}（下次启动进入学习队列）" -f $Word.Trim())
} else {
    Write-Host "（未添加：单词为空，或已在自定义列表/词库中）"
}
