# 教學聚光燈 TeachingFocus

![App icon](Assets/AppIcon.png)

Mac 原生教學畫筆與聚光燈。目標：macOS 13+、Apple Silicon。Windows 不在本次交付範圍。

## 啟動

建議先到 GitHub Releases 下載 DMG 或解壓 ZIP，將 `TeachingFocus.app` 放入「應用程式」後開啟；選單列出現「◎ 教學」。可將 app 複製至「應用程式」後固定使用，避免更換路徑造成權限需要重設。

首次使用到「系統設定 → 隱私權與安全性」允許本 app 的「輔助使用」與「螢幕錄製」（部分系統名稱包含系統音訊）；本程式不擷取音訊。授權後請退出並重新開啟。選單列「權限與使用說明」可開啟對應設定。

這是本機 ad-hoc 簽章版，尚未 Developer ID 簽章及公證。其他 Mac 可能需要在系統設定「隱私權與安全性」允許開啟；不要關閉系統安全機制。

## 上課操作

1. 雙按 Control 開關聚光燈；也可用 Control＋Option＋S。
2. 游標移到欲講解的螢幕，按 Control＋Option＋D 凍結。
3. 工具列選畫筆、直線、箭頭、矩形、橢圓或雷射筆，選色與粗細。
4. 數字 1–5 對應紅、藍、綠、黑、白；Command＋Z 復原，Command＋Shift＋Z 重做。
5. 「清除全部」只清除畫布；長按 Esc 3 秒或「結束講解」清除並返回即時畫面。短按 Esc 不退出。
6. 回到即時畫面後，再點擊真正的按鈕。

凍結不會暫停背景影片或程式。每次凍結都是新畫布。工具列標題列可拖移。延伸桌面只凍結游標所在螢幕。

## 設定

選單列「設定」提供半徑、遮暗程度、螢光線寬、發光強度、外框色、光圈與波紋開關。快捷鍵可在 Control＋Option＋D/S/F/G 中選擇；不可重複。可停用雙按 Control，改用組合鍵。

預設半徑 120 邏輯點、遮暗 60%、青藍外框 3 點、外暈 12 點；設定保存在 macOS UserDefaults。

## 建置與測試

需要 Apple Command Line Tools / Swift 5.9 或以上：

```sh
./scripts/build-app.sh
```

腳本編譯 arm64 release、建立相鄰的 `.app`、進行本機簽章驗證並執行 CoreChecks。CoreChecks 使用獨立 executable 測試框架，因此不依賴 XCTest 執行環境。執行 `./scripts/test.sh` 可重跑核心及繪圖測試；加上 `--live` 可檢查真實畫面擷取。完整測試狀態請看交付的 TEST_REPORT.md。

## 隱私與限制

畫面只存記憶體，退出凍結即釋放，不寫入磁碟、不上傳。受保護影片或系統安全畫面可能無法擷取；線上會議若只分享單一應用程式視窗，不一定包含本工具覆蓋層，請分享整個螢幕並先試播。

## GitHub 預覽版本

Repository：<https://github.com/polarbear0827/teaching-focus>（公開）。

下載：<https://github.com/polarbear0827/teaching-focus/releases>。DMG 開啟後，將 TeachingFocus 拖入 Applications。ZIP 與 DMG 內的程式相同。

目前為 `v1.0.0-beta.2` 預覽版。**只有 ad-hoc 本機簽章；尚未 Developer ID 簽署或 Apple 公證，Gatekeeper 評估為 rejected。** 請見 [簽章報告](SIGNING_REPORT.md)。若系統阻擋，確認來源與 SHA-256 後，可由使用者在系統設定依 macOS 提示允許開啟；不要停用 Gatekeeper。

本版已加入無文字游標角色與螢光聚光燈 icon。YEYE 未提供特定參考圖，本圖為圓潤俏皮的原創視覺方向。
