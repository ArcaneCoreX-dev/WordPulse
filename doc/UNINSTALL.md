# WordPulse 卸载 · 清理 · 迁移流程文档

本项目**全程使用相对路径**（基于脚本自身位置推导），不写注册表、不装服务、不动系统目录，对主系统零影响。以下 `<项目根>` 指 WordPulse 文件夹所在位置（如 `D:\Tools\WordPulse`）。

---

## 一、卸载（完整移除）

### 1. 标准卸载（保留学习进度）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\tools\uninstall.ps1
```

执行内容：
- 删除桌面快捷方式「WordPulse 单词学习.lnk」（目标桌面从 `data\config.json` 读取，留空则系统桌面）
- 删除开机自启快捷方式（启动文件夹内的 WordPulse 快捷方式）
- **保留** `data\` 学习进度，便于以后重新安装继续学

### 2. 彻底卸载（连进度一起删）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\tools\uninstall.ps1 -PurgeData
```

执行内容：
- 删除上述两个快捷方式
- 交互确认后删除 `data\` 目录（学习进度永久丢失，**不可恢复**，请先确认是否需要备份）

### 3. 手动清理核对清单

| 检查项 | 位置 | 应无残留 |
|--------|------|----------|
| 桌面图标 | 桌面（见 config.json `desktopDir`）\WordPulse 单词学习.lnk | 已删除 |
| 开机自启 | 用户启动文件夹 \WordPulse 单词学习.lnk | 已删除 |
| 数据目录 | `<项目根>\data\` | 视是否 -PurgeData |
| 项目目录 | `<项目根>\`（整个 WordPulse 文件夹） | 保留（如需彻底删除，关闭程序后手动删除整个文件夹） |
| 系统注册表 | — | 从未写入 |
| 系统服务 | — | 从未安装 |

> 若需删除整个项目：先关闭所有 WordPulse 窗口，再删除整个 WordPulse 文件夹即可，无任何外部引用。

---

## 二、暂停 / 恢复

| 操作 | 方法 |
|------|------|
| 暂停自启 | 删除启动文件夹里的「WordPulse 单词学习.lnk」（保留桌面图标，想学时双击） |
| 恢复自启 | 重跑 `tools\install.ps1` |

---

## 三、迁移（换电脑 / 换目录）

WordPulse 的全部状态都在项目目录内，**脚本内部无绝对路径**，迁移只需拷贝文件夹。

### 迁移步骤

1. **停止程序**：确认新旧机器上所有 WordPulse 窗口均已关闭。
2. **拷贝项目**：将整个 `WordPulse\` 文件夹复制到新机器任意位置（U 盘 / 网盘均可）。
   - 学习进度在 `data\progress.json`，学习记录在 `data\notes\`，随目录一起走，**数据不丢**。
3. **新机器上安装**（无需任何配置，默认零外部依赖）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <新路径>\WordPulse\tools\install.ps1
   ```
   > 可选：如需把学习记录写入 Obsidian 库，编辑 `data\config.json` 的 `obsidianEnglishDir` 指向新机器 Obsidian 库 English 目录（留空则保存在项目内 `data\notes\English`）。

### 迁移验证清单

| 检查项 | 预期 |
|--------|------|
| 桌面快捷方式 | 指向新路径，双击能弹出学习窗 |
| 开机自启 | 新机器登录后自动弹窗 |
| 学习进度 | `progress.json` 中 streak / dailyLog / 单词状态完好 |
| 词库 | `data\wordbook_*.json` 四份齐全 |
| 学习记录 | `data\notes\English\每日英语学习` 随目录迁移（如配置了 Obsidian 则写入新配置目录） |

---

## 四、故障回退

| 现象 | 处理 |
|------|------|
| 窗口一闪即逝 | 用 `cmd /c start /min powershell -NoProfile -ExecutionPolicy Bypass -File <项目根>\app\wordpulse.ps1` 脱管启动 |
| 自检失败 | 跑 `app\wordpulse.ps1 -SelfTest`，核对输出 missing=0 |
| 进度文件损坏 | 备份后删除 `data\progress.json`，重启程序自动重建（词库不受影响） |
| 想重转词库 | 删除 `data\wordbook_*.json`，重跑 `tools\convert-wordbook.ps1` |
| 学习记录位置不对 | 默认在 `data\notes\English\每日英语学习`；如配置了 `obsidianEnglishDir` 则检查该配置 |
