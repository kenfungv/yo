# Changelog — 豆包浮動待辦

## v2.1 — Grok Bot 浮動頭

### 改咗咩
- 浮動圖標由琥珀色圓碟「7」改成 **Grok Bot 風格圓形頭像**（深色機械人頭、大白眼、額上琥珀 LED、細微笑）。Form 仍係 56×56，內容圓約 44px。
- **懸停／在圖標上移動滑鼠**：瞳孔跟住游標方向微移（look-at），離開後回中。
- **右鍵**：頭像先做短暫 squash／bounce（約 0.3s，Timer 唔阻塞 UI），動畫完先呼叫原本嘅 `Toggle-Panel`。
- **左鍵／拖曳不變**：左鍵開豆包、拖曳移動。
- 面板深色＋琥珀 UI、卡片展開／複製、秘書 `GET /api/todo7` 同 token 流程 **完全冇改**。

### 資產
- `assets/grok_bot_face.png` — 256×256 透明底圓形臉（眼白、**冇瞳孔**），離線用。腳本用 GDI+ 疊瞳孔。
- 若 PNG 唔見，會用內建 GDI+ fallback 畫同一套幾何，仍然可跑。

### 點樣測（Windows 桌面）
WinForms 喺呢個 Linux cloud VM 跑唔到；請喺 Windows PowerShell 5.1+ 測：

```powershell
powershell -File .\豆包浮動待辦.ps1
```

1. 浮動頭應係 Grok Bot，唔再係「7」。
2. 滑鼠喺頭上移動：兩隻眼睛跟住睇。
3. 移開滑鼠：瞳孔回中。
4. 右鍵：先彈一下，然後先開／收 7 日待辦面板（配色／卡片同 v2.0）。
5. 左鍵仍開豆包；拖曳仍可移動圖標。
6. 可選：`powershell -File .\豆包浮動待辦.ps1 -Preview` 會截 `浮動頭_v21.png` 同原本嘅面板預覽圖。

### 檔案
- `豆包浮動待辦.ps1`（UTF-8 BOM）
- `assets/grok_bot_face.png`
- `CHANGELOG.md`
