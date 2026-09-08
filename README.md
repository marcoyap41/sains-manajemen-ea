# Proyek 10 Expert Advisor (EA) dengan Bantuan AI

Repositori ini berisi tugas mata kuliah: membangun **10 Expert Advisor (EA)** untuk MetaTrader 5, masing-masing dibuat dengan merefer strategi dari satu channel YouTube trading/programming (mis. **Rene Balke**, **IQCapital**, atau channel lain), lalu dibangun ulang kodenya dengan bantuan AI. Tahap berikutnya dari proyek ini adalah melakukan **optimasi parameter** pada tiap EA menggunakan MetaTrader 5 Strategy Tester, sehingga dari 20 kandidat EA (10 mahasiswa x versi masing-masing, atau 10 EA x beberapa varian) dapat ditemukan beberapa EA yang **profitable dan robust**.

## Struktur Repositori

```
.
├── README.md
├── EAs/
│   ├── EA01_MA_Crossover.mq5   # Sudah selesai — lihat detail di bawah
│   ├── EA02_....mq5            # TO-DO
│   ├── EA03_....mq5            # TO-DO
│   └── ...                     # sampai EA10
├── docs/
│   └── BACKTESTING.md          # Panduan langkah-demi-langkah backtest di MT5
└── results/                    # (opsional) simpan screenshot/report hasil backtest tiap EA
```

## Daftar EA

| # | Nama EA | Strategi | Sumber Referensi | Status |
|---|---------|----------|-------------------|--------|
| 1 | EA01_MA_Crossover | Cross Moving Average (Fast MA vs Slow MA) | [René Balke - Fx Bot Trading](https://www.youtube.com/watch?v=Oe1JU-twbBg) | ✅ DONE |
| 2 | — | — | — | ⬜ TO-DO |
| 3 | — | — | — | ⬜ TO-DO |
| 4 | — | — | — | ⬜ TO-DO |
| 5 | — | — | — | ⬜ TO-DO |
| 6 | — | — | — | ⬜ TO-DO |
| 7 | — | — | — | ⬜ TO-DO |
| 8 | — | — | — | ⬜ TO-DO |
| 9 | — | — | — | ⬜ TO-DO |
| 10 | — | — | — | ⬜ TO-DO |

> Update tabel ini setiap kali sebuah EA baru selesai dibuat. Isi kolom "Sumber Referensi" dengan nama channel + judul video yang jadi acuan strategi.

## EA01 — Moving Average Crossover

- **File:** [`EAs/MA_Crossover.mq5`](EAs/MA_Crossover.mq5)
- **Logika:** Menggunakan dua Moving Average (MA cepat & MA lambat). Sinyal **Buy** saat MA cepat memotong ke atas MA lambat, sinyal **Sell** saat MA cepat memotong ke bawah MA lambat. Sinyal dievaluasi hanya pada candle yang sudah **tertutup** (bukan candle yang sedang berjalan) agar tidak "repaint".
- **Fitur keamanan:**
  - Magic Number bisa diatur lewat input (`InpMagicNumber`), sehingga EA hanya membuka/menutup/mengubah posisi miliknya sendiri dan tidak akan mengganggu EA lain yang berjalan di akun yang sama.
  - Bekerja di simbol apa pun (menggunakan `_Symbol`/`_Period` bawaan chart, tidak di-hardcode ke satu pair).
  - Tidak menyimpan "flag" internal yang rawan hilang — status posisi selalu dibaca ulang langsung dari terminal/broker, sehingga aman jika MetaTrader restart atau EA di-reload.
  - Stop Loss / Take Profit otomatis disesuaikan agar tidak melanggar jarak minimum (`SYMBOL_TRADE_STOPS_LEVEL`) yang ditetapkan broker.
- **Parameter input penting:** `InpLots`, `InpFastMAPeriod`, `InpSlowMAPeriod`, `InpMAMethod`, `InpAppliedPrice`, `InpStopLossPts`, `InpTakeProfitPts`, `InpSlippagePts`.

## Cara Menambahkan EA Berikutnya

1. Pilih satu channel YouTube (trading/programming MQL) yang membahas sebuah strategi + implementasi EA.
2. Tonton videonya, catat logika strategi (indikator yang dipakai, syarat entry/exit, syarat SL/TP).
3. Minta AI membangun ulang EA tersebut dalam MQL5 (bukan MQL4), dengan magic number sendiri dan struktur input yang rapi — bisa pakai prompt serupa dengan yang dipakai untuk EA01.
4. Simpan file `.mq5` baru di folder `EAs/` dengan penamaan `EA0X_NamaStrategi.mq5`.
5. Update tabel **Daftar EA** di README ini.
6. Lakukan backtest awal mengikuti `docs/BACKTESTING.md` untuk memastikan EA compile tanpa error dan menghasilkan minimal satu transaksi saat di-backtest.

## Tahap Optimasi (2 Minggu Berikutnya)

Setelah 10 EA (atau kumpulan 20 EA kelas) terkumpul, langkah berikutnya:

1. Jalankan **Strategy Tester** MT5 dalam mode **Optimization** untuk tiap EA (lihat `docs/BACKTESTING.md` bagian "Optimasi Parameter").
2. Tentukan rentang parameter yang masuk akal untuk dioptimasi (mis. periode MA, level SL/TP, dsb.) — jangan overfit dengan rentang yang terlalu sempit/spesifik ke satu periode data saja.
3. Bandingkan hasil optimasi menggunakan beberapa periode data berbeda (in-sample vs out-of-sample / forward test) untuk menghindari overfitting.
4. Pilih kandidat EA dengan metrik yang sehat: profit factor > 1, drawdown terkendali, jumlah trade cukup banyak untuk signifikan secara statistik, dan hasil yang tetap konsisten di data out-of-sample.
5. Dokumentasikan hasil (screenshot report, parameter final) di folder `results/`.

## Referensi

- Channel referensi wajib: **Rene Balke** (pemrograman MQL5/EA).
- Channel referensi tambahan (pilih salah satu atau lebih, contoh): **IQCapital**, atau channel lain yang membahas strategi trading + implementasi EA MT5.
- Daftar pembagian channel/strategi per mahasiswa: lihat spreadsheet tugas kelas.
- Kata kunci untuk riset tahap optimasi: *"optimasi Expert Advisor MT5"*, *"MT5 Strategy Tester optimization"*, *"forward testing Expert Advisor"*, *"walk-forward optimization MT5"*.
