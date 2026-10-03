# build-full-dict.ps1 — 从 ECDICT stardict 包构建"全量查询词库" data\fullwordbook.tsv
# 用途：文章点词查义的兜底词库（不参与背诵队列，词库文件独立、不改变原有四级词库）
# 数据源：ECDICT（skywind3000，MIT）简明英汉增强版 stardict 包（data\raw\ecdict-stardict-28.zip）
# 产物：data\fullwordbook.tsv —— 每行 word<TAB>phonetic<TAB>translation，按 word 排序（供二分查找）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-full-dict.ps1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$root = Split-Path -Parent $PSScriptRoot
$rawBase = Join-Path $root 'data\raw\stardict-ecdict\stardict-ecdict-2.4.2'
$idxPath = Join-Path $rawBase 'stardict-ecdict-2.4.2.idx'
$dictPath = Join-Path $rawBase 'stardict-ecdict-2.4.2.dict'
$ifoPath = Join-Path $rawBase 'stardict-ecdict-2.4.2.ifo'
$outPath = Join-Path $root 'data\fullwordbook.tsv'

# ---------- 1) 收集"保留词集合"：四级词库词 + 派生形式 + 常用功能词 ----------
. (Join-Path $root 'core\wordpulse-core.ps1')
$studySet = @{}
foreach ($lv in $script:WP_BookLevels) {
    $book = Get-WPBook $lv
    foreach ($w in $book.words) { $studySet[[string]$w.word.ToLowerInvariant()] = $true }
}
Write-Output ("四级词库词数: {0}" -f $studySet.Count)

# 派生形式（复数/过去/进行/比较级等常见变化）
$suffixList = @('s','es','d','ed','ied','ing','ying','er','r','est','st','ies')
$formCount = 0
foreach ($w in @($studySet.Keys)) {
    if ($w.Length -gt 14) { continue }
    foreach ($sf in $suffixList) {
        $f = $w + $sf
        if ($f.Length -le 18 -and $f -match '^[a-z]+$') { $studySet[$f] = $true; $formCount++ }
    }
    if ($w.EndsWith('y') -and $w.Length -gt 2) {
        $f = $w.Substring(0, $w.Length - 1) + 'ies'
        if ($f.Length -le 18) { $studySet[$f] = $true; $formCount++ }
    }
}
Write-Output ("派生形式新增: {0}" -f $formCount)

# 常用功能词/高频词补充
$commonList = @(
'the','of','and','to','in','for','on','with','by','at','from','as','that','this','it','is','are','was','were','be','been','being','have','has','had','do','does','did','will','would','can','could','may','might','should','must','shall','not','no','yes','but','or','if','because','when','while','after','before','since','until','so','than','then','there','here','where','which','who','whom','whose','what','why','how','all','any','some','many','much','few','little','more','most','less','least','each','every','both','either','neither','other','another','one','two','three','four','five','six','seven','eight','nine','ten','hundred','thousand','million','first','second','third','last','next','again','also','always','never','often','sometimes','usually','very','really','quite','too','enough','only','just','even','still','yet','already','almost','about','above','below','under','over','through','between','among','during','without','within','against','toward','near','far','out','up','down','off','away','back','forward','left','right','top','bottom','inside','outside','into','onto','across','along','around','such','like','unlike','etc','people','thing','time','day','year','week','month','hour','minute','second','today','tomorrow','yesterday','morning','afternoon','evening','night','home','house','school','class','student','teacher','friend','family','father','mother','brother','sister','child','baby','girl','boy','man','woman','world','place','city','town','country','water','food','eat','drink','go','come','see','look','watch','hear','listen','say','tell','talk','speak','ask','answer','know','think','feel','want','need','like','love','hate','give','take','get','make','do','work','play','run','walk','sit','stand','live','die','open','close','start','stop','begin','end','use','put','find','lose','keep','hold','bring','send','carry','build','buy','sell','pay','show','help','try','learn','teach','read','write','study','remember','forget','meet','leave','stay','sleep','wake','wear','wash','clean','cut','wait','turn','move','change','follow','call','visit','travel','fly','drive','ride','swim','jump','fall','throw','catch','hit','kick','push','pull','lift','drop','join','share','enjoy','happen','believe','understand','seem','become','grow','stay','return','arrive','reach','pass','cross','enter','climb','choose','decide','hope','wish','plan','expect','wonder','guess','suppose','prove','explain','describe','report','notice','watch','discover','create','invent','produce','build','develop','improve','increase','reduce','save','spend','cost','afford','borrow','lend','collect','pack','prepare','serve','offer','accept','refuse','agree','disagree','argue','discuss','consider','remember','mention','suggest','advise','warn','protect','prevent','avoid','escape','finish','complete','continue','pause','stop','hurry','rush','wait','delay','hurry')
foreach ($c in $commonList) { $studySet[$c] = $true }
Write-Output ("保留词集合: {0}" -f $studySet.Count)

# ---------- 2) 扫描 idx，收集保留词的偏移 ----------
$ifo = Get-Content $ifoPath | Select-String '^wordcount=' | Select-Object -First 1
$wordCount = [int]$ifo.Line.Split('=')[1]
$idxBytes = [System.IO.File]::ReadAllBytes($idxPath)
$kept = New-Object System.Collections.Generic.List[object]
$i = 0
$p = 0
$idxLen = $idxBytes.Length
while ($p -lt $idxLen) {
    # 单词直到 \0
    $wStart = $p
    while ($p -lt $idxLen -and $idxBytes[$p] -ne 0) { $p++ }
    if ($p -ge $idxLen) { break }
    $word = [System.Text.Encoding]::UTF8.GetString($idxBytes, $wStart, $p - $wStart)
    $p++   # 跳过 \0
    if ($p + 8 -gt $idxLen) { break }
    $off = ([uint32]$idxBytes[$p] -shl 24) -bor ([uint32]$idxBytes[$p+1] -shl 16) -bor ([uint32]$idxBytes[$p+2] -shl 8) -bor ([uint32]$idxBytes[$p+3])
    $sz  = ([uint32]$idxBytes[$p+4] -shl 24) -bor ([uint32]$idxBytes[$p+5] -shl 16) -bor ([uint32]$idxBytes[$p+6] -shl 8) -bor ([uint32]$idxBytes[$p+7])
    $p += 8
    $low = $word.ToLowerInvariant()
    if ($studySet.ContainsKey($low) -and $low -match '^[a-z''-]{1,20}$') {
        $kept.Add(@($low, $off, $sz))
    }
    $i++
    if ($i % 400000 -eq 0) { Write-Output ("idx 扫描 {0}/{1} ..." -f $i, $wordCount) }
}
Write-Output ("idx 总条数: {0}  保留: {1}" -f $i, $kept.Count)

# ---------- 3) 读 dict 段，提取音标与首条翻译 ----------
$dfs = [System.IO.File]::OpenRead($dictPath)
$sb = New-Object System.Text.StringBuilder
$phonRx = [regex]'^[*]?\s*\[([^\]]+)\]'
foreach ($k in $kept) {
    $w = $k[0]; $off = [int]$k[1]; $sz = [int]$k[2]
    $buf = New-Object byte[] $sz
    $dfs.Position = $off
    [void]$dfs.Read($buf, 0, $sz)
    $txt = [System.Text.Encoding]::UTF8.GetString($buf)
    $phon = ''
    $body = $txt
    $m = $phonRx.Match($txt)
    if ($m.Success) { $phon = $m.Groups[1].Value; $body = $txt.Substring($m.Length) }
    # 首条非空翻译（去掉 [网络] 前缀与行号类噪音）
    $line = ''
    foreach ($ln in ($body -split "`n")) {
        $t = $ln.Trim("`r", ' ', '　', '*')
        if (-not $t) { continue }
        if ($t -match '^\[网络\]|^\[地名\]|^\[人名\]|^\[例句\]|^\[常用\]') { continue }
        $line = $t
        break
    }
    if (-not $line) { continue }
    if ($line.Length -gt 60) { $line = $line.Substring(0, 60) }
    [void]$sb.AppendLine($w + "`t" + $phon + "`t" + $line)
}
$dfs.Close()
Write-Output ("TSV 行数: {0}" -f ($sb.ToString() -split "`n").Count)

# ---------- 4) 排序写出（无 BOM UTF-8，供二分查找） ----------
$lines = @($sb.ToString() -split "`n" | Where-Object { $_ })
$sorted = $lines | Sort-Object
[System.IO.File]::WriteAllText($outPath, ($sorted -join "`n"), [System.Text.UTF8Encoding]::new($false))
$out = Get-Item $outPath
Write-Output ("完成: {0}  {1:N2} MB  {2} 行" -f $outPath, ($out.Length / 1MB), $sorted.Count)
