# convert-wordbook.ps1
# WordPulse 词库转换脚本：把有道 NDJSON 教材词库转换为四级分级词库
# 输出: data/wordbook_{level}.json  (level = primary / junior / senior / college)
# 编码约定：脚本自身 UTF-8 BOM；输出 JSON 一律 UTF-8 无 BOM
# 路径：默认基于脚本位置（项目根），相对化可迁移
param(
    [string]$BooksDir,
    [string]$OutDir
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# 默认路径基于脚本位置（项目根），迁移后自动跟随
if (-not $BooksDir) { $BooksDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'data\books' }
if (-not $OutDir)   { $OutDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'data' }

# 级别 -> 书册前缀映射（按教材分级，由简单到难）
$levelMap = @{
    "primary" = @("PEPXiaoXue")
    "junior"  = @("PEPChuZhong")
    "senior"  = @("PEPGaoZhong")
    "college" = @("CET4", "CET6")
}

$levelNames = @{ "primary"="小学"; "junior"="初中"; "senior"="高中"; "college"="大学" }

function Convert-WordBook($level) {
    $prefixes = $levelMap[$level]
    $books = Get-ChildItem $BooksDir -Directory | Where-Object {
        $n = $_.Name
        ($prefixes | Where-Object { $n.StartsWith($_) }).Count -gt 0
    } | Sort-Object Name
    if (-not $books) { Write-Host "[$level] no books, skip"; return $null }

    $seen = @{}
    $words = New-Object System.Collections.Generic.List[object]
    $bookCount = 0

    foreach ($book in $books) {
        $ndjson = Get-ChildItem $book.FullName -Filter *.json | Select-Object -First 1
        if (-not $ndjson) { continue }
        $bookCount++
        Write-Host "  [$($book.Name)] parsing..."
        $lines = [System.IO.File]::ReadAllLines($ndjson.FullName, [System.Text.Encoding]::UTF8)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $obj = $null
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            if (-not $obj -or -not $obj.headWord) { continue }

            $word = $obj.headWord.Trim()
            $key = $word.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $inner = $obj.content.word.content
            $meaning = ""
            if ($inner.trans) {
                $meaning = ($inner.trans | ForEach-Object { $_.tranCn } | Where-Object { $_ }) -join "；"
            }
            $meaningEn = ""
            if ($inner.trans) {
                $en = ($inner.trans | Where-Object { $_.tranOther } | Select-Object -First 1)
                if ($en) { $meaningEn = $en.tranOther }
            }
            $examples = @()
            if ($inner.sentence -and $inner.sentence.sentences) {
                foreach ($s in $inner.sentence.sentences) {
                    if ($examples.Count -ge 3) { break }
                    if ($s.sContent) {
                        $cn = ""
                        if ($s.sCn) { $cn = $s.sCn }
                        $examples += @{ en = $s.sContent; cn = $cn }
                    }
                }
            }
            $phrases = @()
            if ($inner.phrase -and $inner.phrase.phrases) {
                foreach ($p in $inner.phrase.phrases) {
                    if ($phrases.Count -ge 3) { break }
                    if ($p.pContent) {
                        $cn = ""
                        if ($p.pCn) { $cn = $p.pCn }
                        $phrases += @{ en = $p.pContent; cn = $cn }
                    }
                }
            }
            $us = ""
            if ($inner.usphone) { $us = $inner.usphone }
            $uk = ""
            if ($inner.ukphone) { $uk = $inner.ukphone }
            $words.Add(@{
                word        = $word
                phoneticUs  = $us
                phoneticUk  = $uk
                meaning     = $meaning
                meaningEn   = $meaningEn
                examples    = $examples
                phrases     = $phrases
            })
        }
    }

    Write-Host "[$level] parsed $($words.Count) words ($bookCount books)"
    return @{ level = $level; levelName = $levelNames[$level]; count = $words.Count; words = $words }
}

Write-Host "=== WordPulse wordbook convert start ==="
$results = @()
foreach ($level in @("primary", "junior", "senior", "college")) {
    $r = Convert-WordBook $level
    if ($r) { $results += $r }
}

foreach ($r in $results) {
    $json = $r | ConvertTo-Json -Depth 6 -Compress
    $outFile = Join-Path $OutDir "wordbook_$($r.level).json"
    [System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    $len = [System.IO.File]::ReadAllBytes($outFile).Length
    Write-Host "written: $outFile ($len bytes)"
}
Write-Host "=== convert done ==="
