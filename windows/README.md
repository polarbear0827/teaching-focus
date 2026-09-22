# TeachingFocus Windows

繁體中文教學聚光燈與凍結畫筆，功能以 Mac v1.0.0-beta.7 為基準。

## 下載與啟動

相容目標：**Windows 10 22H2／Windows 11，Intel／AMD x64**。

從 [Windows 預覽 Release](https://github.com/polarbear0827/teaching-focus/releases/tag/v1.1.0-windows-beta.1) 下載 ZIP，先解壓整個資料夾，再執行 `TeachingFocus.exe`。已包含 .NET 執行環境，不需另外安裝 .NET、不需要安裝精靈，也不會安裝服務或設定開機啟動。

右下角通知區會出現雙圈游標圖示，可能收在「顯示隱藏圖示」內。雙擊圖示開啟設定。重複執行會開啟既有設定，不再新增一份程式。

**這是未進行 Windows 實機驗收的預覽版。** 已完成交叉編譯與封裝檢查；未執行 Windows 功能、投影或長時間測試。EXE 未進行 Authenticode 簽署，Windows 可能顯示未識別發行者／SmartScreen 提示；請先核對下載來源與 SHA-256，企業限制請依管理者規定處理。

## 上課操作

- 雙按 Ctrl，或 `Ctrl＋Alt＋S`：切換聚光燈。
- `Ctrl＋Alt＋D`：凍結游標所在螢幕；背景程式與影片仍會繼續。
- 凍結後點邊緣的懸浮球，選畫筆、直線、箭頭、矩形、橢圓或雷射筆。
- 數字 1～5：紅、藍、綠、黑、白。`Ctrl＋Z` 復原，`Ctrl＋Shift＋Z` 重做。
- 球可拖曳，移動超過 4 點才視為拖曳，放開後貼邊並分螢幕記住位置。
- 選工具、顏色、粗細時面板保持開啟；點球、短按 Esc 或點面板外收起。
- 面板外的第一次點擊只收起面板，不畫線或點擊底下程式。
- 長按 Esc 到設定時間（預設 3 秒）或按「結束講解」，清除並返回即時畫面。
- 單純開著光圈、漣漪或粒子，不會攔截平常的 Esc。

通知區選單提供「暫停／繼續」。暫停會清除畫布、關閉效果、停止輸入監聽及快捷鍵，設定仍保留。關閉設定視窗不會退出工具；完全退出請用通知區的「結束工具」。

## 可調設定

- 聚光燈半徑、遮暗、外框顏色／粗細／發光；收縮動畫 0.1～1 秒，預設 0.25 秒。
- 光圈顏色、半徑 6～80 點、不透明度 0～100%，預設 30%；提供淺／深背景預覽。
- 漣漪與粒子可獨立開關。粒子有光點、短線火花、小星芒及五級強度，預設關閉、強度 2；跨螢幕合計最多八組，淡出後釋放。
- Windows 關閉動畫時略過收縮與粒子飛散；漣漪可繼續使用。
- Esc 長按時間 0.5～10 秒。
- 快捷鍵：點「錄製」→ 按組合鍵 →「儲存」。支援 Ctrl 或 Alt 搭配字母、數字或 F1～F11，可加 Shift。Esc 取消；重複、保留組合或系統註冊失敗時不覆蓋原設定。
- 「還原預設設定」確認後重設上述偏好與懸浮球位置、清除畫布，保留暫停狀態。

## 設定與限制

設定存於 `%LOCALAPPDATA%\TeachingFocus\settings.json`，不跟著 EXE 資料夾移動。程式以具版本號的 JSON 與同資料夾原子替換保存；損壞的原設定先備份，再使用預設值。設定寫入失敗會在設定頁顯示。

畫面快照只存在記憶體，退出凍結即釋放，不會上傳或寫入磁碟。首次啟動單檔版時，.NET 可能將原生程式庫解出至使用者暫存目錄，這不會安裝系統服務。

鏡像與延伸桌面按 Windows 螢幕配置處理。不同 DPI 的實際操作對位、全螢幕簡報與插拔／休眠行為留待實機驗收。UAC 安全桌面、受保護影片、獨佔全螢幕及提升權限的程式不在第一版支援承諾內。會議軟體分享整個桌面才能包含覆蓋效果，單一視窗分享由該軟體決定。

## 從原始碼建置

需要 .NET 10 SDK；一般使用者下載 ZIP 不需要 SDK。

Windows PowerShell：

```powershell
./windows/publish.ps1
```

或在支援 .NET 10 的開發環境執行：

```sh
dotnet publish windows/TeachingFocus.Windows/TeachingFocus.Windows.csproj -c Release -r win-x64 --self-contained true -o windows/dist/win-x64
```

`EnableWindowsTargeting` 允許從 macOS／Linux 交叉編譯，不能因此宣稱 Windows 實機測試通過。

程式分為 `TeachingFocus.Core`（狀態與設定）、`TeachingFocus.Windows`（WPF／Win32 整合），既有 `TeachingFocus.Checks` 骨架留待之後驗收擴充；本次未執行測試。
