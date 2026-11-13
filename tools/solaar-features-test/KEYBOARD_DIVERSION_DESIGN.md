# 鍵盤特殊鍵改道：設計交接（未實作／未啟用）

第 7 項本輪只完成設計；不新增改道 UI、設定檔欄位、CID 探測或實體輸入事件處理。以下是待實作規格，不能作為完成或實機驗證的聲明。

## 協定依據（本輪閱讀的 Solaar 副本）

- `hidpp20.py` `Hidpp20.get_keys`／`KeysArrayV4._query_key`：0x1B04 fn0 讀數量，fn1 以 index 查控制；payload `!HHBBBBB` 為 CID、task、flags low、position、group、group mask、flags high。32 是既有裝置觀察值，實作必須照 count 列舉，不寫死。
- `hidpp20.py` `KeyFlag`：暫時可改道 0x20；virtual 0x80；依 `settings_templates.py` `DivertKeys.validator_class` 只呈現可改道且非 virtual 的控制。
- `special_keys.py` `CONTROL` 提供名稱對照；不能拿 task ID 當 CID。未知 CID 顯示十六進位。名稱應整理成自行撰寫的中英表，不複製 GPL 程式碼。
- `hidpp20.py` `ReprogrammableKeyV4._getCidReporting`：fn2 `[CID high, CID low]`，回覆 `[CID high, CID low, flags low, mapped CID high, mapped CID low, flags high]`。
- `ReprogrammableKeyV4._setCidReporting`、`MappingFlag`：fn3 `[CID high, CID low, 0x03 或 0x02, 0, 0]`；0x01 是 temporary diversion、0x02 是其 valid 位元。0x03 開啟、0x02 關閉；mapped CID=0 保留映射。不設 persistent/raw XY/analytics 的 valid 位元。ACK 之後 fn2 回讀，比對 CID 與 temporary bit 才算成功。
- `notifications.py` `REPROG_CONTROLS_V4` 分支：通知 fn0 的前八 bytes 是四個 big-endian CID；應與上一個完整集合比較，僅對新按下的 CID 執行一次 Action。fn1 raw XY 不當按鍵、fn2 analytics 不可和 fn0 重複執行。

## 兩平台共同規格

1. 沿用現有 ActionBinding／動作清單。選原生動作就解除本程式擁有的 temporary diversion；預設完全不改道。以裝置身分＋CID 保存選擇，不能用槽位或顯示名稱當永久身分。
2. 每次連線先讀能力與 CID 清單，僅對使用者指定、這台裝置仍存在且支援的 CID 設定。先建立清理責任再寫入，ACK 遺失也保留關閉責任。成功回讀後才顯示套用。
3. 事件按來源裝置、槽位、feature index、software ID=0 分流；只取專用 HID++ 事件，絕不讀取、記錄或保留一般鍵盤打字輸入。持有 CID 集合、動作 dispatch 與取消狀態須有清楚的佇列歸屬。
4. 按下執行 Action，放開只更新集合；若既有 Action 需要成對按下／放開，需為該類動作另定生命週期。切頻道、睡眠、移除、暫停時清空按下狀態，重連不得自動重播舊按下事件。
5. 關閉、暫停、解除指定及連線切換前，針對本程式擁有的 CID 送 temporary off 並回讀。無回覆必須保留清理責任／提示，不能只清掉記憶體集合。不得擅自撤銷其他程式的改道。

## macOS 接點

- `KeyboardHIDPP` 已有 IOHID callback＋序列 work queue，可在 received 的通知分支新增 CID 集合處理，動作送回主執行緒使用現有 ActionRunner。
- 新增待回覆的來源驗證與 connection generation，將快照、通知、寫入／清理限制在同一個來源與世代；移除或切換後排隊的舊事件不得執行。
- `stop()` 必須在 reset 之前完成清理；`changeHost()` 在傳送切頻道之前解除本程式改道。

## Windows 接點與本輪不啟用原因

`KeyboardManager` 現有 transport 只在 Request 中讀 handle。`HidTransport.Request` 在送出前 FlushQueue，會丟掉空閒期間的通知。直接增加第二個讀取執行緒會和 Request 搶同一個 handle，可能吃掉回覆、令寫入誤判失敗，也會放大 Bolt 休眠／待切換的競態。

後續需要單一讀取者：統一讀取迴圈把軟體回覆交給 pending request，把 software ID=0 的鍵盤通知交給事件佇列；Request 不得再自行讀／flush。另須驗證 CancelIo／Dispose、重連世代、來源隔離、短報告錯誤與 Raw Input 不重複 dispatch。亦可評估單獨 Raw Input 事件通道，但必須先證明來源與短／長報告完整且不重複。這是通訊生命週期的實質修改，不能在本輪禁止實體裝置測試的條件下，把未驗證的按鍵接管當成功能交付；Mac 也暫不交付一套不同生命週期的未驗證版本。

## 實作前後必要驗收（尚未執行）

- 純測試：CID info／reporting 封包、flags 保留、錯誤／缺漏／不同 CID 回覆、四鍵完整集合、新按下去重、同 CID 的滑鼠與鍵盤隔離。
- 模擬通訊：通知與回覆交錯、ACK 遺失、裝置移除、排隊事件跨世代、暫停／恢復、切頻道、所有清理失敗重試與 Dispose 期間讀取取消。
- 實機：先選一個非關鍵特殊鍵，原生→改道→動作一次→解除；分別測 BT／Bolt、Options+ 開／關、睡眠與跨主機往返、正常結束與訊號結束；保留鍵盤正常輸入、其他未指定按鍵與滑鼠動作。全部通過後才擴大到多個 CID。
