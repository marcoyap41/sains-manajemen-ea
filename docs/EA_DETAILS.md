# EA Details

## EA01 - Moving Average Crossover

- **File:** [`../EAs/EA01_MA_Crossover_EA.mq5`](../EAs/EA01_MA_Crossover_EA.mq5)
- **Logika:** Menggunakan dua Moving Average (MA cepat & MA lambat). Sinyal **Buy** saat MA cepat memotong ke atas MA lambat, sinyal **Sell** saat MA cepat memotong ke bawah MA lambat. Sinyal dievaluasi hanya pada candle yang sudah **tertutup** (bukan candle yang sedang berjalan) agar tidak "repaint".
- **Fitur keamanan:**
  - Magic Number bisa diatur lewat input (`InpMagicNumber`), sehingga EA hanya membuka/menutup/mengubah posisi miliknya sendiri dan tidak akan mengganggu EA lain yang berjalan di akun yang sama.
  - Bekerja di simbol apa pun (menggunakan `_Symbol`/`_Period` bawaan chart, tidak di-hardcode ke satu pair).
  - Tidak menyimpan "flag" internal yang rawan hilang - status posisi selalu dibaca ulang langsung dari terminal/broker, sehingga aman jika MetaTrader restart atau EA di-reload.
  - Stop Loss / Take Profit otomatis disesuaikan agar tidak melanggar jarak minimum (`SYMBOL_TRADE_STOPS_LEVEL`) yang ditetapkan broker.
- **Parameter input penting:** `InpLots`, `InpFastMAPeriod`, `InpSlowMAPeriod`, `InpMAMethod`, `InpAppliedPrice`, `InpStopLossPts`, `InpTakeProfitPts`, `InpSlippagePts`.

## EA02 - RSI Trend

- **File:** [`../EAs/EA02_RSI_Trend_EA.mq5`](../EAs/EA02_RSI_Trend_EA.mq5)

- **Logika:** Menggunakan **Relative Strength Index (RSI)** sebagai indikator utama untuk menghasilkan sinyal **Buy** dan **Sell**. Sinyal **Buy** muncul ketika RSI berada di bawah level *oversold* yang ditentukan, sedangkan sinyal **Sell** muncul ketika RSI berada di atas level *overbought* yang ditentukan. Setelah sinyal terjadi, RSI harus kembali melewati level tengah (default 50) sebelum sinyal berikutnya dapat diaktifkan kembali.

- **Fitur keamanan:**

  - Magic Number dapat diatur melalui input (`InpMagicNumber`), sehingga EA dapat membedakan posisi miliknya dari posisi atau EA lain yang berjalan pada akun yang sama.

  - Bekerja pada simbol apa pun dan dapat menggunakan timeframe RSI yang berbeda dari timeframe chart.

  - Menyediakan **MA Filter** opsional. Jika diaktifkan, posisi Buy hanya diperbolehkan ketika harga berada di atas MA, sedangkan posisi Sell hanya diperbolehkan ketika harga berada di bawah MA.

  - Sinyal dievaluasi berdasarkan candle yang sudah **tertutup** untuk menghindari penggunaan nilai RSI pada candle yang masih berjalan.

  - Menyediakan Stop Loss, Take Profit, dan Trailing Stop berbasis persentase harga.

  - Mendukung perhitungan ukuran lot berdasarkan persentase risiko serta menyediakan fallback lot apabila perhitungan berbasis risiko tidak dapat digunakan.

- **Parameter input penting:** `InpRSIPeriod`, `InpRSITimeframe`, `InpBuyLevel`, `InpSellLevel`, `InpRSIMidLevel`, `InpUseMAFilter`, `InpMAPeriod`, `InpMATimeframe`, `InpMAMethod`, `InpStopLossPercent`, `InpTakeProfitPercent`, `InpTrailingTriggerPercent`, `InpTrailingDistancePercent`, `InpTrailingStepPercent`, `InpRiskMode`, `InpRiskValue`, `InpFallbackLots`.
