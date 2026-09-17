# Changelog — 豆包浮動待辦

## v3.0.2 — 浮動頭 layered blit ＋ 列表滾到頂空白

視覺同行為維持 v3.0 Dusk Ledger。v3.0.1 喺 Windows 實測：指住頭仍然閃；展開後滾到頂會留大片空白。

### 浮動頭仍然閃
v3.0.1 `SpriteForm` + `TransparencyKey` Magenta + 全窗 `Invalidate` 唔夠：color-key 每次重繪先打成洋紅洞再畫，hover／look-at 仍然閃白／閃洋紅。

**修法**
- 棄用 Magenta color-key。`LayeredForm` 用 `WS_EX_LAYERED` + `UpdateLayeredWindow`（`ULW_ALPHA`、premultiplied 32bpp）真透明。
- 靜態臉 cache（`baseSprite`）+ 只重畫瞳孔層；timer 只喺 look／bounce 真係變先 blit，**唔** `Invalidate`、**唔**每像素 MouseMove 重繪。
- `pptDst = NULL`，位置交俾 `Form.Location`，避免 layered blit 同拖曳搶座標。
- 跳過 `WM_ERASEBKGND`／空 `OnPaint`，唔同 `SetLayeredWindowAttributes` 混用。

### 滾到頂大片空白
v3.0.1 對 AutoScroll **同一個** panel 嘅子控件設 `Top`，再設 `AutoScrollMinSize`。滾動中 WinForms 會把 scroll offset 寫入 `Top`；滾回頂時第一張卡 `Top` 仍然好大。

**修法**
- `listPanel`（AutoScroll）只得一個子控件 `listCanvas`。
- group／card 嘅 `Top` 相對 canvas（由 0 排），唔再相對 scroll panel。
- `AutoScrollMinSize = (0, canvas.Height)`：虛擬高度跟內容高度，**唔**用 scrolled 時嘅 `child.Bottom`（會縮 scroll range）。
- `Layout-Cards` 唔改 `canvas.Location`（交俾 AutoScroll）；重置／狀態列先歸零。

### 點樣測（Windows）
Linux cloud VM 跑唔到 WinForms。

```powershell
cd doubao-floating-todo
powershell -File .\豆包浮動待辦.ps1
```

1. 滑鼠停喺浮動頭、慢慢郁、離開：冇閃白／閃洋紅／整粒頭跳閃；眼睛仍跟隨。
2. 左鍵開豆包、拖曳、右鍵 bounce 後 Toggle-Panel 同前。
3. 打開面板，展開幾張卡，向下滾再滾返最頂：第一個 group／card 貼齊列表頂，冇大片空 canvas。
4. 重整／複製／離開／`-Preview` 同 v3.0。

---

## v3.0.1 — 修閃動（卡片 hover ＋ 浮動頭）

視覺同行為維持 v3.0 Dusk Ledger，只修 WinForms 閃白／閃爍。

### 原因
1. **卡片**：滑鼠經過 TextBox／Label 時父 Panel 不停 `MouseLeave`→`MouseEnter`；每次 hover 改一堆 `BackColor` 再 `Invalidate`，無雙緩衝就會閃。
2. **浮動頭**：`TransparencyKey` 窗每次 `Invalidate` 先擦成洋紅（變透明空洞）再重畫；再加每幀 HighQuality 縮 256px PNG，look-at timer 幾乎唔停。

### 修法
- `SmoothPanel`：`OptimizedDoubleBuffer` + `WS_EX_COMPOSITED`，卡片同子控件一次合成。
- Hover：子控件都接 Enter／Leave；Leave 時若游標仍在卡片內就唔取消 hover；狀態冇變就 return；唔再多餘 `Invalidate`。
- `SpriteForm`：跳過 `OnPaintBackground`／`WM_ERASEBKGND`；Paint 內 `Clear(Magenta)` 一次畫完。**唔**對 color-key 窗開 double-buffer（反而會閃黑）。
- 預縮 `ember_spirit_face.png` 到 52px cache；look-at 量化＋拖曳時唔跟眼；timer 20ms。
- 面板／列表／header／footer 反射開 DoubleBuffered。

### 點樣測（Windows）
滑鼠喺卡片之間快速掃、停喺標題上、進出面板；滑過／離開浮動頭、眼睛跟隨、右鍵 bounce。應冇明顯閃白／內容跳動。

---

## v3.0 — Dusk Ledger（暮色手帳）全面重設

唔係換皮：色票、字級、間距、卡片結構、header 層次、按鈕形態、浮動角色全部重做。行為同 API 合約維持。

### Design 決策

**系統名：Dusk Ledger（暮色手帳）**  
桌面秘書＝黃昏書檯上的手帳，唔係「深灰底＋琥珀 pill」。

| Token | Hex / RGB | 用途 |
| --- | --- | --- |
| Canvas | `#0B0C12` | 面板夜色畫布 |
| Surface / Raised / Hover | `#151821` / `#1C2030` / `#242A3C` | 票卡層次 |
| Text | `#F4EEE6` | 暖象牙，唔用冷灰白 |
| Ember | `#E8956A` | 銅桃強調（重整、主按鈕、頭像光環） |
| Rose / Honey / Slate | `#E56B7D` / `#E8B86D` / `#7B8498` | 逾期／近／稍後 |

**結構（對比 v2.x）**
- Header 由「標題為主」改成 **日曆主視覺**：細 kicker「未來七日」＋巨大日期數字＋「9月 · 週四」；ember 短劃在日期下。逾期變成 **chip**，唔再係標題旁細字。
- 卡片由「色條＋實心 pill＋標題＋ISO 日期」改成 **日期軌票卡**：左欄日／月、右欄標題為主；緊急度改 **ghost chip**（色字＋深底），標題不再被 pill 壓住。
- 分組：色塊標記＋名稱＋右側數量 chip，唔再用「圓點 · 逾期 · 1」。
- Footer：**膠囊按鈕**；複製全部用 ember 描邊作 primary。
- 圓角加大（面板 ~20px、卡片 ~12px）、列表 padding 14–16、卡片高 76。

**浮動頭：Ember 暮火精靈（全新角色）**
- 唔再用琥珀色「7」、橘貓、或 v2.1 冷金屬機械人（額燈／耳／金屬面）。
- 靛藍紫 dumpling／精靈、底部銅桃肚光、腮紅、奶油大眼（PNG **冇瞳孔**，GDI+ 疊加 look-at）。
- Form **64×64**（內容圓 ~52，未超過 72）。右鍵仍 squash／bounce 後 `Toggle-Panel`。
- 資產：`assets/ember_spirit_face.png`；缺檔有 GDI+ fallback。

### 保留行為
左鍵開豆包、右鍵 bounce→面板、拖曳、look-at、GET `/api/todo7` + token、分組、展開備註、選取／複製／複製全部、重整、離開、`-Preview`、UTF-8 BOM、唯讀。

### 點樣測（Windows）
Linux cloud VM 跑唔到 WinForms。

```powershell
cd doubao-floating-todo
powershell -File .\豆包浮動待辦.ps1
```

1. 浮動頭係暮火精靈，唔係「7」亦唔係機械人。
2. 懸停眼睛跟隨；離開回中。
3. 右鍵先彈再開關面板。
4. 面板：大日期 header、左欄日曆數字、ghost chip、暖夜色。
5. 展開／複製／重整／離開同前。
6. 可選 `-Preview` → `面板預覽_v30摺疊.png`、`面板預覽_v30展開.png`、`浮動頭_v30.png`。

離線合成（本目錄／artifacts）：`assets/preview_panel_folded.png`、`assets/preview_panel_expanded.png`。

### 檔案
- `豆包浮動待辦.ps1`（UTF-8 BOM）
- `assets/ember_spirit_face.png`
- `assets/preview_panel_folded.png` / `preview_panel_expanded.png`
- `CHANGELOG.md`

---

## v2.1 — Grok Bot 浮動頭

（已被 v3.0 Ember 精靈取代。v2.1 只改浮動頭、面板維持 v2.0 琥珀緊湊卡。）
