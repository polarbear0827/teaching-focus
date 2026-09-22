# v1.0.0-beta.1 簽章檢查

檢查日期：2026-09-22。對象：從交付 ZIP 解壓的 TeachingFocus.app。

| 檢查 | 結果 |
|---|---|
| `codesign --verify --deep --strict --verbose=2` | PASS：valid on disk；satisfies its Designated Requirement |
| `codesign -dv --verbose=4` | Signature=adhoc；TeamIdentifier=not set |
| `security find-identity -v -p codesigning` | 0 valid identities found |
| `spctl --assess --type execute --verbose=4` | **rejected** |
| Apple 公證 | 尚未提交或完成，無公證票證 |
| 解壓後執行繪圖檢查 | 34 項 PASS；僅證明目前開發機可執行 |

執行檔 SHA-256：`bc6c0ef501fa9f852449947e7df75005854096dadf08232c68ba76ab191ecb14`。

**完整性驗證通過不代表 Apple 信任此開發者，也不代表其他 Mac 可無提示開啟。** DMG 只是安裝容器，不會讓內含程式自動取得正式簽章或公證。安裝包校驗碼見 Release 的 SHA256SUMS.txt。

## 正式發布尚需

1. Apple Developer Program 的 Developer ID Application 憑證及對應私鑰。
2. 啟用 Hardened Runtime，以 Developer ID 重新簽署 app 並加上安全時間戳記。
3. 使用已授權的 notarytool 憑證設定提交公證；不要將密碼、私鑰或 API key 放進 repo。
4. 公證 Accepted 後 staple 票證、重新驗簽，確認 Gatekeeper 接受，再重新建立安裝包及校驗碼。
5. 在另一台乾淨 Mac 驗證下載後首次啟動與 TCC 授權。

目前不宣稱已完成上述步驟。本版作為私人預覽 Release 發布，保留所有現場 NOT VERIFIED 項目。
