# install.ps1 — WordPulse 安装：桌面快捷方式 + 开机自启（启动文件夹）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\tools\install.ps1
# 说明：只创建两个快捷方式，不写注册表、不装服务，卸载即删，零系统残留
# 路径：全部相对化（基于脚本自身位置）；桌面目录从 data\config.json 读取
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$root = Split-Path -Parent $PSScriptRoot
$app  = Join-Path $root 'app\wordpulse.ps1'
$icon = Join-Path $root 'assets\WordPulse.ico'
if (-not (Test-Path $icon)) {
    Write-Host '[提示] 未找到 assets\WordPulse.ico，将使用系统默认图标。可运行 tools\make-icon.ps1 重新生成。'
}
. (Join-Path $root 'core\wordpulse-core.ps1')

# 桌面目录：优先配置（config.json desktopDir），留空则系统桌面
$desktop = ''
$cfg = Get-WPConfig
if ($cfg.desktopDir) { $desktop = [string]$cfg.desktopDir }
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = [Environment]::GetFolderPath('Desktop') }
if (-not (Test-Path $desktop)) {
    Write-Host '[错误] 未找到可用桌面目录，请检查 data\config.json 的 desktopDir 配置。'
    exit 1
}

# 真实用户启动目录探测（自动化服务账户的 APPDATA 会指向 Public，不可用）
function Get-RealStartupDir {
    $startup = $null
    try { $startup = [Environment]::GetFolderPath('Startup') } catch {}
    if ($startup -and (Test-Path $startup)) { return $startup }
    # 兜底：按加载中的用户配置文件反查
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
if (-not $startup) {
    Write-Host '[错误] 未找到可用的用户启动目录，开机自启快捷方式跳过（桌面快捷方式仍会创建）。'
}

# 桌面快捷方式：双击即学
$desktopLnk = Join-Path $desktop 'WordPulse 单词学习.lnk'
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($desktopLnk)
$sc.TargetPath = 'powershell.exe'
$sc.Arguments  = "-NoProfile -ExecutionPolicy Bypass -File `"$app`""
$sc.WorkingDirectory = $root
$sc.Description = 'WordPulse 开机单词学习窗'
if (Test-Path $icon) { $sc.IconLocation = "$icon,0" } else { $sc.IconLocation = "$env:SystemRoot\System32\shell32.dll,71" }
$sc.Save()

# 开机自启快捷方式：登录后自动弹窗（仅在找到启动目录时创建）
if ($startup) {
    $startupLnk = Join-Path $startup 'WordPulse 单词学习.lnk'
    $sc2 = $ws.CreateShortcut($startupLnk)
    $sc2.TargetPath = 'powershell.exe'
    $sc2.Arguments  = "-NoProfile -ExecutionPolicy Bypass -File `"$app`""
    $sc2.WorkingDirectory = $root
    $sc2.Description = 'WordPulse 开机自启'
    if (Test-Path $icon) { $sc2.IconLocation = "$icon,0" } else { $sc2.IconLocation = "$env:SystemRoot\System32\shell32.dll,71" }
    $sc2.Save()
    Write-Host ("开机自启快捷 : {0}" -f $startupLnk)
} else {
    Write-Host '开机自启快捷 : （未创建，见上文错误说明）'
}

Write-Host '=== WordPulse 安装完成 ==='
Write-Host ("桌面快捷方式 : {0}" -f $desktopLnk)
Write-Host ("开机自启快捷 : {0}" -f $startupLnk)
Write-Host '下次登录 Windows 将自动弹出学习窗；双击桌面图标可立即学习。'
Write-Host '卸载请运行 tools\uninstall.ps1'
