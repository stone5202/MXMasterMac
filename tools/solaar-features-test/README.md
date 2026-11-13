# Solaar 功能離線測試

在專案根目錄執行 `tools/solaar-features-test/run.sh`。只編譯純邏輯與擷取自 Config.swift 的 DeviceSettings；不啟動應用程式、不存取 HID 或使用者設定。

涵蓋第 1–6 項的封包、解析、範圍、回讀比對、所有 byte 值的位元保留、三種背光延遲與四種模式、OS 清單去重與排序、設定檔舊格式及往返。第 7 項只有 KEYBOARD_DIVERSION_DESIGN.md，沒有對應已實作測試。

`preview.swift` 是獨立離屏畫面入口；與 Sources/*.swift 一起編譯時排除 Sources/main.swift，不得改為啟動正式 App。它只建立尚未 start 的 AppModel，填入示範快照，以 NSHostingView 離屏輸出頁 2／5 的中英文全長畫面。HID 管理器從未啟動、device／candidate 保持空值，因此 view.onAppear 的 refresh 也不會送裝置請求。
