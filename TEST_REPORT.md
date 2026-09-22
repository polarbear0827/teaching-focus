# TeachingFocus v1.0.0-beta.2 測試報告

日期：2026-09-22。結論：**已產出可試用版本；尚未完成全部現場驗收。**

## 環境與範圍

- MacBook Air、Apple M4、24 GB RAM；macOS 26.6.2（25G83）。
- Swift 6.4，arm64 Release；Mach-O 最低系統版本為 macOS 13.0。
- 內建 Retina 邏輯尺寸 1470×956、scale 2；TYPE-C 960×640、scale 1；DELL P2717H 1920×1080、scale 1。三螢幕採延伸桌面。
- 最終執行檔 SHA-256：`cda6ed07279c742f1d41d7ebeaa8c56ae675b32a737d31bb982cda21585c7e9e`。
- 程式由命令列開發環境啟動時，診斷顯示輔助使用與畫面擷取均可用；此結果不能替代使用者雙擊啟動後的獨立 TCC 權限驗收。

## 自動測試

| 項目／步驟 | 預期 | 實際 | 狀態／證據 |
|---|---|---|---|
| Release 編譯並建立 app | arm64 可執行檔 | 成功；僅 CLT 缺少非必要搜尋目錄的 linker warning | PASS，evidence/core-checks.log |
| Control 單按、雙按、超時、長按與組合鍵 | 正確觸發且不誤觸 | 通過，包括先放開 Option 的回歸案例 | PASS，同上 |
| Esc 2.9 秒、3 秒、重複按下、提早放開 | 3 秒前不執行，完成一次，放開歸零 | 通過虛擬時鐘測試 | PASS，同上 |
| 復原、重做、分支歷史與清除 | 歷史狀態正確 | 通過 | PASS，同上 |
| 負座標螢幕換算 | 邏輯座標正確 | 通過單一負座標案例，非完整多螢幕矩陣 | PASS，同上 |
| 六種工具 × 五色離屏渲染 | 各組合可產生筆跡像素 | 30 組通過；不代表人眼五色辨識或雷射時間驗證 | PASS，evidence/render-checks.log |
| 聚光燈中心、背景與外框 | 中心透明、遮暗 60%、外框有像素 | 三項通過 | PASS，同上 |
| 100 次模擬畫布重設 | 無快照及歷史殘留 | 通過；不是 100 次真實凍結／UI 循環 | PASS，同上 |
| 三螢幕真實 ScreenCaptureKit 擷取 | 尺寸正確、取得有效 frame | 2940×1912、960×640、1920×1080 均通過 | PASS，evidence/capture-checks.log |
| 擷取時間 | 每次 <1 秒 | 最終一次各約 0.182、0.083、0.102 秒 | PASS，僅擷取 API 時間，不含 UI 首幀延遲 |
| ZIP 解壓到 /tmp 後驗簽及執行 | 不依賴開發目錄，可通過繪圖測試 | 本機簽章有效，34 項繪圖檢查通過 | PASS，evidence/packaged-render-checks.log；執行檔 hash 見本報告環境段落 |

核心測試共 **17 項**；離屏繪圖／重設測試共 **34 項**。測試程式採 executable assertions，失敗時非零退出，不依赖 XCTest。

## 實機 UI 觀察

| 情境 | 實際觀察 | 狀態 |
|---|---|---|
| 啟動 `.app` | 能建立原生選單列程式及設定視窗 | PASS |
| 設定排版 | 繁體中文標籤、四個滑桿、預設值、功能開關與快捷鍵選單可見，無明顯裁切 | PASS |
| 由設定點擊「凍結並畫圖」 | 出現真實桌面的凍結畫布 | PASS，開發環境啟動範圍 |
| 畫筆與聚光燈 | 畫布上觀察到紅色筆跡、暗化背景、明亮圓形中心與青藍螢光邊框 | PASS，僅觀察到的狀態 |
| 工具列各工具完整操作、五色切換、復原、重做與退出 | 尚未完成逐項操作驗收 | NOT VERIFIED |
| 原生全域雙按 Control 與實際按住 Esc 3 秒 | 自動化輸入無法可靠等同實體鍵盤按放 | NOT VERIFIED；邏輯測試已通過 |
| 點擊／拖曳／捲動穿透與退出不誤點 | 尚無完整操作前後證據 | NOT VERIFIED |
| 全螢幕簡報、鏡像投影、跨螢幕繪圖對位 | 尚未完成情境驗收 | NOT VERIFIED |
| 權限拒絕、撤銷、全新使用者環境 | 未變更現有安全權限作故障注入 | NOT VERIFIED |
| 拔除投影機、切換解析度、休眠喚醒 | 未中斷使用者現有螢幕配置 | NOT VERIFIED |
| 設定寫入後完整退出／重啟持久化 | 實作使用 UserDefaults；未完整測試修改／重啟流程 | NOT VERIFIED |

## 尚需現場完成

1. 實體鍵盤：雙按 Control、使用其他 Control 組合鍵、Esc 按住 2.9 秒／超過 3 秒；確認無誤觸且放開前不把重複 Esc 傳至底層。
2. 完成至少 10 次「凍結 → 圈選 → 長按 Esc → 點擊真正按鈕」。
3. 在投影設備及教室後方驗證亮／暗背景的五色筆跡與螢光外框。
4. 測試鏡像、延伸、全螢幕簡報、插拔、休眠與混合縮放的互動對位。
5. **60 分鐘長時間使用與 100 次真實凍結／解除循環：NOT VERIFIED。** 尚無 CPU／記憶體趨勢或洩漏結論，不以 100 次模擬重設替代。
6. 聚光燈端到端 <150 ms、畫筆與游標跟隨的逐幀流暢度：NOT VERIFIED。
7. macOS 13、14、15 及其他 M 系列實機：NOT VERIFIED。最低部署版本設定不等於相容性驗證。

## 修正紀錄與包裝限制

- CoreGraphics 顯式匯入修正初次編譯問題。
- 初次離屏測試沒有可見像素；改以明確的 bitmap graphics context 測試，後續全部通過。這是測試環境修正，不宣稱為真實繪圖故障。
- 修正 Control＋Option 釋放順序可能誤算雙擊；加入兩項回歸測試。
- Retina 改取 display mode 完整像素尺寸，內建螢幕擷取由邏輯尺寸改為 2940×1912。
- 長按 Esc 完成後仍攔截該次按壓的重複事件，直到放開。
- 同步資料夾可能為 `.app` 加入 FinderInfo，造成 codesign 檢查拒絕該 metadata。交付 ZIP 不包含這些 extended attributes，解壓到獨立 /tmp 路徑後已驗證簽章及實際執行。建議從 ZIP 解壓後放入「應用程式」。
- 只有本機 ad-hoc 簽章，**未 Developer ID 簽章／公證**。其他 Mac 的 Gatekeeper 與全新權限流程仍需實測。
- 未保存真實螢幕截圖；證據只含測試文字、尺寸與時間。

## 重跑

```sh
./scripts/test.sh          # build + 17 core checks + 34 render checks
./scripts/test.sh --live   # additionally check permission status and capture each display
```

## beta.2 圖示封裝複驗

新增 Assets/AppIcon.png 與 AppIcon.icns，Info.plist 綁定 AppIcon；build number 為 2。重新建置通過 17 項核心測試；含圖示的 app 通過 codesign 嚴格完整性檢查及 34 項離屏檢查。圖示有透明背景、無文字；實際生成提示詞見 Assets/ICON_PROMPT.md。簽章仍為 ad-hoc，Gatekeeper 仍為 rejected，沒有將此狀態標示為正式簽署成功。
