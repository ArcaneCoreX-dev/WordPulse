# uninstall.ps1 — WordPulse 卸载：删除快捷方式 + 可选清理数据
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\tools\uninstall.ps1
#       powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\tools\uninstall.ps1 -PurgeData   # 连学习进度一起删
# 路径：全部相对化；桌面目录从 data\config.json 读取
param([switch]$PurgeData)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'core\wordpulse-core.ps1')

# 桌面目录：优先配置，留空则系统桌面
$desktop = ''
$cfg = Get-WPConfig
if ($cfg.desktopDir) { $desktop = [string]$cfg.desktopDir }
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = [Environment]::GetFolderPath('Desktop') }

# 真实用户启动目录探测（与 install.ps1 保持一致）
function Get-RealStartupDir {
    $startup = $null
    try { $startup = [Environment]::GetFolderPath('Startup') } catch {}
    if ($startup -and (Test-Path $startup)) { return $startup }
    $prof = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPath -like 'C:\Users\*' -and $_.Loaded -eq $true } |
            Select-Object -First 1
    if ($prof) {
        $cand = Join-Path $prof.LocalPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        if (Test-Path $cand) { return $cand }
    }
    return $null
}
$startup = Get-RealStartupDir

$lnks = @()
$lnks += (Join-Path $desktop 'WordPulse 单词学习.lnk')
if ($startup) { $lnks += (Join-Path $startup 'WordPulse 单词学习.lnk') }

$removed = 0
foreach ($l in $lnks) {
    if (Test-Path $l) { Remove-Item $l -Force; $removed++; Write-Host "已删除: $l" }
}
Write-Host "=== 快捷方式清理完成（删除 $removed 个）==="

if ($PurgeData) {
    $dataDir = Join-Path $root 'data'
    if (Test-Path $dataDir) {
        Write-Host "即将删除数据目录（学习进度将永久丢失）：$dataDir"
        Write-Host "确认输入 YES 后回车继续，其他输入取消："
        $ans = Read-Host
        if ($ans -eq 'YES') {
            Remove-Item $dataDir -Recurse -Force
            Write-Host "已删除数据目录。"
        } else {
            Write-Host "已取消数据清理，进度保留。"
        }
    }
} else {
    Write-Host "学习进度已保留（data\progress.json）。如需彻底清除，请加 -PurgeData 参数重跑。"
}

Write-Host '=== 卸载完成 ==='
Write-Host '说明：项目目录保留，如需迁移请参考 README「迁移」章节。'
