#Requires -Version 5.1
param([switch]$Preview)
<#
  豆包浮動待辦 v2.1（深色簡潔・琥珀強調・緊湊・可複製）
  浮動頭：Grok Bot 頭像；懸停／移動時眼睛跟隨游標；右鍵先彈跳再開待辦
  左鍵開豆包／拖曳移動；面板配色佈局與秘書 API 不變
  GET secretary.kenfungv.workers.dev/api/todo7 ；Token: SECRETARY_TODO_TOKEN；唯讀
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [void][System.Windows.Forms.Application]::SetHighDpiMode('PerMonitorV2') } catch {}
[void][System.Windows.Forms.Application]::EnableVisualStyles()

$DoubaoExe = 'C:\Users\User\AppData\Local\Doubao\Application\Doubao.exe'
$ApiUrl    = 'https://secretary.kenfungv.workers.dev/api/todo7'

$cBg        = [System.Drawing.Color]::FromArgb(18, 18, 20)
$cSurface   = [System.Drawing.Color]::FromArgb(28, 28, 32)
$cSurface2  = [System.Drawing.Color]::FromArgb(36, 36, 42)
$cBorder    = [System.Drawing.Color]::FromArgb(55, 55, 62)
$cText      = [System.Drawing.Color]::FromArgb(236, 236, 240)
$cMuted     = [System.Drawing.Color]::FromArgb(140, 140, 150)
$cFaint     = [System.Drawing.Color]::FromArgb(100, 100, 110)
$cAccent    = [System.Drawing.Color]::FromArgb(245, 158, 11)
$cOverdue   = [System.Drawing.Color]::FromArgb(248, 113, 113)
$cToday     = [System.Drawing.Color]::FromArgb(245, 158, 11)
$cSoon      = [System.Drawing.Color]::FromArgb(251, 191, 36)
$cNormal    = [System.Drawing.Color]::FromArgb(140, 140, 150)
$cError     = [System.Drawing.Color]::FromArgb(248, 113, 113)
$cKey       = [System.Drawing.Color]::Magenta

function New-UiFont([single]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    foreach ($n in @('Microsoft JhengHei UI', 'Segoe UI', 'Microsoft YaHei UI', 'Arial')) {
        try {
            $f = New-Object System.Drawing.Font($n, $size, $style)
            if ($f.FontFamily.Name -eq $n -or $n -eq 'Arial') { return $f }
            $f.Dispose()
        } catch {}
    }
    return New-Object System.Drawing.Font('Segoe UI', $size, $style)
}

$fontTitle  = New-UiFont 12.5 ([System.Drawing.FontStyle]::Bold)
$fontSub    = New-UiFont 8.5
$fontItem   = New-UiFont 10
$fontPill   = New-UiFont 8 ([System.Drawing.FontStyle]::Bold)
$fontDate   = New-UiFont 8
$fontStatus = New-UiFont 9.5

function Get-Brush([System.Drawing.Color]$color) { New-Object System.Drawing.SolidBrush($color) }
function Get-RoundedPath([int]$x, [int]$y, [int]$w, [int]$h, [int]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, $r, $r, 180, 90)
    $p.AddArc(($x + $w - $r), $y, $r, $r, 270, 90)
    $p.AddArc(($x + $w - $r), ($y + $h - $r), $r, $r, 0, 90)
    $p.AddArc($x, ($y + $h - $r), $r, $r, 90, 90)
    $p.CloseFigure()
    return $p
}


# Grok Bot avatar (256px face space; matches assets/grok_bot_face.png)
$script:faceBmp = $null
$script:lookX = 0.0; $script:lookY = 0.0
$script:lookTX = 0.0; $script:lookTY = 0.0
$script:hovering = $false
$script:bouncing = $false
$script:bounceT = 0.0
$script:pendingToggle = $false
$script:pupilR = 15.0
$script:eyes = @(
    @{ Cx = 86.0;  Cy = 116.0; Rx = 38.0; Ry = 42.0 }
    @{ Cx = 170.0; Cy = 116.0; Rx = 38.0; Ry = 42.0 }
)

function Import-AvatarFace {
    $root = $PSScriptRoot
    if ([string]::IsNullOrEmpty($root) -and $PSCommandPath) {
        $root = Split-Path -Parent $PSCommandPath
    }
    if ([string]::IsNullOrEmpty($root)) { $root = (Get-Location).Path }
    $path = Join-Path $root 'assets/grok_bot_face.png'
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $ms = New-Object System.IO.MemoryStream
        $ms.Write($bytes, 0, $bytes.Length)
        [void]$ms.Seek(0, [System.IO.SeekOrigin]::Begin)
        $tmp = [System.Drawing.Bitmap]::FromStream($ms)
        $script:faceBmp = New-Object System.Drawing.Bitmap($tmp)
        $tmp.Dispose(); $ms.Dispose()
    } catch {}
}

function Start-AvatarAnim {
    if ($null -ne $script:animTimer -and -not $script:animTimer.Enabled) { $script:animTimer.Start() }
}

function Get-BounceXform([double]$t) {
    if ($t -le 0 -or $t -ge 1) { return @{ Sx = 1.0; Sy = 1.0; Oy = 0.0 } }
    if ($t -lt 0.22) {
        $u = $t / 0.22
        $e = $u * $u
        return @{ Sx = (1.0 + 0.14 * $e); Sy = (1.0 - 0.18 * $e); Oy = (2.5 * $e) }
    }
    if ($t -lt 0.55) {
        $u = ($t - 0.22) / 0.33
        $e = [Math]::Sin($u * [Math]::PI / 2.0)
        return @{
            Sx = (1.14 + (0.88 - 1.14) * $e)
            Sy = (0.82 + (1.16 - 0.82) * $e)
            Oy = (2.5 + (-9.0 - 2.5) * $e)
        }
    }
    $u = ($t - 0.55) / 0.45
    $e = 1.0 - [Math]::Pow((1.0 - $u), 3)
    return @{
        Sx = (0.88 + (1.0 - 0.88) * $e)
        Sy = (1.16 + (1.0 - 1.16) * $e)
        Oy = (-9.0 * (1.0 - $e))
    }
}

function Set-LookAt([int]$mx, [int]$my) {
    $cx = 26.0; $cy = 26.0
    $dx = [double]$mx - $cx
    $dy = [double]$my - $cy
    $len = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
    $max = 3.6
    if ($len -lt 0.8) {
        $script:lookTX = 0.0
        $script:lookTY = 0.0
    } else {
        $mag = [Math]::Min($max, $len * 0.18)
        $script:lookTX = ($dx / $len) * $mag
        $script:lookTY = ($dy / $len) * $mag
    }
    Start-AvatarAnim
}

function Start-BounceThenToggle {
    if ($script:bouncing) { return }
    $script:bouncing = $true
    $script:bounceT = 0.0
    $script:pendingToggle = $true
    Start-AvatarAnim
}

function Draw-GrokBotFallback {
    param([System.Drawing.Graphics]$g, [int]$ox, [int]$oy, [int]$disc)
    $scale = $disc / 256.0
    $head = Get-Brush ([System.Drawing.Color]::FromArgb(48, 52, 66))
    $g.FillEllipse($head, $ox, $oy, $disc, $disc); $head.Dispose()
    $plate = Get-Brush ([System.Drawing.Color]::FromArgb(36, 38, 50))
    $rw = New-Object System.Drawing.RectangleF(($ox + 48 * $scale), ($oy + 64 * $scale), (160 * $scale), (144 * $scale))
    $g.FillEllipse($plate, $rw); $plate.Dispose()
    $led = Get-Brush ([System.Drawing.Color]::FromArgb(255, 196, 70))
    $lr = New-Object System.Drawing.RectangleF(($ox + (128 - 9) * $scale), ($oy + (54 - 9) * $scale), (18 * $scale), (18 * $scale))
    $g.FillEllipse($led, $lr); $led.Dispose()
    foreach ($eye in $script:eyes) {
        $sock = Get-Brush ([System.Drawing.Color]::FromArgb(12, 12, 18))
        $sr = New-Object System.Drawing.RectangleF(
            ($ox + ($eye.Cx - $eye.Rx - 7) * $scale),
            ($oy + ($eye.Cy - $eye.Ry - 4) * $scale),
            (($eye.Rx + 7) * 2 * $scale),
            (($eye.Ry + 7) * 2 * $scale))
        $g.FillEllipse($sock, $sr); $sock.Dispose()
        $wht = Get-Brush ([System.Drawing.Color]::FromArgb(248, 249, 252))
        $wr = New-Object System.Drawing.RectangleF(
            ($ox + ($eye.Cx - $eye.Rx) * $scale),
            ($oy + ($eye.Cy - $eye.Ry) * $scale),
            ($eye.Rx * 2 * $scale),
            ($eye.Ry * 2 * $scale))
        $g.FillEllipse($wht, $wr); $wht.Dispose()
    }
    $smilePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 124, 140), [Math]::Max(1.2, 3.2 * $scale))
    $g.DrawArc($smilePen, [single]($ox + 104 * $scale), [single]($oy + 148 * $scale), [single](48 * $scale), [single](30 * $scale), 20, 140)
    $smilePen.Dispose()
}

function Draw-GrokBot([System.Drawing.Graphics]$g) {
    $ox = 4; $oy = 4; $disc = 44
    $sh = Get-Brush ([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
    $g.FillEllipse($sh, 6, 8, 42, 42); $sh.Dispose()
    $under = Get-Brush ([System.Drawing.Color]::FromArgb(40, 42, 54))
    $g.FillEllipse($under, $ox, $oy, $disc, $disc); $under.Dispose()
    $faceW = 256.0
    if ($null -ne $script:faceBmp) {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($script:faceBmp, $ox, $oy, $disc, $disc)
        $faceW = [double]$script:faceBmp.Width
    } else {
        Draw-GrokBotFallback $g $ox $oy $disc
    }
    $scale = $disc / $faceW
    $pr = $script:pupilR * $scale
    foreach ($eye in $script:eyes) {
        $ecx = $ox + $eye.Cx * $scale
        $ecy = $oy + $eye.Cy * $scale
        $erx = $eye.Rx * $scale
        $ery = $eye.Ry * $scale
        $maxX = [Math]::Max(0.0, $erx - $pr - 0.6)
        $maxY = [Math]::Max(0.0, $ery - $pr - 0.6)
        $offX = [Math]::Max(-$maxX, [Math]::Min($maxX, [double]$script:lookX))
        $offY = [Math]::Max(-$maxY, [Math]::Min($maxY, [double]$script:lookY))
        $px = $ecx + $offX
        $py = $ecy + $offY
        $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
        $clip.AddEllipse([single]($ecx - $erx), [single]($ecy - $ery), [single](2.0 * $erx), [single](2.0 * $ery))
        $g.SetClip($clip)
        $pb = Get-Brush ([System.Drawing.Color]::FromArgb(16, 16, 22))
        $prRect = New-Object System.Drawing.RectangleF(($px - $pr), ($py - $pr), (2.0 * $pr), (2.0 * $pr))
        $g.FillEllipse($pb, $prRect); $pb.Dispose()
        $hi = Get-Brush ([System.Drawing.Color]::FromArgb(230, 255, 255, 255))
        $hr = [Math]::Max(0.7, $pr * 0.32)
        $hiRect = New-Object System.Drawing.RectangleF(($px - $pr * 0.45), ($py - $pr * 0.50), (2.0 * $hr), (2.0 * $hr))
        $g.FillEllipse($hi, $hiRect); $hi.Dispose()
        $g.ResetClip()
        $clip.Dispose()
    }
    $ring = New-Object System.Drawing.Pen($cAccent, 1.6)
    $g.DrawEllipse($ring, $ox, $oy, $disc, $disc)
    $ring.Dispose()
}

Import-AvatarFace

$fetchScript = {
    param($url, $token)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if ([string]::IsNullOrEmpty($token)) { return @{ kind = 'env' } }
    $headers = @{ Authorization = "Bearer $token" }
    $attempt = 0
    while ($true) {
        try {
            $r = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 20
            return @{ kind = 'ok'; data = $r }
        } catch {
            $resp = $null
            try { $resp = $_.Exception.Response } catch {}
            if ($null -ne $resp) {
                $code = [int]$resp.StatusCode
                if ($code -eq 401) { return @{ kind = 'unauthorized' } }
                if ($code -eq 503) { return @{ kind = 'not_configured' } }
                if ($code -eq 405) { return @{ kind = 'method' } }
            }
            $attempt++
            if ($attempt -le 2) { Start-Sleep -Seconds 5; continue }
            return @{ kind = 'network' }
        }
    }
}

function Build-TodoItems {
    param($data)
    $out = New-Object System.Collections.ArrayList
    $arr = @($data.items) | Sort-Object { [int]$_.days_left }
    $over = 0
    foreach ($it in $arr) {
        $dl = [int]$it.days_left
        $marker = ''; $color = $cNormal; $urgency = 'normal'; $group = '稍後'
        # groups: 逾期 今日 明日 三日內 稍後 — use literal Unicode escapes carefully
        if ($dl -lt 0) {
            $marker = ('逾期{0}日' -f [Math]::Abs($dl)); $color = $cOverdue; $urgency = 'overdue'; $group = '逾期'; $over++
        }
        elseif ($dl -eq 0) { $marker = '今日'; $color = $cToday; $urgency = 'today'; $group = '今日' }
        elseif ($dl -eq 1) { $marker = '明日'; $color = $cSoon; $urgency = 'soon'; $group = '明日' }
        elseif ($dl -le 3) { $marker = ('餘{0}日' -f $dl); $color = $cSoon; $urgency = 'soon'; $group = '三日內' }
        else { $marker = ('餘{0}日' -f $dl); $color = $cNormal; $urgency = 'normal'; $group = '稍後' }
        $title = if ([string]::IsNullOrWhiteSpace([string]$it.title)) { '(無標題)' } else { [string]$it.title }
        $date = [string]$it.date
        $note = [string]$it.note
        $copyText = "$title`r`n$date"
        if (-not [string]::IsNullOrWhiteSpace($note)) { $copyText += "`r`n$note" }
        [void]$out.Add(@{
            Title = $title; Date = $date; Note = $note; Marker = $marker
            Color = $color; Urgency = $urgency; Group = $group; CopyText = $copyText
        })
    }
    return ,@{ Items = $out; Overdue = $over }
}

function New-SelectableText {
    param([string]$Text, [System.Drawing.Font]$Font, [System.Drawing.Color]$Fore, [System.Drawing.Color]$Back,
          [int]$X, [int]$Y, [int]$W, [int]$H, [switch]$Multiline)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $Text; $tb.Font = $Font; $tb.ForeColor = $Fore; $tb.BackColor = $Back
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tb.ReadOnly = $true; $tb.TabStop = $true; $tb.ShortcutsEnabled = $true
    $tb.Location = New-Object System.Drawing.Point($X, $Y)
    $tb.Size = New-Object System.Drawing.Size($W, $H)
    $tb.Cursor = [System.Windows.Forms.Cursors]::IBeam
    if ($Multiline) { $tb.Multiline = $true; $tb.ScrollBars = 'Vertical'; $tb.WordWrap = $true }
    return $tb
}

function Copy-ToClipboard([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    try { [System.Windows.Forms.Clipboard]::SetText($text) } catch {}
}

$script:cards = New-Object System.Collections.ArrayList
$script:listRows = New-Object System.Collections.ArrayList

function New-CardContextMenu($card) {
    $cm = New-Object System.Windows.Forms.ContextMenuStrip
    $mi1 = New-Object System.Windows.Forms.ToolStripMenuItem('複製本項')
    $mi1.Add_Click({ Copy-ToClipboard ([string]$card.Tag.CopyText) })
    $mi2 = New-Object System.Windows.Forms.ToolStripMenuItem('複製標題')
    $mi2.Add_Click({ Copy-ToClipboard ([string]$card.Tag.Title) })
    $mi3 = New-Object System.Windows.Forms.ToolStripMenuItem('展開／收起')
    $mi3.Add_Click({ Toggle-Card $card })
    [void]$cm.Items.Add($mi1); [void]$cm.Items.Add($mi2); [void]$cm.Items.Add($mi3)
    return $cm
}

function Toggle-Card($card) {
    $tag = $card.Tag
    $tag.Expanded = -not $tag.Expanded
    $tag.Detail.Visible = $tag.Expanded
    $tag.Hint.Text = if ($tag.Expanded) { [char]0x25B2 } else { [char]0x25BC }
    $baseH = 64
    if ($tag.Expanded) {
        $need = 56
        try {
            $sz = [System.Windows.Forms.TextRenderer]::MeasureText(
                [string]$tag.Detail.Text, $tag.Detail.Font,
                (New-Object System.Drawing.Size($tag.Detail.Width, 0)),
                [System.Windows.Forms.TextFormatFlags]::WordBreak)
            $need = [Math]::Max(48, [Math]::Min(120, $sz.Height + 8))
        } catch {}
        $tag.Detail.Height = $need
        $card.Height = $baseH + $need + 8
    } else { $card.Height = $baseH }
    $card.Invalidate(); Layout-Cards
}

function Layout-Cards {
    $y = 4
    foreach ($c in $script:listRows) { $c.Top = $y; $y += $c.Height + 6 }
    $listPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($y + 4))
}

function New-GroupHeader([string]$text, [System.Drawing.Color]$accent) {
    $h = New-Object System.Windows.Forms.Panel
    $h.Width = 368; $h.Height = 22; $h.BackColor = $cBg
    $h.Tag = @{ IsGroup = $true }
    $dot = New-Object System.Windows.Forms.Label
    $dot.Text = [char]0x25CF; $dot.Font = $fontDate; $dot.ForeColor = $accent; $dot.BackColor = $cBg
    $dot.Location = New-Object System.Drawing.Point(10, 4); $dot.AutoSize = $true
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text; $lbl.Font = $fontSub; $lbl.ForeColor = $cMuted; $lbl.BackColor = $cBg
    $lbl.Location = New-Object System.Drawing.Point(26, 4); $lbl.AutoSize = $true
    $h.Controls.Add($dot); $h.Controls.Add($lbl)
    return $h
}

function New-TodoCard {
    param($item)
    $cardW = 368
    $card = New-Object System.Windows.Forms.Panel
    $card.Width = $cardW; $card.Height = 64; $card.BackColor = $cSurface
    $tag = @{
        Expanded = $false; Color = $item.Color; Hover = $false
        Detail = $null; Hint = $null; CopyText = [string]$item.CopyText
        Title = [string]$item.Title; IsGroup = $false
    }
    $card.Tag = $tag
    $cm = New-CardContextMenu $card
    $card.ContextMenuStrip = $cm

    $pillBg = switch ([string]$item.Urgency) {
        'overdue' { $cOverdue }
        'today'   { $cToday }
        'soon'    { $cSoon }
        default   { [System.Drawing.Color]::FromArgb(70, 70, 80) }
    }
    $pillW = [Math]::Max(40, [System.Windows.Forms.TextRenderer]::MeasureText([string]$item.Marker, $fontPill).Width + 10)
    $pill = New-Object System.Windows.Forms.Label
    $pill.Text = [string]$item.Marker; $pill.Font = $fontPill
    $pill.BackColor = $pillBg; $pill.ForeColor = $cBg
    if ([string]$item.Urgency -eq 'normal') { $pill.ForeColor = $cText }
    $pill.TextAlign = 'MiddleCenter'
    $pill.Location = New-Object System.Drawing.Point(12, 8)
    $pill.Size = New-Object System.Drawing.Size($pillW, 16)
    $pr = Get-RoundedPath 0 0 $pillW 16 5
    $pill.Region = New-Object System.Drawing.Region($pr); $pr.Dispose()
    $pill.ContextMenuStrip = $cm
    $card.Controls.Add($pill)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = [char]0x25BC; $hint.Font = $fontDate; $hint.ForeColor = $cFaint; $hint.BackColor = $cSurface
    $hint.TextAlign = 'MiddleCenter'
    $hint.Location = New-Object System.Drawing.Point(($cardW - 28), 6)
    $hint.Size = New-Object System.Drawing.Size(20, 18)
    $hint.Cursor = [System.Windows.Forms.Cursors]::Hand
    $hint.Add_Click({ Toggle-Card $this.Parent })
    $card.Controls.Add($hint); $tag.Hint = $hint

    $title = New-SelectableText -Text ([string]$item.Title) -Font $fontItem -Fore $cText -Back $cSurface -X 12 -Y 28 -W ($cardW - 40) -H 20
    $title.ContextMenuStrip = $cm; $card.Controls.Add($title)

    $date = New-SelectableText -Text ([string]$item.Date) -Font $fontDate -Fore $cMuted -Back $cSurface -X 12 -Y 48 -W ($cardW - 40) -H 14
    $date.ContextMenuStrip = $cm; $card.Controls.Add($date)

    $noteText = if ([string]::IsNullOrWhiteSpace([string]$item.Note)) { '(無備註)' } else { [string]$item.Note }
    $detail = New-SelectableText -Text $noteText -Font $fontDate -Fore $cMuted -Back $cSurface -X 12 -Y 64 -W ($cardW - 24) -H 48 -Multiline
    $detail.Visible = $false; $detail.ContextMenuStrip = $cm
    $card.Controls.Add($detail); $tag.Detail = $detail

    $card.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $w = $this.Width; $h = $this.Height
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $face = if ($this.Tag.Hover) { $cSurface2 } else { $cSurface }
        $body = Get-RoundedPath 0 0 ($w - 1) ($h - 1) 8
        $fb = Get-Brush $face; $g.FillPath($fb, $body); $fb.Dispose()
        $acc = Get-Brush $this.Tag.Color
        $g.FillRectangle($acc, 0, 8, 3, ($h - 16)); $acc.Dispose()
        $pen = New-Object System.Drawing.Pen($cBorder, 1)
        $g.DrawPath($pen, $body); $pen.Dispose(); $body.Dispose()
    })
    $card.Add_MouseEnter({ $this.Tag.Hover = $true; $this.Invalidate() })
    $card.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Invalidate() })
    $card.Add_DoubleClick({ Toggle-Card $this })
    return $card
}

function Set-ListStatus {
    param([string]$text, [System.Drawing.Color]$color)
    $listPanel.Controls.Clear(); $script:cards.Clear()
    if ($script:listRows) { $script:listRows.Clear() }
    if ($text) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $text; $lbl.Font = $fontStatus; $lbl.ForeColor = $color; $lbl.BackColor = $cBg
        $lbl.Location = New-Object System.Drawing.Point(14, 16)
        $lbl.Size = New-Object System.Drawing.Size(340, 40)
        $listPanel.Controls.Add($lbl)
    }
    $todayLabel.Text = ''; $overdueLabel.Text = ''; $overdueLabel.Visible = $false
}

function Render-TodoResult {
    param($result)
    if ($null -eq $result) { Set-ListStatus '攞唔到行程數據' $cError; return }
    switch ($result.kind) {
        'env'            { Set-ListStatus '環境變數 SECRETARY_TODO_TOKEN 未設定' $cError; return }
        'unauthorized'   { Set-ListStatus 'TODO_TOKEN 唔對' $cError; return }
        'not_configured' { Set-ListStatus 'Mac 側未設定 TODO_TOKEN' $cError; return }
        'method'         { Set-ListStatus '端點只支援 GET' $cError; return }
        'network'        { Set-ListStatus '網絡問題（已重試）' $cError; return }
    }
    $data = $result.data
    if ($null -eq $data -or -not $data.ok) { Set-ListStatus '伺服器回應異常' $cError; return }

    $dt = $null
    try { $dt = [datetime]::ParseExact([string]$data.today, 'yyyy-MM-dd', $null) } catch {}
    $dow = @('週日','週一','週二','週三','週四','週五','週六')
    $todayLabel.Text = if ($dt) { "$($dt.Month)/$($dt.Day) $($dow[[int]$dt.DayOfWeek])" } else { '' }

    $built = Build-TodoItems $data
    $listPanel.Controls.Clear(); $script:cards.Clear(); $script:listRows.Clear()
    if ($built.Items.Count -eq 0) {
        Set-ListStatus '未來 7 日內冇未完成待辦' $cMuted
    } else {
        $order = @('逾期','今日','明日','三日內','稍後')
        $grouped = @{}
        foreach ($g in $order) { $grouped[$g] = New-Object System.Collections.ArrayList }
        foreach ($it in $built.Items) { [void]$grouped[$it.Group].Add($it) }
        foreach ($g in $order) {
            if ($grouped[$g].Count -eq 0) { continue }
            $accent = switch ($g) {
                '逾期' { $cOverdue }; '今日' { $cToday }; '明日' { $cSoon }; '三日內' { $cSoon }; default { $cMuted }
            }
            $gh = New-GroupHeader ("{0} · {1}" -f $g, $grouped[$g].Count) $accent
            [void]$script:listRows.Add($gh); $listPanel.Controls.Add($gh)
            foreach ($it in $grouped[$g]) {
                $c = New-TodoCard $it
                [void]$script:cards.Add($c); [void]$script:listRows.Add($c)
                $listPanel.Controls.Add($c)
            }
        }
        Layout-Cards
    }
    if ($built.Overdue -gt 0) {
        $overdueLabel.Text = ("逾期 {0}" -f $built.Overdue)
        $overdueLabel.Visible = $true
        $overdueLabel.Left = $todayLabel.Right + 8
    } else { $overdueLabel.Visible = $false }

    $cntText = ("{0} 項" -f $data.count)
    if ($null -ne $data.undated_count -and [int]$data.undated_count -gt 0) {
        $cntText += (" · 未定日 {0}" -f $data.undated_count)
    }
    $countLabel.Text = $cntText
    $mirrorLabel.Text = ''
    if ($null -ne $data.mirror_age_minutes) {
        $m = [int]$data.mirror_age_minutes
        $age = if ($m -lt 60) { "${m}m" } elseif ($m -lt 1440) { "$([Math]::Floor($m/60))h" } else { "$([Math]::Floor($m/1440))d" }
        $mirrorLabel.Text = "同步 $age"
    }
}

function Update-TodoPanel {
    $countLabel.Text = ''; $mirrorLabel.Text = ''
    Set-ListStatus '載入中…' $cMuted
    if ($script:fetchPS) { try { $script:fetchPS.Dispose() } catch {}; $script:fetchPS = $null }
    $token = $env:SECRETARY_TODO_TOKEN
    if ([string]::IsNullOrEmpty($token)) { $token = [Environment]::GetEnvironmentVariable('SECRETARY_TODO_TOKEN', 'User') }
    $ps = [System.Management.Automation.PowerShell]::Create()
    [void]$ps.AddScript($fetchScript).AddArgument($ApiUrl).AddArgument($token)
    $script:fetchPS = $ps
    $script:fetchHandle = $ps.BeginInvoke()
    $script:fetchTimer.Start()
}

function Toggle-Panel {
    if ($panel.Visible) { $panel.Hide(); return }
    $work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $logo.Left - $panel.Width - 10
    if ($x -lt $work.Left) { $x = $logo.Right + 10 }
    $y = $logo.Top + [int](($logo.Height - $panel.Height) / 2)
    if ($y -lt $work.Top) { $y = $work.Top }
    if (($y + $panel.Height) -gt $work.Bottom) { $y = $work.Bottom - $panel.Height }
    $panel.Location = New-Object System.Drawing.Point($x, $y)
    $panel.Show(); $panel.BringToFront()
    Update-TodoPanel
}

function Launch-Doubao {
    if (Test-Path -LiteralPath $DoubaoExe) {
        Start-Process -FilePath $DoubaoExe | Out-Null
    } else {
        [void][System.Windows.Forms.MessageBox]::Show("搵唔到豆包：$DoubaoExe", '浮動待辦')
    }
}

$logo = New-Object System.Windows.Forms.Form
$logo.FormBorderStyle = 'None'
$logo.StartPosition = 'Manual'
$logo.ShowInTaskbar = $false
$logo.TopMost = $true
$logo.AllowTransparency = $true
$logo.BackColor = $cKey
$logo.TransparencyKey = $cKey
$logo.Size = New-Object System.Drawing.Size(56, 56)
$work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$logo.Location = New-Object System.Drawing.Point(($work.Right - 68), ($work.Bottom - 68))
$logo.Cursor = [System.Windows.Forms.Cursors]::Hand

$logo.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $xf = @{ Sx = 1.0; Sy = 1.0; Oy = 0.0 }
    if ($script:bouncing) { $xf = Get-BounceXform ([double]$script:bounceT) }
    $cx = 26.0
    $cy = 26.0
    $state = $g.Save()
    $g.TranslateTransform([single]$cx, [single]($cy + $xf.Oy))
    $g.ScaleTransform([single]$xf.Sx, [single]$xf.Sy)
    $g.TranslateTransform([single](-$cx), [single](-$cy))
    Draw-GrokBot $g
    $g.Restore($state)
})

$script:dragStart = $null; $script:dragging = $false
$logo.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:dragStart = $e.Location; $script:dragging = $false }
})
$logo.Add_MouseMove({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $null -ne $script:dragStart) {
        $dx = $e.X - $script:dragStart.X; $dy = $e.Y - $script:dragStart.Y
        if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 4) { $script:dragging = $true }
        if ($script:dragging) { $logo.Location = New-Object System.Drawing.Point(($logo.Left + $dx), ($logo.Top + $dy)) }
    }
    $script:hovering = $true
    Set-LookAt $e.X $e.Y
})
$logo.Add_MouseEnter({
    $script:hovering = $true
    Start-AvatarAnim
})
$logo.Add_MouseLeave({
    $script:hovering = $false
    $script:lookTX = 0.0
    $script:lookTY = 0.0
    Start-AvatarAnim
})
$logo.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $was = $script:dragging; $script:dragging = $false; $script:dragStart = $null
        if (-not $was) { Launch-Doubao }
    } elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        Start-BounceThenToggle
    }
})
$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($logo, "左鍵：開豆包`n右鍵：彈跳後開 7 日待辦`n拖曳：移動`n懸停：眼睛跟隨`n面板可選取／Ctrl+C／右鍵複製")

$script:animTimer = New-Object System.Windows.Forms.Timer
$script:animTimer.Interval = 16
$script:animTimer.Add_Tick({
    $dirty = $false
    $doToggle = $false
    if ($script:bouncing) {
        $script:bounceT = [double]$script:bounceT + 0.058
        $dirty = $true
        if ($script:bounceT -ge 1.0) {
            $script:bounceT = 0.0
            $script:bouncing = $false
            $doToggle = [bool]$script:pendingToggle
            $script:pendingToggle = $false
        }
    }
    $ldx = [double]$script:lookTX - [double]$script:lookX
    $ldy = [double]$script:lookTY - [double]$script:lookY
    if ([Math]::Abs($ldx) -gt 0.04 -or [Math]::Abs($ldy) -gt 0.04) {
        $script:lookX = [double]$script:lookX + ($ldx * 0.38)
        $script:lookY = [double]$script:lookY + ($ldy * 0.38)
        $dirty = $true
    } elseif ([Math]::Abs($ldx) -gt 0.0 -or [Math]::Abs($ldy) -gt 0.0) {
        $script:lookX = [double]$script:lookTX
        $script:lookY = [double]$script:lookTY
        $dirty = $true
    }
    if ($dirty) { $logo.Invalidate() }
    if ($doToggle) { Toggle-Panel }
    $lookSettled = ([Math]::Abs(([double]$script:lookX) - ([double]$script:lookTX)) -lt 0.03) -and ([Math]::Abs(([double]$script:lookY) - ([double]$script:lookTY)) -lt 0.03)
    if (-not $script:bouncing -and $lookSettled) {
        $script:animTimer.Stop()
    }
})
$logo.Add_FormClosed({
    if ($script:animTimer) { try { $script:animTimer.Stop(); $script:animTimer.Dispose() } catch {} }
    if ($script:faceBmp) { try { $script:faceBmp.Dispose() } catch {}; $script:faceBmp = $null }
})

$PanelW = 392; $PanelH = 480; $HeaderH = 52; $FooterH = 44

$panel = New-Object System.Windows.Forms.Form
$panel.FormBorderStyle = 'None'
$panel.StartPosition = 'Manual'
$panel.ShowInTaskbar = $false
$panel.TopMost = $true
$panel.BackColor = $cBg
$panel.Size = New-Object System.Drawing.Size($PanelW, $PanelH)
$panel.KeyPreview = $true
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$d = 14
$path.AddArc(0, 0, $d, $d, 180, 90)
$path.AddArc(($PanelW - $d), 0, $d, $d, 270, 90)
$path.AddArc(($PanelW - $d), ($PanelH - $d), $d, $d, 0, 90)
$path.AddArc(0, ($PanelH - $d), $d, $d, 90, 90)
$path.CloseFigure()
$panel.Region = New-Object System.Drawing.Region($path)

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size($PanelW, $HeaderH)
$header.BackColor = $cBg
$header.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawLine($pen, 12, ($HeaderH - 1), ($PanelW - 12), ($HeaderH - 1))
    $pen.Dispose()
})
$panel.Controls.Add($header)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = '未來 7 日'; $titleLabel.ForeColor = $cText; $titleLabel.Font = $fontTitle
$titleLabel.BackColor = $cBg; $titleLabel.Location = New-Object System.Drawing.Point(14, 8)
$titleLabel.Size = New-Object System.Drawing.Size(160, 22); $titleLabel.AutoSize = $false
$header.Controls.Add($titleLabel)

$todayLabel = New-Object System.Windows.Forms.Label
$todayLabel.ForeColor = $cMuted; $todayLabel.Font = $fontSub; $todayLabel.BackColor = $cBg
$todayLabel.Location = New-Object System.Drawing.Point(16, 30); $todayLabel.AutoSize = $true
$header.Controls.Add($todayLabel)

$overdueLabel = New-Object System.Windows.Forms.Label
$overdueLabel.ForeColor = $cOverdue; $overdueLabel.Font = $fontSub; $overdueLabel.BackColor = $cBg
$overdueLabel.Location = New-Object System.Drawing.Point(120, 30); $overdueLabel.AutoSize = $true
$overdueLabel.Visible = $false
$header.Controls.Add($overdueLabel)

$refreshLbl = New-Object System.Windows.Forms.Label
$refreshLbl.Text = '重整'; $refreshLbl.ForeColor = $cAccent; $refreshLbl.Font = $fontSub
$refreshLbl.BackColor = $cBg; $refreshLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
$refreshLbl.Location = New-Object System.Drawing.Point(($PanelW - 78), 16); $refreshLbl.AutoSize = $true
$refreshLbl.Add_Click({ Update-TodoPanel })
$refreshLbl.Add_MouseEnter({ $refreshLbl.ForeColor = $cSoon })
$refreshLbl.Add_MouseLeave({ $refreshLbl.ForeColor = $cAccent })
$header.Controls.Add($refreshLbl)

$closeLbl = New-Object System.Windows.Forms.Label
$closeLbl.Text = 'X'; $closeLbl.ForeColor = $cFaint; $closeLbl.Font = $fontSub
$closeLbl.BackColor = $cBg; $closeLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
$closeLbl.Location = New-Object System.Drawing.Point(($PanelW - 28), 14)
$closeLbl.Size = New-Object System.Drawing.Size(18, 18); $closeLbl.TextAlign = 'MiddleCenter'
$closeLbl.Add_Click({ $panel.Hide() })
$closeLbl.Add_MouseEnter({ $closeLbl.ForeColor = $cText })
$closeLbl.Add_MouseLeave({ $closeLbl.ForeColor = $cFaint })
$header.Controls.Add($closeLbl)

$panel.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $panel.Hide() }
})

$listPanel = New-Object System.Windows.Forms.Panel
$listPanel.Location = New-Object System.Drawing.Point(8, $HeaderH)
$listPanel.Size = New-Object System.Drawing.Size(($PanelW - 12), ($PanelH - $HeaderH - $FooterH))
$listPanel.BackColor = $cBg
$listPanel.AutoScroll = $true
$listPanel.HorizontalScroll.Enabled = $false
$listPanel.HorizontalScroll.Visible = $false
$panel.Controls.Add($listPanel)

$footer = New-Object System.Windows.Forms.Panel
$footer.BackColor = $cBg
$footer.Location = New-Object System.Drawing.Point(0, ($PanelH - $FooterH))
$footer.Size = New-Object System.Drawing.Size($PanelW, $FooterH)
$footer.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($cBorder, 1)
    $e.Graphics.DrawLine($pen, 12, 0, ($PanelW - 12), 0)
    $pen.Dispose()
})
$panel.Controls.Add($footer)

$countLabel = New-Object System.Windows.Forms.Label
$countLabel.Font = $fontSub; $countLabel.ForeColor = $cMuted; $countLabel.BackColor = $cBg
$countLabel.Location = New-Object System.Drawing.Point(14, 6)
$countLabel.Size = New-Object System.Drawing.Size(160, 16)
$footer.Controls.Add($countLabel)

$mirrorLabel = New-Object System.Windows.Forms.Label
$mirrorLabel.Font = $fontDate; $mirrorLabel.ForeColor = $cFaint; $mirrorLabel.BackColor = $cBg
$mirrorLabel.Location = New-Object System.Drawing.Point(14, 24)
$mirrorLabel.Size = New-Object System.Drawing.Size(160, 14)
$footer.Controls.Add($mirrorLabel)

function New-FooterBtn([string]$text, [int]$x, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $cBorder
    $b.FlatAppearance.MouseOverBackColor = $cSurface2
    $b.BackColor = $cSurface; $b.ForeColor = $cText; $b.Font = $fontSub
    $b.Size = New-Object System.Drawing.Size(64, 26)
    $b.Location = New-Object System.Drawing.Point($x, 9)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_Click($onClick)
    return $b
}

$copyAllBtn = New-FooterBtn '複製全部' ($PanelW - 150) ({
    $buf = New-Object System.Text.StringBuilder
    foreach ($c in $script:cards) {
        if ($c.Tag -and $c.Tag.CopyText) {
            [void]$buf.AppendLine([string]$c.Tag.CopyText)
            [void]$buf.AppendLine('-')
        }
    }
    Copy-ToClipboard ($buf.ToString().Trim())
    $mirrorLabel.Text = '已複製'
})
$footer.Controls.Add($copyAllBtn)

$exitBtn = New-FooterBtn '離開' ($PanelW - 78) ({ [System.Windows.Forms.Application]::Exit() })
$footer.Controls.Add($exitBtn)

$panel.Add_FormClosing({
    param($s, $e)
    if ($script:fetchTimer) { $script:fetchTimer.Stop() }
    if ($script:fetchPS) { try { $script:fetchPS.Dispose() } catch {} }
})

$script:fetchTimer = New-Object System.Windows.Forms.Timer
$script:fetchTimer.Interval = 250
$script:fetchTimer.Add_Tick({
    if ($null -ne $script:fetchHandle -and $script:fetchHandle.IsCompleted) {
        $script:fetchTimer.Stop()
        $result = $null
        try { $result = $script:fetchPS.EndInvoke($script:fetchHandle) } catch {}
        if ($script:fetchPS) { $script:fetchPS.Dispose(); $script:fetchPS = $null }
        $script:fetchHandle = $null
        Render-TodoResult $result
    }
})

$script:panelShownOnce = $false
try {
    [void][System.Windows.Forms.Application]::Idle.Add({
        if (-not $script:panelShownOnce) {
            $script:panelShownOnce = $true
            if (-not $panel.Visible) { Toggle-Panel }
        }
    })
} catch {}

$logo.Show()
Toggle-Panel

if ($Preview) {
    $script:prevDone = $false
    $prevTimer = New-Object System.Windows.Forms.Timer
    $prevTimer.Interval = 1600
    $prevTimer.Add_Tick({
        if ($script:prevDone) { $prevTimer.Stop(); return }
        $script:prevDone = $true
        $mock = @{
            ok = $true; today = '2026-09-17'; count = 3
            items = @(
                @{ title = '交回校務通告簽署'; date = '2026-09-15'; days_left = -2; note = '已過限期請盡快補交' }
                @{ title = '設立校友會 group + 幹事會議'; date = '2026-09-18'; days_left = 1; note = '9月18日下午會議室' }
                @{ title = 'DSE 中六級第一次成績估算'; date = '2026-09-22'; days_left = 5; note = '限期22/9下午4時前' }
            )
            undated_count = 0; mirror_age_minutes = 12
        }
        Render-TodoResult @{ kind = 'ok'; data = $mock }
        for ($i = 0; $i -lt 10; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
        $b1 = New-Object System.Drawing.Bitmap($PanelW, $PanelH)
        $panel.DrawToBitmap($b1, (New-Object System.Drawing.Rectangle(0, 0, $PanelW, $PanelH)))
        $b1.Save((Join-Path $PSScriptRoot '面板預覽_v20深色摺疊.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        $b1.Dispose()
        if ($script:cards.Count -gt 0) { Toggle-Card $script:cards[0] }
        for ($i = 0; $i -lt 10; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
        $b2 = New-Object System.Drawing.Bitmap($PanelW, $PanelH)
        $panel.DrawToBitmap($b2, (New-Object System.Drawing.Rectangle(0, 0, $PanelW, $PanelH)))
        $b2.Save((Join-Path $PSScriptRoot '面板預覽_v20深色展開.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        $b2.Dispose()
        $bi = New-Object System.Drawing.Bitmap(56, 56)
        $logo.DrawToBitmap($bi, (New-Object System.Drawing.Rectangle(0, 0, 56, 56)))
        $bi.Save((Join-Path $PSScriptRoot '浮動頭_v21.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        $bi.Dispose()
        [System.Windows.Forms.Application]::Exit()
    })
    $prevTimer.Start()
}

[void][System.Windows.Forms.Application]::Run($logo)
