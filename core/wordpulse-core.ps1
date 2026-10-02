# wordpulse-core.ps1
# WordPulse 核心引擎：词库加载 + SM-2 间隔重复调度 + 每日记录 + 打卡统计
# 设计：纯数据层，不依赖 GUI，可独立冒烟测试；GUI 通过 dot-source 引用
# 编码：本脚本 UTF-8 BOM；进度 JSON 落盘 UTF-8 无 BOM

# ============ 路径与基础（全部相对化，可整体迁移） ============
# 项目根：由脚本自身位置推导（core 的父目录），不依赖绝对路径
$script:WP_Root      = Split-Path -Parent $PSScriptRoot
$script:WP_DataDir   = Join-Path $script:WP_Root "data"
$script:WP_Progress  = Join-Path $script:WP_DataDir "progress.json"
$script:WP_Config    = Join-Path $script:WP_DataDir "config.json"
$script:WP_BackupDir = Join-Path $script:WP_DataDir "backups"   # progress.json 每日滚动备份
$script:WP_BackupKeep = 7                                        # 保留最近 N 份备份
$script:WP_BookLevels = @("primary", "junior", "senior", "college")
$script:WP_LevelNames = @{ primary="小学"; junior="初中"; senior="高中"; college="大学" }

# ============ 配置文件（项目外依赖统一收敛，迁移只改此处） ============
# config.json 结构：
#   obsidianEnglishDir : Obsidian 笔记库 English 目录（每日记录写入其下「每日英语学习」）
#   desktopDir         : 桌面快捷方式目标目录（install/uninstall 用，留空则自动探测）
#   maxReviewPerDay    : 每日复习队列封顶（0/负数=不限），旧 config 无此字段时按默认 20 处理
function Get-WPConfig {
    if (Test-Path $script:WP_Config) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:WP_Config, [System.Text.Encoding]::UTF8)
            $cfg = $raw | ConvertFrom-Json
            return $cfg
        } catch { }
    }
    # 默认配置：学习记录默认保存在项目内 data\notes\English（零外部依赖，解压即用）
    # 若用户配置了 obsidianEnglishDir，则记录写入其 Obsidian 库（可选进阶）
    return @{
        obsidianEnglishDir = ''   # 留空 = 记录保存到项目内 data\notes\English\每日英语学习
        desktopDir         = ''
        maxReviewPerDay    = 20    # 每日复习队列封顶（0 或负数 = 不限制），防止断学后到期词涌爆
    }
}

function Save-WPConfig($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 4 -Compress
    if (-not (Test-Path $script:WP_DataDir)) { New-Item -ItemType Directory -Force -Path $script:WP_DataDir | Out-Null }
    Write-WPAtomicText $script:WP_Config $json
}

# 确保配置落盘（首次运行自动生成，供用户迁移时修改）
function Init-WPConfig {
    if (Test-Path $script:WP_Config) { return Get-WPConfig }
    $cfg = Get-WPConfig
    Save-WPConfig $cfg
    return $cfg
}

# 词库缓存（进程内，按级别懒加载）：level -> @{ meta=@{}; words=List }
$script:WP_Books = @{}
# word→entry 索引缓存（level -> hashtable，键为小写单词），Get-WPEntry O(1) 查找用
$script:WP_Index = @{}

function New-WPUtf8NoBom {
    return New-Object System.Text.UTF8Encoding($false)
}

# 原子写文本：先完整写入 .tmp，再 NTFS rename 覆盖目标（元数据级微秒窗口）
# 目的：崩溃/断电只会留下多余 tmp 文件，绝不会产生半截 JSON 覆盖真实数据
function Write-WPAtomicText([string]$path, [string]$text) {
    $tmp = "$path.tmp"
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($tmp, $text, (New-WPUtf8NoBom))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

# ============ 词库加载（按级别懒加载：启动只解析当前级，弹窗提速） ============
function Get-WPBook([string]$Level) {
    # 加载并缓存单个级别词库；返回 @{ meta; words }，词库文件不存在返回 $null
    if ($script:WP_Books.ContainsKey($Level)) { return $script:WP_Books[$Level] }
    $path = Join-Path $script:WP_DataDir "wordbook_$Level.json"
    if (-not (Test-Path $path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $data = $raw | ConvertFrom-Json
    $book = @{
        meta  = @{ level=$data.level; levelName=$data.levelName; count=$data.count }
        words = $data.words
    }
    $script:WP_Books[$Level] = $book
    # 构建该级 word→entry 索引（小写键），避免每次线性扫描整库
    $map = @{}
    foreach ($w in $data.words) {
        $k = [string]$w.word
        if ($k -and -not $map.ContainsKey($k.ToLowerInvariant())) {
            $map[$k.ToLowerInvariant()] = $w
        }
    }
    $script:WP_Index[$Level] = $map
    return $book
}

function Get-WPBooks {
    # 全量加载（兼容旧调用与测试脚本）；日常运行路径请优先用 Get-WPBook 单级加载
    foreach ($lv in $script:WP_BookLevels) { Get-WPBook $lv | Out-Null }
    return $script:WP_Books
}

# ============ 进度持久化 ============
function Get-WPProgress {
    # 返回进度对象；不存在则初始化；解析失败（文件损坏）则自愈：留证 + 回退最新备份
    if (Test-Path $script:WP_Progress) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:WP_Progress, [System.Text.Encoding]::UTF8)
            return ($raw | ConvertFrom-Json)
        } catch {
            try {
                $bad = "$script:WP_Progress.corrupt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Move-Item $script:WP_Progress $bad -Force   # 坏文件留证，绝不带着空对象继续跑再覆盖
                $bak = Get-WPLatestBackup
                if ($bak) {
                    Copy-Item $bak $script:WP_Progress -Force
                    try {
                        $raw = [System.IO.File]::ReadAllText($script:WP_Progress, [System.Text.Encoding]::UTF8)
                        return ($raw | ConvertFrom-Json)
                    } catch { }
                }
            } catch { }
        }
    }
    return @{
        version       = 1
        currentLevel  = "primary"          # 当前学习级别
        streak        = 0                   # 连续打卡天数
        lastStudyDate = ""                 # 上次学习日期 (yyyy-MM-dd)
        dailyLog      = @()                # 每日学习记录
        words         = [pscustomobject]@{} # 每词复习状态: word -> state（与 JSON 读回类型一致，避免 hashtable 假属性键）
        customWords   = @()                # 手动添加词（word 文本列表）
    }
}

function Save-WPProgress($prog) {
    $json = $prog | ConvertTo-Json -Depth 8 -Compress
    Write-WPAtomicText $script:WP_Progress $json
}

# ============ 进度备份与恢复 ============
# 备份命名 progress-<yyyyMMdd-HHmmss>.json，同日只留一份，超出保留数自动清理
function Backup-WPProgress {
    if (-not (Test-Path $script:WP_Progress)) { return $null }
    if (-not (Test-Path $script:WP_BackupDir)) { New-Item -ItemType Directory -Force -Path $script:WP_BackupDir | Out-Null }
    $todayStamp = (Get-Date).ToString('yyyyMMdd')
    $all = @(Get-ChildItem $script:WP_BackupDir -Filter 'progress-*.json' -File | Sort-Object Name -Descending)
    $todayBak = @($all | Where-Object { $_.Name -like "progress-$todayStamp-*" })
    if ($todayBak.Count -gt 0) { return $todayBak[0].FullName }   # 当日已有备份
    $dest = Join-Path $script:WP_BackupDir ("progress-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item $script:WP_Progress $dest -Force
    # 清理：重新枚举（含刚写入的新备份）按名降序，保留最新 N 份
    # 注意不能把 $dest 直接追加到旧数组尾部——新备份名最大应排最前，否则会被误删
    $now = @(Get-ChildItem $script:WP_BackupDir -Filter 'progress-*.json' -File | Sort-Object Name -Descending)
    if ($now.Count -gt $script:WP_BackupKeep) {
        $now | Select-Object -Skip $script:WP_BackupKeep | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    return $dest
}

function Get-WPLatestBackup {
    if (-not (Test-Path $script:WP_BackupDir)) { return $null }
    $f = @(Get-ChildItem $script:WP_BackupDir -Filter 'progress-*.json' -File | Sort-Object Name -Descending) | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

function Get-WPDateStr {
    return (Get-Date).ToString("yyyy-MM-dd")
}

# 手动加词：把词追加到当前级别词库（持久化到自定义列表，下次启动生效）
function Add-WPCustomWord([string]$word) {
    if ([string]::IsNullOrWhiteSpace($word)) { return $false }
    $w = $word.Trim()
    $prog = Get-WPProgress
    $exists = @($prog.customWords | Where-Object { $_ -eq $w }).Count -gt 0
    if ($exists) { return $false }
    # 追加并写回
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($x in $prog.customWords) { $list.Add($x) }
    $list.Add($w)
    $prog.customWords = $list.ToArray()
    Save-WPProgress $prog
    $script:WP_Books = @{}   # 清缓存（含索引），下次按级别重新懒加载
    $script:WP_Index = @{}
    return $true
}

# ============ SM-2 间隔重复（简化版） ============
# state: @{ level; interval; due; reps; lapses; lastResult }
# level 0=新词；学后按答对次数提升，interval 1/3/7/15/30 天
function Get-WPDefaultState {
    return @{ level=0; interval=0; due=""; reps=0; lapses=0; lastResult="" }
}

function Update-WPState($state, [bool]$correct) {
    # 返回更新后的 state（不落盘，由调用方统一保存）
    if ($correct) {
        $state.reps++
        switch ($state.level) {
            0 { $state.level = 1; $state.interval = 1 }
            1 { $state.level = 2; $state.interval = 3 }
            2 { $state.level = 3; $state.interval = 7 }
            3 { $state.level = 4; $state.interval = 15 }
            default { $state.level = 5; $state.interval = 30 }
        }
        $state.lastResult = "correct"
    } else {
        $state.lapses++
        $state.level = [Math]::Max(0, $state.level - 1)
        $state.interval = 1
        $state.lastResult = "wrong"
    }
    $state.due = (Get-Date).AddDays($state.interval).ToString("yyyy-MM-dd")
    return $state
}

# ============ 每日计划 ============
# 返回 @{ level; levelName; newWords=@(); reviewWords=@(); all=@() }
function Get-WPDailyPlan {
    $prog = Get-WPProgress
    $today = Get-WPDateStr
    $lv = $prog.currentLevel
    $book = Get-WPBook $lv          # 懒加载：只解析当前级词库
    if (-not $book) { return $null }

    # 1) 到期复习词：state 存在且 due <= today，按 level 升序（快遗忘的优先）
    #    封顶 maxReviewPerDay：多出的顺延到之后每天（未答题 due 不变，天然排队，无需额外记账）
    $reviewWords = @()
    $wordStates = $prog.words
    foreach ($k in $wordStates.PSObject.Properties.Name) {
        $st = $wordStates.$k
        if ($st.due -and $st.due -le $today) {
            $reviewWords += @{ word=$k; state=$st; level=$st.level }
        }
    }
    $reviewWords = @($reviewWords | Sort-Object @{e={$_.level}}, @{e={$_.state.lapses}; Descending=$true})
    $cfg = Get-WPConfig
    $maxReview = 20
    # 字段存在即采信（含 0/负数 = 不限制）；不能用 -and $cfg.xxx 真值判断，0 会被误当缺省
    $mrProp = $cfg.PSObject.Properties['maxReviewPerDay']
    if ($null -ne $mrProp -and $null -ne $mrProp.Value) { $maxReview = [int]$mrProp.Value }
    if ($maxReview -gt 0 -and $reviewWords.Count -gt $maxReview) {
        $reviewWords = @($reviewWords | Select-Object -First $maxReview)
    }

    # 2) 新词：当前级别词库中从未出现在 state 的，取前 N（默认每日新词 10 个）
    $newCount = 10
    $known = @{}
    foreach ($k in $wordStates.PSObject.Properties.Name) { $known[$k.ToLowerInvariant()] = $true }
    foreach ($cw in $prog.customWords) { $known[$cw.ToLowerInvariant()] = $true }
    $newCandidates = @()
    foreach ($w in $book.words) {
        if (-not $known.ContainsKey($w.word.ToLowerInvariant())) {
            $newCandidates += $w
            if ($newCandidates.Count -ge $newCount) { break }
        }
    }

    $newWords = @()
    foreach ($w in $newCandidates) {
        $newWords += @{ word=$w.word; entry=$w; state=(Get-WPDefaultState) }
    }

    $all = @()
    foreach ($r in $reviewWords) { $all += @{ kind="review"; word=$r.word; entry=$null; state=$r.state } }
    foreach ($n in $newWords)   { $all += @{ kind="new";    word=$n.word; entry=$n.entry; state=$n.state } }

    return @{
        level      = $lv
        levelName  = $script:WP_LevelNames[$lv]
        newWords   = $newWords
        reviewWords = $reviewWords
        all        = $all
        today      = $today
        streak     = $prog.streak   # GUI 头部连击展示依赖，缺失会导致"连击  天"空白
    }
}

# 取词条详情（新词从词库取；复习词若词库没有（手动词）则生成占位）
function Get-WPEntry([string]$word, $plan) {
    # 确保该级别已懒加载，然后走索引 O(1) 查找；未命中回退占位（手动词场景）
    $lv = $plan.level
    Get-WPBook $lv | Out-Null
    if ($script:WP_Index.ContainsKey($lv)) {
        $hit = $script:WP_Index[$lv][$word.ToLowerInvariant()]
        if ($hit) { return $hit }
    }
    # 手动词占位
    return @{ word=$word; phoneticUs=""; phoneticUk=""; meaning="(手动添加词，暂无释义)"; meaningEn=""; examples=@(); phrases=@() }
}

# ============ 学习记录导出（默认项目内 data\notes，可选 Obsidian） ============
# 记录目录优先级：① config.json 的 obsidianEnglishDir（配置了则写入 Obsidian 库）
#                   ② 未配置 → 项目内 data\notes\English（零外部依赖，整体可迁移）
$script:WP_ObsidianDir = $null
function Get-WPObsidianDir {
    if ($script:WP_ObsidianDir) { return $script:WP_ObsidianDir }
    $cfg = Get-WPConfig
    $dir = [string]$cfg.obsidianEnglishDir
    if (-not $dir -or -not (Test-Path $dir)) {
        # 未配置或目录不存在：默认保存到项目内 data\notes\English
        $dir = Join-Path $script:WP_DataDir 'notes\English'
    }
    $script:WP_ObsidianDir = $dir
    return $dir
}
$script:WP_DailyNoteDir = $null
function Get-WPDailyNoteDir {
    if ($script:WP_DailyNoteDir) { return $script:WP_DailyNoteDir }
    $dir = Join-Path (Get-WPObsidianDir) '每日英语学习'
    $script:WP_DailyNoteDir = $dir
    return $dir
}

function Get-WPObsidianNotePath {
    return Join-Path (Get-WPDailyNoteDir) ((Get-WPDateStr) + '.md')
}

# 生成今日学习记录 Markdown 并写入记录目录：<记录根>\每日英语学习\<日期>.md
# 记录根 = 项目内 data\notes\English（默认）或 config.json 配置的 Obsidian 目录（可选）
# 每次答题后调用，实时更新，崩溃也不丢
# 结构：①今日单词+例句+语境文章 ②训练题目与正误 ③用户输入明细（含错误）
function Export-WPDailyNote {
    $prog = Get-WPProgress
    $today = Get-WPDateStr
    $lv = $prog.currentLevel
    $lvName = $script:WP_LevelNames[$lv]
    $todayLog = $null
    if ($prog.dailyLog -and @($prog.dailyLog).Count -gt 0) {
        $todayLog = $prog.dailyLog | Where-Object { $_.date -eq $today } | Select-Object -Last 1
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# 每日英语学习 · $today")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- 学习级别：$lvName")
    [void]$sb.AppendLine("- 连续打卡：$($prog.streak) 天")
    if ($todayLog) {
        [void]$sb.AppendLine("- 今日新词：$($todayLog.newWords) 个 / 答对 $($todayLog.correctNew)")
        [void]$sb.AppendLine("- 今日复习：$($todayLog.reviewWords) 个 / 答对 $($todayLog.correctReview)")
        [void]$sb.AppendLine("- 答题总数：$($todayLog.words.Count) 次")
    } else {
        [void]$sb.AppendLine("- 今日尚未开始学习")
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()

    # ===== ① 今日单词 + 例句 + 语境文章（全部列出） =====
    # 词源 = 今日实际答题记录（与训练记录同源，保证一致）
    # 不用 Get-WPDailyPlan().all —— 那是动态重算的最新计划，学完后会换成下一批新词
    $wordList = @()
    if ($todayLog -and $todayLog.words -and @($todayLog.words).Count -gt 0) {
        $wordList = @($todayLog.words | ForEach-Object { $_.word } | Select-Object -Unique)
    }

    if ($wordList.Count -gt 0) {
        [void]$sb.AppendLine("## 一、今日单词 · 例句 · 语境文章")
        [void]$sb.AppendLine()
        $idx = 1
        foreach ($w in $wordList) {
            $entry = Get-WPEntry $w @{ level = $lv }
            $phon = if ($entry.phoneticUs) { ('/' + $entry.phoneticUs + '/') } else { '' }
            $meaning = if ($entry.meaning) { $entry.meaning } else { '' }
            $kindMark = ''
            $rec = $null
            if ($todayLog -and $todayLog.words) {
                $rec = $todayLog.words | Where-Object { $_.word -eq $w } | Select-Object -Last 1
                if ($rec) { $kindMark = if ($rec.kind -eq 'new') { ' 🆕' } else { ' 🔄' } }
            }
            [void]$sb.AppendLine("### $idx. **$w**$kindMark  $phon — $meaning")
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

            # 全部例句
            if ($entry.examples.Count -gt 0) {
                [void]$sb.AppendLine("例句：")
                foreach ($s in $entry.examples) {
                    if ($s.en) {
                        # 用「」标注英文例句，避免反引号转义问题
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
    }

    # ===== ② 训练题目 + 正误判定 =====
    if ($todayLog -and $todayLog.words -and @($todayLog.words).Count -gt 0) {
        [void]$sb.AppendLine("## 二、训练记录")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("| # | 单词 | 题型 | 题目 | 我的答案 | 判定 |")
        [void]$sb.AppendLine("|---|------|------|------|---------|------|")
        $qi = 1
        foreach ($rec in $todayLog.words) {
            $modeTxt = $rec.mode
            if (-not $modeTxt) {
                # 兼容旧记录（无 mode 字段）
                $modeTxt = if ($rec.kind -eq 'new') { '选义/拼写/填空' } else { '选义/拼写/填空' }
            }
            $q = $rec.question
            if (-not $q) { $q = '（题目）' }
            $q = $q.Replace('|', '\|')
            $ans = $rec.userInput
            if (-not $ans) { $ans = '（未记录）' }
            $ans = $ans.Replace('|', '\|')
            $res = if ($rec.result -eq 'correct') { '✅ 对' } else { '❌ 错' }
            [void]$sb.AppendLine("| $qi | $($rec.word) | $modeTxt | $q | $ans | $res |")
            $qi++
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine()
    }

    # ===== ③ 用户输入明细（无论对错全部列出） =====
    if ($todayLog -and $todayLog.words -and @($todayLog.words).Count -gt 0) {
        [void]$sb.AppendLine("## 三、答题明细（我的输入）")
        [void]$sb.AppendLine()
        $qi = 1
        foreach ($rec in $todayLog.words) {
            $modeTxt = $rec.mode
            if (-not $modeTxt) { $modeTxt = '' }
            $ans = $rec.userInput
            if (-not $ans) { $ans = '（未记录）' }
            $res = if ($rec.result -eq 'correct') { '✅' } else { '❌' }
            [void]$sb.AppendLine("- $res **$($rec.word)** [$modeTxt]：我输入「$ans」")
            $qi++
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine()
    }

    $dir = Get-WPDailyNoteDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $outFile = Get-WPObsidianNotePath
    Write-WPAtomicText $outFile $sb.ToString()
    return $outFile
}
# 记录一次答题结果；返回更新后的 progress
# ============ 语境文章生成（core 层，GUI 与 Obsidian 导出共用） ============
# 把词条数据组装成一篇围绕该词的完整语境文章（不是例句罗列）
# 返回 @{ title; lead; paras=@( @{en;cn} ); phrases=@( @{en;cn} ); outro; word }
function New-WPArticle($entry) {
    $word = $entry.word
    $title = 'The Story of "' + $word + '"'
    $lead  = ''

    # 导语：基于英文释义/中文释义写引入句
    $meaning = $entry.meaning
    $meaningEn = $entry.meaningEn
    if ($meaningEn) {
        $lead = '"' + $word + '" is a word worth knowing. In plain terms, it means: ' + $meaningEn.TrimEnd('.') + '.'
    } else {
        $lead = '"' + $word + '" is a word worth knowing. It means: ' + $meaning + '.'
    }

    # 语境段落：用例句编织（每条例句作为一段语境的落点）
    $paras = @()
    foreach ($s in $entry.examples) {
        $en = $s.en
        $cn = if ($s.cn) { $s.cn } else { '' }
        if (-not $en) { continue }
        $paras += @{ en = $en; cn = $cn }
        if ($paras.Count -ge 3) { break }
    }
    if ($paras.Count -eq 0) {
        $paras += @{ en = 'Here, "' + $word + '" appears in real life, and you can feel how it works in context.'; cn = '在这里，「' + $word + '」出现在真实语境中，你可以感受它如何使用。' }
    }

    # 短语拓展
    $phrs = @()
    foreach ($p in $entry.phrases) {
        if ($p.en) { $phrs += @{ en = $p.en; cn = if ($p.cn) { $p.cn } else { '' } } }
        if ($phrs.Count -ge 3) { break }
    }

    # 收尾
    $outro = 'Now you have met "' + $word + '" in real context. Try using it in your own sentences today — that is how words come alive!'
    if ($meaning) {
        $outro += '（' + $word + '：' + $meaning + '）'
    }

    return @{
        title = $title
        lead  = $lead
        paras = $paras
        phrases = $phrs
        outro = $outro
        word  = $word
    }
}

# ============ 记录答题 & 打卡 ============
function Submit-WPAnswer([string]$word, [bool]$correct, $plan, [string]$mode = "", [string]$question = "", [string]$userInput = "") {
    $prog = Get-WPProgress
    $today = Get-WPDateStr

    # 更新单词状态
    if (-not $prog.words.PSObject.Properties[$word]) {
        $prog.words | Add-Member -NotePropertyName $word -NotePropertyValue (Get-WPDefaultState)
    }
    $state = $prog.words.$word
    $newState = Update-WPState $state $correct
    $prog.words.$word = $newState

    # 打卡/连击：首次在当天答题视为学习
    if ($prog.lastStudyDate -ne $today) {
        if ($prog.lastStudyDate -eq (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")) {
            $prog.streak++
        } else {
            $prog.streak = 1
        }
        $prog.lastStudyDate = $today
        # 新建当日记录
        $prog.dailyLog += @{
            date=$today; newWords=0; reviewWords=0; correctNew=0; correctReview=0; words=@()
        }
    }

    # 更新当日记录
    $todayLog = $prog.dailyLog | Where-Object { $_.date -eq $today } | Select-Object -Last 1
    $isNew = $false
    if ($plan -and $plan.newWords) {
        $isNew = @($plan.newWords | Where-Object { $_.word -eq $word }).Count -gt 0
    }
    $logList = New-Object System.Collections.Generic.List[object]
    foreach ($x in $todayLog.words) { $logList.Add($x) }
    # 完整答题明细：题型 / 题目 / 用户输入（无论对错）/ 判定
    $logList.Add(@{
        word      = $word
        result    = $(if($correct){"correct"}else{"wrong"})
        kind      = $(if($isNew){"new"}else{"review"})
        mode      = $mode          # 选义 / 拼写 / 填空
        question  = $question      # 题目文本（选项题含选项）
        userInput = $userInput     # 用户实际选择/输入的原文
    })
    $todayLog.words = $logList.ToArray()
    if ($isNew) {
        $todayLog.newWords++
        if ($correct) { $todayLog.correctNew++ }
    } else {
        $todayLog.reviewWords++
        if ($correct) { $todayLog.correctReview++ }
    }
    # 回写 dailyLog（按索引替换当日项）
    for ($i = 0; $i -lt $prog.dailyLog.Count; $i++) {
        if ($prog.dailyLog[$i].date -eq $today) { $prog.dailyLog[$i] = $todayLog; break }
    }

    Save-WPProgress $prog

    # 每次答题后实时导出每日学习记录（崩溃也不丢）
    try { Export-WPDailyNote | Out-Null } catch { }

    return $prog
}

# 今日进度摘要（供 GUI 展示）
function Get-WPTodaySummary($plan) {
    $prog = Get-WPProgress
    $today = Get-WPDateStr
    $todayLog = $prog.dailyLog | Where-Object { $_.date -eq $today } | Select-Object -Last 1
    $doneCount = 0
    if ($todayLog) { $doneCount = $todayLog.words.Count }
    $total = @($plan.all).Count
    return @{
        streak      = $prog.streak
        done        = $doneCount
        total       = $total
        newCount    = @($plan.newWords).Count
        reviewCount = @($plan.reviewWords).Count
        levelName   = $plan.levelName
    }
}
