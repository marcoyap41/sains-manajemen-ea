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

## EA02 - RSI Mean Reversion

- **File:** [`../EAs/EA02_RSI_Mean_Reversion_EA.mq5`](../EAs/EA02_RSI_Mean_Reversion_EA.mq5)

- **Logika:** Menggunakan **Relative Strength Index (RSI)** sebagai indikator utama untuk menghasilkan sinyal **Buy** dan **Sell**. Sinyal **Buy** muncul ketika RSI berada di bawah level *oversold* yang ditentukan, sedangkan sinyal **Sell** muncul ketika RSI berada di atas level *overbought* yang ditentukan. Setelah sinyal terjadi, RSI harus kembali melewati level tengah (default 50) sebelum sinyal berikutnya dapat diaktifkan kembali.

- **Fitur keamanan:**

  - Magic Number dapat diatur melalui input (`InpMagicNumber`), sehingga EA dapat membedakan posisi miliknya dari posisi atau EA lain yang berjalan pada akun yang sama.

  - Bekerja pada simbol apa pun dan dapat menggunakan timeframe RSI yang berbeda dari timeframe chart.

  - Menyediakan **MA Filter** opsional. Jika diaktifkan, posisi Buy hanya diperbolehkan ketika harga berada di atas MA, sedangkan posisi Sell hanya diperbolehkan ketika harga berada di bawah MA.

  - Sinyal dievaluasi berdasarkan candle yang sudah **tertutup** untuk menghindari penggunaan nilai RSI pada candle yang masih berjalan.

  - Menyediakan Stop Loss, Take Profit, dan Trailing Stop berbasis persentase harga.

  - Mendukung perhitungan ukuran lot berdasarkan persentase risiko serta menyediakan fallback lot apabila perhitungan berbasis risiko tidak dapat digunakan.

- **Parameter input penting:** `InpRSIPeriod`, `InpRSITimeframe`, `InpBuyLevel`, `InpSellLevel`, `InpRSIMidLevel`, `InpUseMAFilter`, `InpMAPeriod`, `InpMATimeframe`, `InpMAMethod`, `InpStopLossPercent`, `InpTakeProfitPercent`, `InpTrailingTriggerPercent`, `InpTrailingDistancePercent`, `InpTrailingStepPercent`, `InpRiskMode`, `InpRiskValue`, `InpFallbackLots`.

## EA03 - MACD + EMA200 Crossover

- **File:** [`../EAs/EA03_MACD_EMA200_Crossover_EA.mq5`](../EAs/EA03_MACD_EMA200_Crossover_EA.mq5)
- **Logika:** Sinyal utama dari persilangan garis MACD (main line) dan signal line, dengan syarat tambahan posisi silangnya: **Buy** hanya valid jika persilangan (main memotong ke atas signal) terjadi **di bawah** garis nol, **Sell** hanya valid jika persilangan (main memotong ke bawah signal) terjadi **di atas** garis nol. Ditambah filter tren **EMA(200)**: harga harus di atas EMA untuk Buy, di bawah EMA untuk Sell. Sinyal hanya dievaluasi pada candle yang sudah **tertutup**.
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagicNumber`), hanya memproses posisi miliknya sendiri.
  - Timeframe- dan symbol-agnostic (`_Symbol`/timeframe chart, tidak hardcode).
  - Status "sudah trading di bar ini" tidak disimpan sebagai flag internal yang rapuh, melainkan diturunkan ulang langsung dari riwayat deal broker di setiap tick — sehingga aman terhadap restart MT5/terminal tanpa file state eksternal.
  - Filter spread maksimum opsional (`InpMaxSpreadPoints`) dan opsi membatasi hanya satu posisi terbuka (`InpAllowMultiplePositions`).
  - SL diletakkan dengan buffer di luar EMA(200), TP dihitung dari rasio risk:reward terhadap jarak SL tersebut.
- **Parameter input penting:** `InpMagicNumber`, `InpAllowMultiplePositions`, `InpMaxSpreadPoints`, `InpSlippagePoints`, `InpFastEMA`, `InpSlowEMA`, `InpSignalSMA`, `InpMAPeriod`, `InpAppliedPrice`, `InpSLBufferPercent`, `InpRiskReward`, `InpUseMoneyManagement`, `InpRiskPercent`, `InpFixedLots`, `InpUseBarOpenDelay`, `InpBarOpenDelayMinutes`.

## EA04 - Bollinger Band Mean Reversion + MA Filter

- **File:** [`../EAs/EA04_Bollinger_Band_Mean_Reversion_EA.mq5`](../EAs/EA04_Bollinger_Band_Mean_Reversion_EA.mq5)
- **Logika:** Mean-reversion dari Bollinger Bands — **Sell** saat harga menyentuh/melewati band **atas**, **Buy** saat harga menyentuh/melewati band **bawah**. Filter MA opsional (timeframe & periode sendiri): Sell hanya diizinkan bila Bid di bawah MA, Buy hanya diizinkan bila Ask di atas MA. SL/TP dihitung dari lebar Bollinger Band (Upper−Lower) saat sinyal muncul, dikalikan faktor SL/TP masing-masing. Saat harga kembali melewati garis tengah (basis line), sebagian posisi (`InpClosePercent`%) ditutup — bisa diset 100% untuk full close.
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagic`), hanya satu posisi per simbol per magic number pada satu waktu.
  - Bekerja di simbol apa pun, timeframe Bollinger Band & MA independen dari timeframe chart.
  - Status "sudah partial-close" dipulihkan setelah restart MT5 lewat terminal `GlobalVariable` yang di-key per tiket posisi, sehingga tidak partial-close dobel setelah restart.
- **Parameter input penting:** `InpMagic`, `InpLots`, `InpSlippagePoints`, `InpBBTimeframe`, `InpBBPeriod`, `InpBBShift`, `InpBBDeviation`, `InpBBAppliedPrice`, `InpUseMAFilter`, `InpMATimeframe`, `InpMAPeriod`, `InpMAShift`, `InpMAMethod`, `InpMAAppliedPrice`, `InpSLFactor`, `InpTPFactor`, `InpClosePercent`.

## EA05 - Range Breakout

- **File:** [`../EAs/EA05_RangeBreakout_EA.mq5`](../EAs/EA05_RangeBreakout_EA.mq5)
- **Logika:** Setiap sesi, range harga dibangun antara jam `InpRangeStartHour:Minute` dan `InpRangeEndHour:Minute` (server time). Setelah range selesai terbentuk, EA memasang **Buy Stop** di batas atas range dan **Sell Stop** di batas bawah range (bisa dibatasi hanya satu sisi lewat `InpTradeMode`). Jika harga sudah breakout duluan sebelum order sempat dipasang, EA langsung membuka posisi market sebagai gantinya (menghindari pending order yang tidak valid). SL/TP dihitung dari lebar range dikalikan faktor SL/TP; TP opsional. Opsional: semua posisi/pending order ditutup paksa di `InpCloseHour:Minute`, dan opsional OCO (`InpOneTradePerDay`) — begitu satu sisi kena fill, order sisi seberang otomatis dibatalkan.
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagicNumber`), hanya menangani order/posisi miliknya sendiri.
  - Bekerja di simbol/chart apa pun.
  - Status harian (sudah pasang order / sudah force-close hari ini) dipulihkan lewat terminal `GlobalVariable`, sehingga restart MT5 di tengah sesi tidak menyebabkan order dobel atau force-close berulang di hari yang sama.
  - Opsi visualisasi range di chart (`InpVisualizeRange`) untuk mempermudah verifikasi visual saat backtest.
- **Parameter input penting:** `InpMagicNumber`, `InpRangeStartHour/Minute`, `InpRangeEndHour/Minute`, `InpUseCloseTime`, `InpCloseHour/Minute`, `InpRiskMoney`, `InpSLFactor`, `InpUseTP`, `InpTPFactor`, `InpTradeMode`, `InpOneTradePerDay`, `InpSlippagePoints`, `InpPendingBufferPts`.

## EA06 - ATR Momentum Breakout

- **File:** [`../EAs/EA06_ATRMomentumBreakout_EA.mq5`](../EAs/EA06_ATRMomentumBreakout_EA.mq5)
- **Logika:** Pada setiap bar baru di timeframe kerja (`InpTimeframe`), EA mengecek candle yang baru saja tertutup. Jika range (high−low) candle tersebut lebih besar dari `InpATRMultiplier × ATR(InpATRPeriod)`, candle itu dianggap "candle sinyal". Arah trade mengikuti arah candle (bullish → Buy, bearish → Sell), dengan syarat tambahan: close candle harus cukup dekat ke ekstrem candle-nya sendiri (dalam `InpCloseProximityPct`% dari range, diukur dari high untuk Buy / dari low untuk Sell). SL/TP berupa persentase dari harga entry; ukuran posisi dihitung dari risiko uang tetap (`InpRiskMoney`) per trade. Maksimal satu entry baru per candle sinyal, tapi beberapa posisi bisa terbuka bersamaan jika beberapa sinyal muncul sebelum posisi sebelumnya selesai (tidak ada manajemen posisi aktif selain SL/TP).
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagicNumber`).
  - Seluruh proses dievaluasi sekali per bar baru (bukan per tick) untuk efisiensi.
  - Status "sudah trading candle ini" disimpan di terminal `GlobalVariable` persisten, sehingga restart MT5 tidak menyebabkan sinyal yang sama dieksekusi dua kali.
  - Label visual di atas tiap candle sinyal (nilai ATR & ukuran candle) untuk mempermudah verifikasi visual.
- **Parameter input penting:** `InpMagicNumber`, `InpTimeframe`, `InpATRPeriod`, `InpATRMultiplier`, `InpCloseProximityPct`, `InpSLPercent`, `InpTPPercent`, `InpRiskMoney`, `InpSlippagePoints`, `InpShowSignalLabels`.

## EA07 - Market Structure Trend Following

- **File:** [`../EAs/EA07_MarketStructureTrend_EA.mq5`](../EAs/EA07_MarketStructureTrend_EA.mq5)
- **Logika:** Mendeteksi swing high/low secara independen di dua timeframe — **Trend** (timeframe lebih tinggi) dan **Signal** (timeframe lebih rendah). Sebuah bar dikonfirmasi sebagai swing high/low jika benar-benar tertinggi/terendah dibanding `InpSwingLeftBars` bar di kirinya dan `InpSwingRightBars` bar di kanannya (baru terkonfirmasi setelah bar-bar kanan itu benar-benar tertutup, sehingga tidak repaint). **Definisi tren** (di timeframe Trend): begitu terjadi `InpTrendConsecutiveSwings` higher-high & higher-low berturut-turut → uptrend aktif (simetris untuk downtrend); level invalidasi tren mengikuti swing low/high terakhir dan dicek tiap tick. **Entry** (di timeframe Signal): selama tren Trend-timeframe aktif, begitu muncul `InpSignalConsecutiveSwings` swing higher/lower berturut-turut searah tren di timeframe Signal, posisi market langsung dibuka; maksimal `InpMaxTradesPerTrend` trade per tren aktif, dan tiap pola swing Signal yang memenuhi syarat hanya memicu maksimal satu trade (mencegah entry berulang). **Exit:** semua posisi searah tren ditutup begitu tren Trend-timeframe dinyatakan invalid.
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagicNumber`), hanya menangani posisi miliknya sendiri.
  - Deteksi swing & evaluasi tren/entry hanya sekali per bar baru per timeframe (bukan per tick); satu-satunya kerja per tick adalah satu perbandingan harga untuk cek trend-break.
  - Saat start/restart, riwayat swing & status tren dibangun ulang langsung dari data harga historis (bukan mengandalkan state yang rapuh); hanya state yang benar-benar tidak bisa dihitung ulang (arah tren aktif, jumlah trade di tren berjalan, sinyal terakhir yang sudah ditradingkan) yang dipersist ke terminal `GlobalVariable`.
  - Bekerja di simbol apa pun; SL bisa dalam poin, persen harga, atau di swing low/high terakhir; TP dalam poin, persen, atau nonaktif.
- **Parameter input penting:** `InpMagicNumber`, `InpTrendTimeframe`, `InpSignalTimeframe`, `InpSwingLeftBars`, `InpSwingRightBars`, `InpTrendConsecutiveSwings`, `InpSignalConsecutiveSwings`, `InpMaxTradesPerTrend`, `InpRiskMoney`, `InpSLMode`, `InpSLPoints`, `InpSLPercent`, `InpTPMode`, `InpTPPoints`, `InpTPPercent`, `InpSlippagePoints`, `InpHistoryLookbackBars`.

## EA08 - Turnaround Tuesday

- **File:** [`../EAs/EA08_TurnaroundTuesday_EA.mq5`](../EAs/EA08_TurnaroundTuesday_EA.mq5)
- **Logika:** Buy dibuka pada hari & jam tertentu (default **Senin 22:55** server time), hanya jika harga (Bid) berada **di bawah** filter Moving Average (default MA harian, periode 24, SMA, close price). Posisi ditutup pada hari & jam tertentu lainnya (default **Selasa 22:55**). SL berupa persentase dari harga entry; ukuran lot dihitung dari risiko persentase saldo akun.
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagicNumber`), hanya menangani posisi miliknya sendiri.
  - Status (posisi terbuka & "sudah entry hari ini") dibangun ulang dari data posisi live saat `OnInit()`, sehingga restart MT5 di tengah posisi terbuka tidak menyebabkan entry dobel atau kehilangan jejak posisi.
  - Bekerja di simbol apa pun — parameter tick size/tick value/volume step diambil otomatis dari simbol aktif, tidak hardcode ke satu indeks.
  - Validasi input (jam/menit valid, risk % dan SL % > 0) di `OnInit()`.
- **Parameter input penting:** `InpMagicNumber`, `InpDeviationPoints`, `InpBarTimeframe`, `InpDayOpen`, `InpOpenHour/Minute`, `InpDayClose`, `InpCloseHour/Minute`, `InpUseMAFilter`, `InpMATimeframe`, `InpMAPeriod`, `InpMAMethod`, `InpMAAppliedPrice`, `InpRiskPercent`, `InpStopLossPercent`, `InpLotDigits`.

## EA09 - Go Long

- **File:** [`../EAs/EA09_GoLong_EA.mq5`](../EAs/EA09_GoLong_EA.mq5)
- **Logika:** Buy dibuka setiap hari trading pada jam tertentu (default **01:05** server time) dan ditutup lagi di jam tertentu (default **22:50**) — supaya hanya membayar spread, bukan swap overnight. Ukuran posisi dihitung risk-based: `InpRiskPercent` dari `InpBaseMoney` (atau saldo live jika `InpBaseMoney=0`) dianggap sebagai kerugian maksimum bila harga jatuh ke nol. Filter opsional **"wait for new high"** (`InpWaitForNewHigh`): bila aktif, EA tidak langsung entry di jam trigger, melainkan menghitung *reference high* hari itu (dari tengah malam sampai jam trigger) lalu baru Buy saat harga menembus level tersebut. SL/TP nonaktif secara default (sesuai strategi aslinya) tapi bisa diaktifkan sebagai persentase dari harga entry.
- **Fitur keamanan:**
  - Magic Number adjustable (`InpMagicNumber`), hanya menangani posisi miliknya sendiri.
  - Status (posisi terbuka & tanggal entry terakhir) dibangun ulang dari data posisi live saat `OnInit()`.
  - Pengecekan margin sebelum kirim order — lot size otomatis diturunkan jika free margin tidak mencukupi.
  - Bekerja di simbol apa pun; semua konversi harga↔uang memakai tick size/tick value simbol aktif.
- **Parameter input penting:** `InpMagicNumber`, `InpDeviationPoints`, `InpOpenHour/Minute`, `InpCloseHour/Minute`, `InpWaitForNewHigh`, `InpBaseMoney`, `InpRiskPercent`, `InpLotDigits`, `InpUseStopLoss`, `InpStopLossPercent`, `InpUseTakeProfit`, `InpTakeProfitPercent`.

## EA10 - Ninja Turtle Scalper (Donchian Channel Breakout)

- **File:** [`../EAs/EA10_NinjaTurtleScalper_EA.mq5`](../EAs/EA10_NinjaTurtleScalper_EA.mq5)
- **Logika:** Donchian Channel (highest-high/lowest-low atas N bar + garis tengah) dihitung di timeframe & periode tertentu. Tiga mode trigger entry (`InpTriggerMode`): **Tick** (entry instan begitu harga menyentuh upper/lower band), **M1 close** (entry saat candle M1 close di luar band), atau **Donchian close** (entry saat bar timeframe Donchian sendiri close di luar band, dengan channel pembanding yang mengecualikan bar yang sedang diuji). Aturan **re-arm**: setelah sinyal Sell, sinyal Sell berikutnya baru bisa aktif jika harga sempat kembali ke atas garis tengah; setelah sinyal Buy, harus kembali ke bawah garis tengah dulu. Volume mode **Lots** (fixed) atau **Money** (lot dihitung dari jarak SL agar kerugian awal ≈ jumlah uang yang ditentukan). SL wajib, TP opsional (persen dari harga entry). Trailing SL: aktif setelah profit mencapai `InpTSLTriggerPercent`, mengikuti harga dengan jarak `InpTSLDistancePercent`, hanya dimodifikasi bila perbaikan ≥ `InpTSLStepPercent`.
- **Fitur keamanan:**
  - Magic Number & comment adjustable (`InpMagicNumber`, `InpComment`), hanya satu posisi terbuka di satu waktu (tidak hedging terhadap dirinya sendiri).
  - Status re-arm (`buyArmed`/`sellArmed`) dipersist ke terminal `GlobalVariable` (unik per simbol+magic number), bertahan lintas restart MT5 — bukan cuma posisi yang direstore, tapi juga status "boleh/tidak boleh sinyal lagi".
  - Posisi terbuka direkonstruksi dari data live saat `OnInit()`.
  - Pengecekan margin sebelum kirim order, lot otomatis diturunkan bila margin tidak cukup.
  - Bekerja di simbol apa pun via tick size/tick value/volume step simbol aktif.
- **Parameter input penting:** `InpMagicNumber`, `InpComment`, `InpSendLogs`, `InpDeviationPoints`, `InpVolumeMode`, `InpVolume`, `InpLotDigits`, `InpTakeProfitPercent`, `InpStopLossPercent`, `InpTSLTriggerPercent`, `InpTSLDistancePercent`, `InpTSLStepPercent`, `InpDonchianTimeframe`, `InpDonchianPeriod`, `InpTriggerMode`.
