# EA Details

## EA01 - Moving Average Crossover

- **File:** [`EAs/MA_Crossover.mq5`](EAs/MA_Crossover.mq5)
- **Logika:** Menggunakan dua Moving Average (MA cepat & MA lambat). Sinyal **Buy** saat MA cepat memotong ke atas MA lambat, sinyal **Sell** saat MA cepat memotong ke bawah MA lambat. Sinyal dievaluasi hanya pada candle yang sudah **tertutup** (bukan candle yang sedang berjalan) agar tidak "repaint".
- **Fitur keamanan:**
  - Magic Number bisa diatur lewat input (`InpMagicNumber`), sehingga EA hanya membuka/menutup/mengubah posisi miliknya sendiri dan tidak akan mengganggu EA lain yang berjalan di akun yang sama.
  - Bekerja di simbol apa pun (menggunakan `_Symbol`/`_Period` bawaan chart, tidak di-hardcode ke satu pair).
  - Tidak menyimpan "flag" internal yang rawan hilang - status posisi selalu dibaca ulang langsung dari terminal/broker, sehingga aman jika MetaTrader restart atau EA di-reload.
  - Stop Loss / Take Profit otomatis disesuaikan agar tidak melanggar jarak minimum (`SYMBOL_TRADE_STOPS_LEVEL`) yang ditetapkan broker.
- **Parameter input penting:** `InpLots`, `InpFastMAPeriod`, `InpSlowMAPeriod`, `InpMAMethod`, `InpAppliedPrice`, `InpStopLossPts`, `InpTakeProfitPts`, `InpSlippagePts`.