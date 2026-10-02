# restore-progress.ps1 — 列出进度备份并恢复指定备份
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File tools\restore-progress.ps1
$ErrorActionPreference = 'Stop'
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) }

$root = Split-Path -Parent $PSScriptRoot
$progress  = Join-Path $root 'data\progress.json'
$backupDir = Join-Path $root 'data\backups'

$bkps = @(Get-ChildItem $backupDir -Filter 'progress-*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
if ($bkps.Count -eq 0) {
    Write-Host '没有可用备份（backups 目录为空）。'
    exit 0
}

Write-Host '可用备份（新 → 旧）：'
for ($i = 0; $i -lt $bkps.Count; $i++) {
    $sizeKB = [math]::Round($bkps[$i].Length / 1KB, 1)
    Write-Host ("  [{0}] {1}  {2} KB  {3}" -f $i, $bkps[$i].Name, $sizeKB, $bkps[$i].LastWriteTime)
}

$pick = Read-Host '输入要恢复的备份编号（直接回车取消）'
if ([string]::IsNullOrWhiteSpace($pick)) { Write-Host '已取消，未做任何修改。'; exit 0 }
$n = 0
if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 0 -or $n -ge $bkps.Count) {
    Write-Host "无效编号：$pick"; exit 1
}

# 恢复前把当前进度另存一份，双保险
if (Test-Path $progress) {
    $keep = "$progress.before-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $progress $keep -Force
    Write-Host "当前进度已另存：$keep"
}
Copy-Item $bkps[$n].FullName $progress -Force
Write-Host ("已恢复：{0} → progress.json" -f $bkps[$n].Name)
Write-Host '提示：若学习窗正在运行，请关闭后重新打开以加载恢复后的进度。'
