# v1.0.0-beta.3 簽章檢查

檢查日期：2026-09-22。對象：從交付 PKG 展開的 TeachingFocus.app，以及 PKG 容器。

| 檢查 | 結果 |
|---|---|
| `codesign --verify --deep --strict --verbose=2` | PASS：valid on disk；satisfies its Designated Requirement |
| `codesign -dv --verbose=4` | Signature=adhoc；TeamIdentifier=not set |
| `security find-identity -v -p codesigning` | 0 valid identities found |
| `spctl --assess --type execute --verbose=4` | **rejected** |
| `pkgutil --check-signature` | **Status: no signature**（PKG 未簽署） |
| Apple 公證 | 尚未提交或完成，無公證票證 |
| 解壓後執行繪圖檢查 | 34 項 PASS；僅證明目前開發機可執行 |

執行檔 SHA-256：`cda6ed07279c742f1d41d7ebeaa8c56ae675b32a737d31bb982cda21585c7e9e`。

**完整性驗證通過不代表 Apple 信任此開發者，也不代表其他 Mac 可無提示開啟。** PKG 只是安裝容器，不會讓內含程式自動取得正式簽章或公證。安裝包校驗碼見 Release 的 SHA256SUMS.txt。

## 正式發布尚需

1. Apple Developer Program 的 Developer ID Application 與 Developer ID Installer 憑證及對應私鑰；前者簽 app，後者簽 PKG。
2. 啟用 Hardened Runtime，以 Developer ID 重新簽署 app 並加上安全時間戳記。
3. 使用已授權的 notarytool 憑證設定提交公證；不要將密碼、私鑰或 API key 放進 repo。
4. 公證 Accepted 後 staple 票證、重新驗簽，確認 Gatekeeper 接受，再重新建立安裝包及校驗碼。
5. 在另一台乾淨 Mac 驗證下載後首次啟動與 TCC 授權。

目前不宣稱已完成上述步驟。本版作為公開預覽 Release 發布，保留所有現場 NOT VERIFIED 項目。

PKG 的安裝目標已核對為 `/Applications/TeachingFocus.app`，`relocatable=false`，無安裝腳本。已展開 payload 並驗證 app 簽章、圖示資源與 34 項離屏檢查；未在本機執行需要系統安裝授權的實際安裝，因此 Installer 完整安裝流程為 NOT VERIFIED。
