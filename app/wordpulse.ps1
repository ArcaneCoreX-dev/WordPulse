# wordpulse.ps1 — WordPulse 开机单词学习窗（WPF 单文件 GUI）
#   用法：powershell -ExecutionPolicy Bypass -File <项目根>\app\wordpulse.ps1
#   自检：powershell -ExecutionPolicy Bypass -File <项目根>\app\wordpulse.ps1 -SelfTest
#   补弹：-Respawn 表示由 30 分钟补弹进程拉起，不再触发二次补弹
#   关闭：学完今日任务自动退出；未学完则安排 30 分钟后再弹一次
#   路径：全部相对化（基于脚本自身位置），项目整体可迁移
param([switch]$SelfTest, [switch]$Respawn)
$ErrorActionPreference = 'Continue'
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) }

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'core\wordpulse-core.ps1')

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Speech

# ============================================================ XAML =====
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WordPulse 单词学习窗" Width="880" Height="620" MinWidth="760" MinHeight="520"
        FontFamily="Microsoft YaHei UI" FontSize="13" Background="#F5F6FA"
        WindowStartupLocation="CenterScreen" Topmost="True" ShowInTaskbar="True">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- 顶部标题栏 -->
    <Border Grid.Row="0" Background="#1A2E5C" CornerRadius="8" Padding="16,10" Margin="0,0,0,10">
      <Grid>
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="WordPulse" FontSize="18" FontWeight="Bold" Foreground="White"/>
          <ComboBox x:Name="cmbLevel" Width="78" Height="24" Margin="12,2,0,0" FontSize="12" VerticalAlignment="Center" SelectedIndex="0" ToolTip="切换学习级别（进度各自保留，可随时切回）">
            <ComboBoxItem Tag="primary">小学</ComboBoxItem>
            <ComboBoxItem Tag="junior">初中</ComboBoxItem>
            <ComboBoxItem Tag="senior">高中</ComboBoxItem>
            <ComboBoxItem Tag="college">大学</ComboBoxItem>
          </ComboBox>
          <TextBlock x:Name="lblStreak" Text="🔥 连击 0 天" FontSize="13" Foreground="#FFD479" Margin="16,5,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="lblProgress" Text="0/10" FontSize="13" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" Margin="0,0,14,0"/>
          <Button x:Name="btnClose" Content="✕ 关闭" Width="64" Height="26" BorderThickness="0" Background="#3A4A76" Foreground="White" FontSize="12"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- 中部：左主词卡 + 右训练 -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="18"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- 左：主词卡（语境/朗读/文章） -->
      <Border Grid.Column="0" Background="White" CornerRadius="8" BorderBrush="#E2E6EF" BorderThickness="1" Padding="14">
        <DockPanel>
          <!-- 朗读按钮行 -->
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
            <Button x:Name="btnSpeakWord" Content="🔊 朗读单词" Height="28" Padding="10,0" Background="#EAF1FE" BorderBrush="#2A6DF4"/>
            <Button x:Name="btnSpeakSlow" Content="🐢 慢速" Height="28" Padding="10,0" Margin="8,0,0,0" Background="#EAF1FE" BorderBrush="#2A6DF4"/>
            <Button x:Name="btnSpeakSent" Content="🔊 朗读例句" Height="28" Padding="10,0" Margin="8,0,0,0" Background="#EAF1FE" BorderBrush="#2A6DF4"/>
          </StackPanel>

          <!-- 主词展示 -->
          <StackPanel DockPanel.Dock="Top" Margin="0,4,0,0">
            <TextBlock x:Name="txtWord" Text="word" FontSize="40" FontWeight="Bold" Foreground="#1A2E5C"/>
            <TextBlock x:Name="txtPhonetic" Text="/wɜːd/" FontSize="14" Foreground="#666" Margin="0,2,0,0"/>
            <TextBlock x:Name="txtMeaning" Text="n. 单词；话语" FontSize="16" Foreground="#2A6DF4" Margin="0,6,0,0" TextWrapping="Wrap"/>
          </StackPanel>

          <Separator DockPanel.Dock="Top" Margin="0,10,0,8"/>

          <!-- 语境：例句（每条例句旁带喇叭） -->
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Text="📖 语境 · 例句" FontSize="13" FontWeight="Bold" Foreground="#1A2E5C"/>
            <DockPanel Margin="0,4,0,0">
              <Button x:Name="btnSpeakSent1" Content="🔊" Width="30" Height="26" DockPanel.Dock="Left" Margin="0,0,6,0" Background="#EAF1FE" BorderBrush="#2A6DF4" FontSize="12" Padding="0" ToolTip="朗读例句1"/>
              <StackPanel>
                <TextBlock x:Name="txtSent1" Text="-" FontSize="13" Foreground="#333" TextWrapping="Wrap"/>
                <TextBlock x:Name="txtSent1Cn" Text="-" FontSize="12" Foreground="#888" TextWrapping="Wrap"/>
              </StackPanel>
            </DockPanel>
            <DockPanel Margin="0,6,0,0">
              <Button x:Name="btnSpeakSent2" Content="🔊" Width="30" Height="26" DockPanel.Dock="Left" Margin="0,0,6,0" Background="#EAF1FE" BorderBrush="#2A6DF4" FontSize="12" Padding="0" ToolTip="朗读例句2"/>
              <StackPanel>
                <TextBlock x:Name="txtSent2" Text="" FontSize="13" Foreground="#333" TextWrapping="Wrap"/>
                <TextBlock x:Name="txtSent2Cn" Text="" FontSize="12" Foreground="#888" TextWrapping="Wrap"/>
              </StackPanel>
            </DockPanel>
          </StackPanel>

          <!-- 文章：当日词编短文（点击标题进入阅读界面） -->
          <StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
            <Border Background="#F3F7FF" CornerRadius="6" Padding="10,8" BorderBrush="#C9D9F8" BorderThickness="1">
              <StackPanel>
                <TextBlock x:Name="txtArticleTitle" Text="📄 今日文章（点击阅读 →）" FontSize="12" FontWeight="Bold" Foreground="#2A6DF4" Cursor="Hand" ToolTip="点击打开文章阅读界面"/>
                <TextBlock x:Name="txtArticle" Text="今日文章生成中…" FontSize="12" Foreground="#444" Margin="0,4,0,0" TextWrapping="Wrap" MaxHeight="72"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </DockPanel>
      </Border>

      <!-- 右：训练区 -->
      <Border Grid.Column="2" Background="White" CornerRadius="8" BorderBrush="#E2E6EF" BorderThickness="1" Padding="14">
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="lblMode" Text="训练 · 选义" FontSize="14" FontWeight="Bold" Foreground="#1A2E5C"/>
              <TextBlock x:Name="lblModeHint" Text="（三种题型轮换）" FontSize="11" Foreground="#999" Margin="8,3,0,0"/>
            </StackPanel>
            <TextBlock x:Name="txtQuiz" Text="选择正确释义" FontSize="15" Foreground="#222" Margin="0,10,0,0" TextWrapping="Wrap" MinHeight="44"/>
          </StackPanel>

          <!-- 选义选项 -->
          <StackPanel DockPanel.Dock="Top" x:Name="panelChoice" Margin="0,8,0,0">
            <Button x:Name="opt1" Content="-" Height="40" Margin="0,0,0,6" HorizontalContentAlignment="Left" Padding="12,0" Background="#FAFBFF" BorderBrush="#C9D9F8"/>
            <Button x:Name="opt2" Content="-" Height="40" Margin="0,0,0,6" HorizontalContentAlignment="Left" Padding="12,0" Background="#FAFBFF" BorderBrush="#C9D9F8"/>
            <Button x:Name="opt3" Content="-" Height="40" Margin="0,0,0,6" HorizontalContentAlignment="Left" Padding="12,0" Background="#FAFBFF" BorderBrush="#C9D9F8"/>
            <Button x:Name="opt4" Content="-" Height="40" Margin="0,0,0,0" HorizontalContentAlignment="Left" Padding="12,0" Background="#FAFBFF" BorderBrush="#C9D9F8"/>
          </StackPanel>

          <!-- 拼写/填空输入 -->
          <StackPanel DockPanel.Dock="Top" x:Name="panelInput" Margin="0,8,0,0" Visibility="Collapsed">
            <TextBox x:Name="txtInput" Height="38" FontSize="16" Padding="8,6" BorderBrush="#2A6DF4" VerticalContentAlignment="Center"/>
            <Button x:Name="btnSubmit" Content="✓ 提交" Height="34" Margin="0,8,0,0" Background="#2A6DF4" Foreground="White" FontWeight="Bold"/>
          </StackPanel>

          <!-- 反馈 -->
          <StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
            <TextBlock x:Name="txtFeedback" Text="" FontSize="14" FontWeight="Bold" TextWrapping="Wrap" MinHeight="24"/>
            <Button x:Name="btnNext" Content="下一词 →" Height="40" Margin="0,8,0,0" Background="#1A2E5C" Foreground="White" FontWeight="Bold" FontSize="14"/>
          </StackPanel>
        </DockPanel>
      </Border>
    </Grid>

    <!-- 底部进度条 -->
    <Border Grid.Row="2" Background="White" CornerRadius="8" BorderBrush="#E2E6EF" BorderThickness="1" Padding="12,10" Margin="0,10,0,0">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid x:Name="barHost">
          <Border Background="#E8E8F0" CornerRadius="5" Height="14" VerticalAlignment="Center">
            <Border x:Name="barProgress" Background="#2A6DF4" CornerRadius="5" Height="14" HorizontalAlignment="Left" Width="0"/>
          </Border>
        </Grid>
        <TextBlock Grid.Column="1" x:Name="lblBarText" Text="今日进度 0%" FontSize="12" Foreground="#555" Margin="12,0,0,0" VerticalAlignment="Center"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)
function Find($n) { $window.FindName($n) }

# ============================================================ 状态 =====
$script:plan = $null
$script:queue = @()          # 待学队列（plan.all 的拷贝）
$script:cur = $null          # 当前词 @{ kind; word; entry; state; done }
$script:mode = 0             # 0 选义 / 1 拼写 / 2 填空
$script:answered = $false
$script:correctCount = 0
$script:doneCount = 0
$script:totalCount = 0
$script:distractors = @()    # 选义干扰项

# 选义选项按钮
$optBtns = @((Find 'opt1'), (Find 'opt2'), (Find 'opt3'), (Find 'opt4'))
$script:optAnswers = @()

# ============================================================ 文章阅读窗口 =====
$xamlReader = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="今日文章阅读" Width="720" Height="640" MinWidth="560" MinHeight="420"
        FontFamily="Microsoft YaHei UI" FontSize="13" Background="#FAFBFD"
        WindowStartupLocation="CenterScreen" Topmost="True">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <DockPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
          <Button x:Name="artPrev" Content="◀ 上一篇" Height="28" Padding="8,0" Background="#EAF1FE" BorderBrush="#2A6DF4" Margin="0,0,8,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="artTitle" Text="📄 今日文章" FontSize="20" FontWeight="Bold" Foreground="#1A2E5C" VerticalAlignment="Center"/>
          <Button x:Name="artNext" Content="下一篇 ▶" Height="28" Padding="8,0" Background="#EAF1FE" BorderBrush="#2A6DF4" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="artSub" Text="" FontSize="12" Foreground="#888" HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </DockPanel>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="artPanel" Margin="0,0,4,0"/>
    </ScrollViewer>
    <!-- 点词查义结果栏（点击文章中的任意单词，这里显示该词释义） -->
    <Border Grid.Row="2" x:Name="artLookupBar" Background="#EAF1FE" CornerRadius="6" Padding="10,8" Margin="0,10,0,0" Visibility="Collapsed">
      <TextBlock x:Name="artLookup" Text="" FontSize="13" Foreground="#1A2E5C" TextWrapping="Wrap"/>
    </Border>
  </Grid>
</Window>
'@
$script:articleWindow = $null

function Find2($n) { $script:articleWindow.FindName($n) }

# 点词查义：按点击处的字符偏移，从整句中提取所在单词，查当前级别词库并显示释义
function Show-WordLookup([string]$text, [int]$idx) {
    $bar = (Find2 'artLookupBar')
    $lab = (Find2 'artLookup')
    if (-not $bar -or -not $lab) { return }
    if ($idx -lt 0 -or $idx -gt $text.Length) { $bar.Visibility = [System.Windows.Visibility]::Collapsed; return }
    # 定位包含 idx 的连续字母 token（含 ' 与 -，如 don't、mid-air）
    $tok = $null
    $mm = [regex]::Match($text, "[A-Za-z''-]+")
    while ($mm.Success) {
        if ($mm.Index -le $idx -and $idx -lt $mm.Index + $mm.Length) { $tok = $mm.Value; break }
        $mm = $mm.NextMatch()
    }
    if (-not $tok) { $bar.Visibility = [System.Windows.Visibility]::Collapsed; return }
    $word = $tok.Trim("'")
    $e = Get-WPEntry $word $script:plan
    if ($e -and $e.meaning -and $e.meaning -notmatch '手动添加') {
        $phon = if ($e.phoneticUs) { '/' + $e.phoneticUs + '/' } else { '' }
        $lab.Text = ('【{0}】 {1}  —  {2}' -f $e.word, $phon, $e.meaning)
    } else {
        $lab.Text = ('【{0}】 当前词库暂无该词释义' -f $word)
    }
    $bar.Visibility = [System.Windows.Visibility]::Visible
}

# ============================================================ 文章阅读窗口 =====
# 注：New-WPArticle 已在 core 层定义（GUI 与 Obsidian 导出共用），此处直接调用
$script:articleIdx = 0   # 当前展示的词在 plan.all 中的索引

function Render-ArticleBody {
    # 根据当前索引渲染一篇文章到阅读窗口
    $panel = (Find2 'artPanel')
    $panel.Children.Clear()
    $items = @($script:plan.all)
    if ($items.Count -eq 0) { return }
    if ($script:articleIdx -lt 0) { $script:articleIdx = 0 }
    if ($script:articleIdx -ge $items.Count) { $script:articleIdx = $items.Count - 1 }

    $it = $items[$script:articleIdx]
    $e = $it.entry
    if (-not $e) { $e = Get-WPEntry $it.word $script:plan }
    $art = New-WPArticle $e
    $thisWord = $e.word

    # 标题与副栏
    (Find2 'artTitle').Text = '📄 ' + $art.title
    (Find2 'artSub').Text = ('级别：{0} · {1}/{2} · 点击 🔊 朗读 / 点击单词查释义' -f $script:plan.levelName, ($script:articleIdx + 1), $items.Count)
    # 切换文章时收起查义栏
    (Find2 'artLookupBar').Visibility = [System.Windows.Visibility]::Collapsed

    # 词条头：单词 + 音标 + 释义（可点词朗读）
    $headRow = New-Object System.Windows.Controls.DockPanel
    $headRow.Margin = New-Object System.Windows.Thickness(0, 2, 0, 6)
    $wordBtn = New-Object System.Windows.Controls.Button
    $wordBtn.Content = '🔊'
    $wordBtn.Width = 30
    $wordBtn.Height = 28
    $wordBtn.FontSize = 13
    $wordBtn.Padding = New-Object System.Windows.Thickness(0)
    $wordBtn.Background = (Get-Brush '#EAF1FE')
    $wordBtn.BorderBrush = (Get-Brush '#2A6DF4')
    $wordBtn.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $wordBtn.ToolTip = '朗读单词'
    [System.Windows.Controls.DockPanel]::SetDock($wordBtn, 'Left')
    $wordBtn.Add_Click({ Speak-Text $thisWord 0 }.GetNewClosure())
    $headRow.Children.Add($wordBtn) | Out-Null
    $headTxt = New-Object System.Windows.Controls.TextBlock
    $headTxt.Text = $e.word + '  ' + $(if ($e.phoneticUs) { '/' + $e.phoneticUs + '/' } else { '' }) + '  —  ' + $e.meaning
    $headTxt.FontSize = 16
    $headTxt.FontWeight = 'Bold'
    $headTxt.Foreground = (Get-Brush '#1A2E5C')
    $headTxt.TextWrapping = 'Wrap'
    $headTxt.VerticalAlignment = 'Center'
    $headRow.Children.Add($headTxt) | Out-Null
    $panel.Children.Add($headRow) | Out-Null

    # 导语段（点词查义）
    $leadBlock = New-Object System.Windows.Controls.TextBlock
    $leadBlock.Text = $art.lead
    $leadBlock.FontSize = 13
    $leadBlock.FontStyle = 'Italic'
    $leadBlock.Foreground = (Get-Brush '#444')
    $leadBlock.TextWrapping = 'Wrap'
    $leadBlock.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
    $leadText = $art.lead
    $leadBlock.Add_MouseLeftButtonUp({ param($s2, $e2)
        $tp = $s2.GetPositionFromPoint($e2.GetPosition($s2))
        if ($tp) { Show-WordLookup $leadText $tp.GetOffsetToPosition($s2.ContentStart) }
    }.GetNewClosure())
    $panel.Children.Add($leadBlock) | Out-Null

    # 语境段落（每段带朗读按钮）
    foreach ($p in $art.paras) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = '🔊'
        $btn.Width = 26
        $btn.Height = 22
        $btn.FontSize = 10
        $btn.Padding = New-Object System.Windows.Thickness(0)
        $btn.Background = (Get-Brush '#EAF1FE')
        $btn.BorderBrush = (Get-Brush '#2A6DF4')
        $btn.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $btn.ToolTip = '朗读此段'
        [System.Windows.Controls.DockPanel]::SetDock($btn, 'Left')
        $sentText = $p.en
        $btn.Add_Click({ Speak-Text $sentText 0 }.GetNewClosure())
        $row.Children.Add($btn) | Out-Null
        $st = New-Object System.Windows.Controls.TextBlock
        $st.Text = $p.en
        $st.FontSize = 13.5
        $st.Foreground = (Get-Brush '#222')
        $st.TextWrapping = 'Wrap'
        $st.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        $st.Cursor = [System.Windows.Input.Cursors]::Hand   # 提示可点
        $sentFull = $p.en
        $st.Add_MouseLeftButtonUp({ param($s2, $e2)
            $tp = $s2.GetPositionFromPoint($e2.GetPosition($s2))
            if ($tp) { Show-WordLookup $sentFull $tp.GetOffsetToPosition($s2.ContentStart) }
        }.GetNewClosure())
        $row.Children.Add($st) | Out-Null
        $panel.Children.Add($row) | Out-Null
        if ($p.cn) {
            $ct = New-Object System.Windows.Controls.TextBlock
            $ct.Text = $p.cn
            $ct.FontSize = 12
            $ct.Foreground = (Get-Brush '#888')
            $ct.Margin = New-Object System.Windows.Thickness(32, 0, 0, 6)
            $ct.TextWrapping = 'Wrap'
            $panel.Children.Add($ct) | Out-Null
        }
    }

    # 短语拓展
    if ($art.phrases.Count -gt 0) {
        $phHead = New-Object System.Windows.Controls.TextBlock
        $phHead.Text = '💡 常用搭配'
        $phHead.FontSize = 13
        $phHead.FontWeight = 'Bold'
        $phHead.Foreground = (Get-Brush '#2A6DF4')
        $phHead.Margin = New-Object System.Windows.Thickness(0, 10, 0, 2)
        $panel.Children.Add($phHead) | Out-Null
        foreach ($p in $art.phrases) {
            $phRow = New-Object System.Windows.Controls.StackPanel
            $phRow.Margin = New-Object System.Windows.Thickness(4, 2, 0, 0)
            $phTxt = New-Object System.Windows.Controls.TextBlock
            $phTxt.Text = '• ' + $p.en + $(if ($p.cn) { '  —  ' + $p.cn } else { '' })
            $phTxt.FontSize = 12.5
            $phTxt.Foreground = (Get-Brush '#333')
            $phTxt.TextWrapping = 'Wrap'
            $phRow.Children.Add($phTxt) | Out-Null
            $panel.Children.Add($phRow) | Out-Null
        }
    }

    # 收尾
    $outBlock = New-Object System.Windows.Controls.TextBlock
    $outBlock.Text = $art.outro
    $outBlock.FontSize = 13
    $outBlock.FontStyle = 'Italic'
    $outBlock.Foreground = (Get-Brush '#2A6DF4')
    $outBlock.TextWrapping = 'Wrap'
    $outBlock.Margin = New-Object System.Windows.Thickness(0, 12, 0, 0)
    $panel.Children.Add($outBlock) | Out-Null
}

function Show-ArticleReader {
    # 若已有阅读窗口打开则直接激活
    if ($script:articleWindow) {
        try { $script:articleWindow.Activate() } catch {}
        return
    }
    if (-not $script:plan -or @($script:plan.all).Count -eq 0) {
        # 今日无任务，无文章可读
        try {
            [System.Windows.MessageBox]::Show('今日没有待学单词，暂无可阅读文章。', 'WordPulse', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        } catch {}
        return
    }
    try {
        $w2 = [System.Windows.Markup.XamlReader]::Parse($xamlReader)
        $script:articleWindow = $w2
        # 默认定位到当前正在学习的词
        $script:articleIdx = 0
        if ($script:cur) {
            for ($i = 0; $i -lt @($script:plan.all).Count; $i++) {
                if (@($script:plan.all)[$i].word -eq $script:cur.word) { $script:articleIdx = $i; break }
            }
        }
        Render-ArticleBody

        (Find2 'artPrev').Add_Click({ $script:articleIdx--; Render-ArticleBody })
        (Find2 'artNext').Add_Click({ $script:articleIdx++; Render-ArticleBody })

        $w2.Add_Closed({ $script:articleWindow = $null })
        [void]$w2.ShowDialog()
    } catch {
        $script:articleWindow = $null
    }
}

# 今日文章标题点击 → 打开阅读界面
(Find 'txtArticleTitle').Add_MouseLeftButtonUp({ Show-ArticleReader })

# ============================================================ TTS =====
$script:tts = $null
$script:ttsVoice = $null
function Init-Tts {
    if ($script:tts) { return }
    try {
        $script:tts = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $script:tts.Rate = 0
        foreach ($v in $script:tts.GetInstalledVoices()) {
            $info = $v.VoiceInfo
            if ($info.Culture.Name -like 'en*') { $script:ttsVoice = $info.Name; break }
        }
        if ($script:ttsVoice) { $script:tts.SelectVoice($script:ttsVoice) }
    } catch { $script:tts = $null }
}
function Speak-Text([string]$text, [int]$rate = 0) {
    if (-not $script:tts) { Init-Tts }
    if (-not $script:tts) { return }
    try {
        $script:tts.Rate = $rate
        $script:tts.SpeakAsync($text) | Out-Null
    } catch {}
}

# ============================================================ 渲染 =====
function Get-Distractors([string]$word, $entry) {
    # 从当前级别词库随机取 3 个其他词的释义作干扰项（全库随机起点，避免总抽到词库头部）
    $lv = $script:plan.level
    $book = Get-WPBook $lv          # 懒加载：只保证当前级在缓存
    if (-not $book) { return @('词库未就绪-1', '词库未就绪-2', '词库未就绪-3') }
    $words = $book.words
    $total = @($words).Count
    $correctMeaning = if ($entry.meaning) { [string]$entry.meaning } else { '' }
    $rand = New-Object System.Random
    $picked = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    if ($correctMeaning) { $seen[$correctMeaning] = $true }
    $start = if ($total -gt 0) { $rand.Next($total) } else { 0 }
    $scan = [Math]::Min($total, 240)   # 从随机起点最多扫 240 条，兼顾多样性与耗时
    for ($i = 0; $i -lt $scan; $i++) {
        $cand = $words[($start + $i) % $total]
        if ($cand.word -eq $word) { continue }
        $m = [string]$cand.meaning
        if (-not $m -or $seen.ContainsKey($m)) { continue }
        $seen[$m] = $true
        $picked.Add($m)
        if ($picked.Count -ge 3) { break }
    }
    # 极端兜底（词库过小）
    $pad = 1
    while ($picked.Count -lt 3) { $picked.Add("释义不足-选项$pad"); $pad++ }
    return @($picked[0], $picked[1], $picked[2])
}

function Show-Entry($item) {
    $script:answered = $false
    # 关键修复：复习词的 entry 为 null，必须用解析后的词条重建 cur，
    # 否则判分时 cur.entry.meaning 恒为 null → 永远判错
    $w = $item.entry
    if (-not $w) { $w = Get-WPEntry $item.word $script:plan }
    $script:cur = @{ kind = $item.kind; word = $item.word; entry = $w; state = $item.state }

    (Find 'txtWord').Text = $w.word
    $phon = ''
    if ($w.phoneticUs) { $phon = '/' + $w.phoneticUs + '/' }
    if ($w.phoneticUk -and $w.phoneticUk -ne $w.phoneticUs) { $phon += '  英 /' + $w.phoneticUk + '/' }
    (Find 'txtPhonetic').Text = $phon
    (Find 'txtMeaning').Text = $w.meaning

    # 例句
    $ex = $w.examples
    if ($ex.Count -ge 1) {
        (Find 'txtSent1').Text = $ex[0].en
        (Find 'txtSent1Cn').Text = $ex[0].cn
    } else {
        (Find 'txtSent1').Text = '（暂无例句）'
        (Find 'txtSent1Cn').Text = ''
    }
    if ($ex.Count -ge 2) {
        (Find 'txtSent2').Text = $ex[1].en
        (Find 'txtSent2Cn').Text = $ex[1].cn
    } else {
        (Find 'txtSent2').Text = ''
        (Find 'txtSent2Cn').Text = ''
    }

    # 题型轮换
    $script:mode = $script:doneCount % 3
    Show-Quiz $w
    # 切换单词时同步刷新文章预览（跟随当前词）
    try { Render-Article } catch {}
    Update-Progress
}

function Show-Quiz($w) {
    $word = $w.word
    if ($script:mode -eq 0) {
        # 选义
        (Find 'lblMode').Text = '训练 · 选义'
        (Find 'lblModeHint').Text = '（看单词，选正确释义）'
        (Find 'txtQuiz').Text = '请选择「' + $word + '」的正确释义：'
        $dist = Get-Distractors $word $w
        $correct = $w.meaning
        $options = @($dist[0], $dist[1], $dist[2], $correct)
        # 洗牌
        $rand = New-Object System.Random
        for ($i = 3; $i -gt 0; $i--) {
            $j = $rand.Next($i + 1)
            $t = $options[$i]; $options[$i] = $options[$j]; $options[$j] = $t
        }
        $script:optAnswers = $options
        for ($k = 0; $k -lt 4; $k++) {
            $optBtns[$k].Content = $options[$k]
            $optBtns[$k].Background = Get-Brush '#FAFBFF'
            $optBtns[$k].BorderBrush = Get-Brush '#C9D9F8'
        }
        # 记录题目信息（题目文本含全部选项）
        $script:quizInfo = @{
            mode     = '选义'
            question = '请选择「' + $word + '」的正确释义：A. ' + $options[0] + '  B. ' + $options[1] + '  C. ' + $options[2] + '  D. ' + $options[3]
            correct  = $correct
        }
        (Find 'panelChoice').Visibility = 'Visible'
        (Find 'panelInput').Visibility = 'Collapsed'
        (Find 'txtInput').Text = ''
        (Find 'txtFeedback').Text = ''
    } elseif ($script:mode -eq 1) {
        # 拼写
        (Find 'lblMode').Text = '训练 · 拼写'
        (Find 'lblModeHint').Text = '（看释义，拼出单词）'
        (Find 'txtQuiz').Text = '根据释义拼写出单词：' + $w.meaning
        $script:quizInfo = @{
            mode     = '拼写'
            question = '根据释义拼写出单词：' + $w.meaning
            correct  = $word
        }
        (Find 'panelChoice').Visibility = 'Collapsed'
        (Find 'panelInput').Visibility = 'Visible'
        (Find 'txtInput').Text = ''
        (Find 'txtFeedback').Text = ''
        $window.Dispatcher.BeginInvoke([Action]{ (Find 'txtInput').Focus() | Out-Null }) | Out-Null
    } else {
        # 填空：用第一条例句挖空（词边界匹配，避免 'a'/'I' 等短词误伤整句）
        $ex = $w.examples
        $sent = $null
        if ($ex.Count -ge 1 -and $ex[0].en) {
            $pattern = '(?i)\b' + [regex]::Escape($word) + '\b'
            if ($ex[0].en -match $pattern) {
                $sent = [regex]::Replace($ex[0].en, $pattern, '______')
            }
        }
        if ($sent) {
            (Find 'lblMode').Text = '训练 · 填空'
            (Find 'lblModeHint').Text = '（看例句，填出单词）'
            (Find 'txtQuiz').Text = $sent
            $script:quizInfo = @{
                mode     = '填空'
                question = '看例句填空：' + $sent
                correct  = $word
            }
        } else {
            # 无合适例句时退化为拼写
            $script:mode = 1
            Show-Quiz $w
            return
        }
        (Find 'panelChoice').Visibility = 'Collapsed'
        (Find 'panelInput').Visibility = 'Visible'
        (Find 'txtInput').Text = ''
        (Find 'txtFeedback').Text = ''
        $window.Dispatcher.BeginInvoke([Action]{ (Find 'txtInput').Focus() | Out-Null }) | Out-Null
    }
}

function Get-Brush($html) {
    try {
        $c = (New-Object System.Windows.Media.ColorConverter).ConvertFromString($html)
        return [System.Windows.Media.SolidColorBrush]::new($c)
    } catch { return [System.Windows.Media.Brushes]::Gray }
}

function Update-Progress {
    # totalCount 在初始化时锁定，此处只算百分比，不重新赋值
    $pct = if ($script:totalCount -gt 0) { [int](100 * $script:doneCount / $script:totalCount) } else { 100 }
    (Find 'lblProgress').Text = "$script:doneCount/$script:totalCount"
    (Find 'lblBarText').Text = ('今日进度 {0}%' -f $pct)
    $w = [Math]::Max(0, [Math]::Min(1, $script:doneCount / [Math]::Max(1, $script:totalCount)))
    # 进度条宽度跟随容器实际宽度（窗口缩放不再留白），布局未完成时回退 600
    $bw = (Find 'barHost').ActualWidth
    if (-not $bw -or $bw -le 0) { $bw = 604 }
    (Find 'barProgress').Width = $w * [Math]::Max(0, $bw - 4)
}

function Render-Article {
    # 主界面预览：展示当前词的语境文章导语（点击标题进阅读界面看全文）
    $e = $null
    if ($script:cur) {
        $e = $script:cur.entry
        if (-not $e) { $e = Get-WPEntry $script:cur.word $script:plan }
    }
    if (-not $e) {
        # 无当前词时用今日第一个词兜底
        $it = @($script:plan.all | Select-Object -First 1)
        if ($it) {
            $e = $it[0].entry
            if (-not $e) { $e = Get-WPEntry $it[0].word $script:plan }
        }
    }
    if ($e) {
        $art = New-WPArticle $e
        (Find 'txtArticle').Text = $art.title + "`n" + $art.lead
    } else {
        (Find 'txtArticle').Text = '今日文章生成中…'
    }
}

# ============================================================ 答题 =====
# 当前题目的完整信息（供答题明细记录）：mode名 / 题目文本 / 正确答案
$script:quizInfo = @{ mode=''; question=''; correct='' }

function Mark-Answer([bool]$correct, [string]$detail) {
    $script:answered = $true
    $w = $script:cur
    # 答题明细：题型 / 题目（含选项） / 用户输入（无论对错）都记录
    $modeTxt = $script:quizInfo.mode
    $qText   = $script:quizInfo.question
    if (-not $modeTxt) { $modeTxt = if ($script:mode -eq 0) { '选义' } elseif ($script:mode -eq 1) { '拼写' } else { '填空' } }
    if (-not $qText) { $qText = (Find 'txtQuiz').Text }
    $progAfter = Submit-WPAnswer -word $w.word -correct $correct -plan $script:plan `
        -mode $modeTxt -question $qText -userInput $detail
    # 连击实时刷新：当日首次答题后 streak 已 +1，头部不能再停留在启动快照值
    if ($progAfter -and ([int]$progAfter.streak -ne [int]$script:plan.streak)) {
        $script:plan.streak = [int]$progAfter.streak
        (Find 'lblStreak').Text = ('🔥 连击 {0} 天' -f $progAfter.streak)
    }
    if ($correct) { $script:correctCount++ }
    $script:doneCount++

    $fb = (Find 'txtFeedback')
    if ($correct) {
        $fb.Text = '✅ 正确！' + $(if ($detail) { '（' + $detail + '）' } else { '' })
        $fb.Foreground = Get-Brush '#1E8E3E'
    } else {
        $fb.Text = '❌ 答错。正确：' + $script:quizInfo.correct
        $fb.Foreground = Get-Brush '#C0392B'
    }
    (Find 'btnNext').IsEnabled = $true
    Update-Progress
}

function Next-Word {
    if ($script:queue.Count -eq 0) { Finish-Session; return }
    $item = $script:queue[0]
    $script:queue = @($script:queue | Select-Object -Skip 1)
    Show-Entry $item
}

function Finish-Session {
    (Find 'txtWord').Text = '🎉 今日完成！'
    (Find 'txtPhonetic').Text = ''
    (Find 'txtMeaning').Text = ("共完成 {0} 词，答对 {1} 词，连击 {2} 天。继续坚持！" -f $script:doneCount, $script:correctCount, $script:plan.streak)
    (Find 'txtSent1').Text = '窗口 3 秒后自动关闭。'
    (Find 'txtSent1Cn').Text = '按记忆曲线，明天会有部分单词进入复习队列，届时再弹窗巩固。'
    (Find 'txtSent2').Text = ''
    (Find 'txtSent2Cn').Text = ''
    (Find 'panelChoice').Visibility = 'Collapsed'
    (Find 'panelInput').Visibility = 'Collapsed'
    (Find 'txtQuiz').Text = '已完成今日学习任务'
    (Find 'btnNext').Content = '立即关闭'
    (Find 'btnNext').IsEnabled = $true
    $script:finished = $true
    # 学完自动关闭：3 秒后关窗（按钮可提前关）
    Start-WPAutoClose 3
}

# ============================================================ 事件 =====
foreach ($k in 0..3) {
    $idx = $k
    # GetNewClosure：按值捕获 $idx，避免闭包引用循环变量（PS 脚本作用域陷阱）
    $optBtns[$k].Add_Click({
        if ($script:answered) { return }
        if ($script:mode -ne 0) { return }
        $selected = $script:optAnswers[$idx]
        $correct = ($selected -eq $script:cur.entry.meaning)
        Mark-Answer $correct $selected
    }.GetNewClosure())
}

(Find 'btnSubmit').Add_Click({
    if ($script:answered) { return }
    $input = (Find 'txtInput').Text.Trim()
    if (-not $input) { return }
    $w = $script:cur
    $correct = ($input.ToLowerInvariant() -eq $w.word.ToLowerInvariant())
    Mark-Answer $correct $input
})

(Find 'btnNext').Add_Click({
    if ($script:finished) { $window.Close(); return }
    Next-Word
})

(Find 'btnClose').Add_Click({ $window.Close() })
(Find 'btnSpeakWord').Add_Click({ if ($script:cur) { Speak-Text $script:cur.word 0 } })
(Find 'btnSpeakSlow').Add_Click({ if ($script:cur) { Speak-Text $script:cur.word -3 } })
(Find 'btnSpeakSent1').Add_Click({
    if ($script:cur -and $script:cur.entry.examples.Count -ge 1) { Speak-Text $script:cur.entry.examples[0].en 0 }
})
(Find 'btnSpeakSent2').Add_Click({
    if ($script:cur -and $script:cur.entry.examples.Count -ge 2) { Speak-Text $script:cur.entry.examples[1].en 0 }
})
# 修复：btnSpeakSent 此前在 XAML 声明但从未接线（死按钮）——现在顺序朗读全部例句
(Find 'btnSpeakSent').Add_Click({
    if ($script:cur -and $script:cur.entry -and $script:cur.entry.examples) {
        foreach ($x in $script:cur.entry.examples) { if ($x.en) { Speak-Text $x.en 0 } }
    }
})

# ============================================================ 快捷键 =====
# 1-4 选答案 / Enter 提交或下一词 / N 下一词（输入框聚焦时仅 Enter 生效，不影响打字）
function Click-Btn($b) {
    if ($b) { $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
}
$window.Add_PreviewKeyDown({
    param($s, $e)
    $inText = $e.OriginalSource -is [System.Windows.Controls.TextBox]
    $k = $e.Key
    if ($script:finished) {
        if ($k -eq [System.Windows.Input.Key]::Return -or $k -eq [System.Windows.Input.Key]::N) { $window.Close(); $e.Handled = $true }
        return
    }
    if ($k -eq [System.Windows.Input.Key]::Return) {
        if ($script:answered) { Click-Btn (Find 'btnNext') } else { Click-Btn (Find 'btnSubmit') }
        $e.Handled = $true
        return
    }
    if ($inText) { return }
    $optIdx = switch ($k) {
        D1 { 0 } NumPad1 { 0 }
        D2 { 1 } NumPad2 { 1 }
        D3 { 2 } NumPad3 { 2 }
        D4 { 3 } NumPad4 { 3 }
        N  { -2 }
        default { -1 }
    }
    if ($optIdx -ge 0) {
        if ($script:mode -eq 0 -and -not $script:answered) { Click-Btn $optBtns[$optIdx]; $e.Handled = $true }
    } elseif ($optIdx -eq -2) {
        if ($script:answered) { Click-Btn (Find 'btnNext'); $e.Handled = $true }
    }
})

# 窗口缩放时进度条跟随容器宽度
$window.Add_SizeChanged({ Update-Progress })

# 关闭时：未完成则 30 分钟后再弹
$window.Add_Closing({
    if ($script:finished -or $Respawn) { return }
    # 检查今日是否已全部完成
    if ($script:doneCount -ge $script:totalCount -and $script:totalCount -gt 0) { return }
    try {
        # 补弹脚本路径用 $PSCommandPath（当前脚本自身），迁移后自动跟随
        $self = $PSCommandPath
        $ps = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Start-Sleep -Seconds 1800; powershell -NoProfile -ExecutionPolicy Bypass -File '$self' -Respawn`""
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'start', '/min', $ps) -WindowStyle Hidden | Out-Null
    } catch {}
})

# ============================================================ 自动关闭 =====
# 学完/无任务后自动关窗；空闲 10 分钟无操作也自动关（未学完走 30 分钟补弹）
$script:autoCloseTimer = $null
$script:lastDoneCount = -1
$script:idleTicks = 0

function Start-WPAutoClose([int]$seconds = 3) {
    if ($script:autoCloseTimer) { try { $script:autoCloseTimer.Stop() } catch {} }
    $script:autoCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:autoCloseTimer.Interval = [TimeSpan]::FromSeconds($seconds)
    $script:autoCloseTimer.Add_Tick({
        $script:autoCloseTimer.Stop()
        try { $window.Close() } catch {}
    })
    $script:autoCloseTimer.Start()
}

# 空闲检测计时器：每 30s 检查一次，连续 20 次（10 分钟）无答题则自动关闭
$idleTimer = New-Object System.Windows.Threading.DispatcherTimer
$idleTimer.Interval = [TimeSpan]::FromSeconds(30)
$idleTimer.Add_Tick({
    if ($script:finished) { $idleTimer.Stop(); return }
    if ($script:doneCount -ne $script:lastDoneCount) {
        $script:lastDoneCount = $script:doneCount
        $script:idleTicks = 0
        return
    }
    $script:idleTicks++
    if ($script:idleTicks -ge 20) { try { $window.Close() } catch {} }
})
$idleTimer.Start()

# ============================================================ 级别切换 =====
function Switch-WPLevel([string]$newLv) {
    # 切换 progress.currentLevel 并重建当日队列；各级别状态都在 words 里，随时可切回
    $prog = Get-WPProgress
    $prog.currentLevel = $newLv
    Save-WPProgress $prog
    $newPlan = Get-WPDailyPlan
    if (-not $newPlan -or @($newPlan.all).Count -eq 0) {
        # 新级别今日无任务：显示无任务态（不自动关窗，用户可能还要切级别）
        if ($script:autoCloseTimer) { try { $script:autoCloseTimer.Stop() } catch {} }
        $script:plan = @{ level=$newLv; levelName=$script:WP_LevelNames[$newLv]; newWords=@(); reviewWords=@(); all=@(); today=(Get-WPDateStr); streak=$prog.streak }
        $script:queue = @(); $script:totalCount = 0; $script:doneCount = 0
        $script:finished = $true
        (Find 'txtWord').Text = '今日没有待学单词'
        (Find 'txtPhonetic').Text = ''
        (Find 'txtMeaning').Text = '可手动加词，或切换到其他级别继续学习。'
        (Find 'panelChoice').Visibility = 'Collapsed'
        (Find 'panelInput').Visibility = 'Collapsed'
        (Find 'txtQuiz').Text = '当前级别今日无任务'
        (Find 'btnNext').Content = '立即关闭'
        (Find 'btnNext').IsEnabled = $true
        (Find 'lblStreak').Text = ('🔥 连击 {0} 天' -f $prog.streak)
        Update-Progress
        return
    }
    # 有新任务：解除完成/自动关闭状态，重建队列从头开始
    if ($script:autoCloseTimer) { try { $script:autoCloseTimer.Stop() } catch {} }
    $script:plan = $newPlan
    $script:queue = @($newPlan.all)
    $script:doneCount = 0
    $script:correctCount = 0
    $script:totalCount = @($script:queue).Count
    $script:finished = $false
    (Find 'btnNext').Content = '下一词 →'
    (Find 'lblStreak').Text = ('🔥 连击 {0} 天' -f $newPlan.streak)
    Next-Word
    Update-Progress
}

# 级别下拉：先按当前进度同步选中项（此时尚未挂事件，不会触发切换）
$curLv = (Get-WPProgress).currentLevel
$lvItems = (Find 'cmbLevel').Items
for ($i = 0; $i -lt $lvItems.Count; $i++) {
    if ([string]$lvItems[$i].Tag -eq $curLv) { (Find 'cmbLevel').SelectedIndex = $i; break }
}
(Find 'cmbLevel').Add_SelectionChanged({
    $item = (Find 'cmbLevel').SelectedItem
    if (-not $item) { return }
    $newLv = [string]$item.Tag
    if ($script:plan -and $newLv -eq $script:plan.level) { return }   # 未变化（含初始化赋值）
    Switch-WPLevel $newLv
})

# ============================================================ 初始化 =====
Init-WPConfig | Out-Null   # 首次运行落盘 data\config.json（README 承诺行为，此前从未被调用）
try { Backup-WPProgress | Out-Null } catch { }   # 启动即滚动备份进度（同日仅一份，保留 7 份）
$script:plan = Get-WPDailyPlan
if (-not $script:plan -or @($script:plan.all).Count -eq 0) {
    # 今日无任务（词库已学完当前级别），提示后自动关闭
    $window.Title = 'WordPulse - 今日无任务'
    (Find 'txtWord').Text = '今日没有待学单词'
    (Find 'txtMeaning').Text = '可手动加词，或确认当前级别词库进度。'
    (Find 'btnNext').Content = '立即关闭'
    (Find 'btnNext').IsEnabled = $true
    $script:finished = $true
    $curLvStub = (Get-WPProgress).currentLevel
    $script:plan = @{ level=$curLvStub; levelName=$script:WP_LevelNames[$curLvStub]; newWords=@(); reviewWords=@(); all=@(); today=(Get-WPDateStr); streak=(Get-WPProgress).streak }
    Start-WPAutoClose 4
} else {
    (Find 'lblStreak').Text = ('🔥 连击 {0} 天' -f $script:plan.streak)
    $script:queue = @($script:plan.all)
    $script:doneCount = 0
    $script:totalCount = @($script:queue).Count
    Init-Tts
    Render-Article
    Next-Word
}

if ($SelfTest) {
    $names = @('cmbLevel','lblStreak','lblProgress','btnClose','btnSpeakWord','btnSpeakSlow',
               'btnSpeakSent','btnSpeakSent1','btnSpeakSent2','txtWord','txtPhonetic','txtMeaning',
               'txtSent1','txtSent1Cn','txtSent2','txtSent2Cn','txtArticleTitle','txtArticle',
               'lblMode','lblModeHint','txtQuiz','panelChoice','opt1','opt2','opt3','opt4',
               'panelInput','txtInput','btnSubmit','txtFeedback','btnNext','barProgress','barHost','lblBarText')
    $missing = @($names | Where-Object { -not (Find $_) })
    Write-Output ('SELFTEST: controls=' + $names.Count + ' missing=' + $missing.Count)
    if ($missing.Count) { Write-Output ('MISSING: ' + ($missing -join ', ')) }
    # 文章阅读窗自检（含点词查义新控件）
    $aNames = @('artTitle','artPrev','artNext','artSub','artPanel','artLookupBar','artLookup')
    try {
        $aw = [System.Windows.Markup.XamlReader]::Parse($xamlReader)
        $aMiss = @($aNames | Where-Object { -not $aw.FindName($_) })
        Write-Output ('SELFTEST-ARTICLE: controls=' + $aNames.Count + ' missing=' + $aMiss.Count)
        if ($aMiss.Count) { Write-Output ('AMISSING: ' + ($aMiss -join ', ')) }
    } catch {
        Write-Output ('SELFTEST-ARTICLE: XAML 解析失败 - ' + $_.Exception.Message)
    }
    $planInfo = if ($script:plan) { ('plan=' + $script:plan.levelName + ' total=' + $script:totalCount) } else { 'plan=null' }
    Write-Output ('SELFTEST: ' + $planInfo + ' xaml=OK')
    exit 0
}

[void]$window.ShowDialog()
