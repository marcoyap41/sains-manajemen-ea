# Project 10 Expert Advisor (EA) dengan Bantuan AI
Nama  : Marco Christian <br>
NIM   : 24/539714/PA/22915 <br>
Kelas : Sains Manajemen KOMCS

Repositori ini berisi tugas mata kuliah Sains Manajemen KOMCS Ilmu Komputer UGM: membangun **10 Expert Advisor (EA)** untuk MetaTrader 5, masing-masing dibuat dengan merefer strategi dari satu channel YouTube trading/programming (mis. **Rene Balke**, **IQCapital**, atau channel lain), lalu dibangun ulang kodenya dengan bantuan AI. Tahap berikutnya dari proyek ini adalah melakukan **optimasi parameter** pada tiap EA menggunakan MetaTrader 5 Strategy Tester, sehingga dapat ditemukan beberapa EA yang **profitable dan robust**.

## Struktur Repositori

```
.
├── README.md
├── EAs/
│   ├── EA01_MA_Crossover_EA.mq5   
│   ├── EA02_....mq5            
│   ├── EA03_....mq5            
│   └── ...                    
├── docs/
│   └── BACKTESTING.md          # Panduan langkah-demi-langkah backtest di MT5
└── results/                    
    ├── EA01_MA_Crossover_Backtest.png
    ├── EA02_...png
    ├── EA03_...png
    └── ...
```

## Daftar EA

| # | Nama EA | Strategi | Sumber Referensi | Status |
|---|---------|----------|-------------------|--------|
| 1 | EA01_MA_Crossover_EA | Cross Moving Average (Fast MA vs Slow MA) | [René Balke - Fx Bot Trading](https://www.youtube.com/watch?v=Oe1JU-twbBg) | ✅ DONE |
| 2 | EA02_RSI_Mean_Reversion_EA | RSI Overbought/Oversold with MA Filter | [René Balke - Fx Bot Trading](https://www.youtube.com/watch?v=uexbULNv7YI) | ✅ DONE |
| 3 | EA03_MACD_EMA200_Crossover_EA | MACD Crossover + EMA 200 Trend Filter | [René Balke - Fx Bot Trading](https://www.youtube.com/watch?v=ab3JWfkUr-A) | ✅ DONE |
| 4 | EA04_Bollinger_Band_Mean_Reversion_EA | Bollinger Band Mean Reversion + MA Filter | [René Balke - Fx Bot Trading]() | ✅ DONE |
| 5 | EA05_Range_Breakout_EA | - | [René Balke - Fx Bot Trading]() | TO-DO |
| 6 | EA06_ATR_Candle_Breakout_EA | - | [René Balke - Fx Bot Trading]() | TO-DO |
| 7 | EA07_Market_Structure_Trend_EA | - | [René Balke - Fx Bot Trading]() | TO-DO |
| 8 | EA08_Turnaround_Tuesday_EA | - | [René Balke - Fx Bot Trading]() | TO-DO |
| 9 | EA09_Go_Long_EA | - | [René Balke - Fx Bot Trading]() | TO-DO |
| 10 | EA10_Turtle_Trading_EA | - | [René Balke - Fx Bot Trading]() | TO-DO |

## Cara Menambahkan EA Berikutnya

1. Pilih satu channel YouTube (trading/programming MQL) yang membahas sebuah strategi + implementasi EA.
2. Tonton videonya, catat logika strategi (indikator yang dipakai, syarat entry/exit, syarat SL/TP).
3. Minta AI membangun ulang EA tersebut dalam MQL5 (bukan MQL4), dengan magic number sendiri dan struktur input yang rapi - bisa pakai prompt serupa dengan yang dipakai untuk EA01.
4. Simpan file `.mq5` baru di folder `EAs/` dengan penamaan `EA0X_NamaStrategi.mq5`.
5. Update tabel **Daftar EA** di README ini.
6. Lakukan backtest awal mengikuti `docs/BACKTESTING.md` untuk memastikan EA compile tanpa error dan menghasilkan minimal satu transaksi saat di-backtest.

## Tahap Optimasi

Setelah 10 EA (atau kumpulan 20 EA kelas) terkumpul, langkah berikutnya:

1. Jalankan **Strategy Tester** MT5 dalam mode **Optimization** untuk tiap EA (lihat `docs/BACKTESTING.md` bagian "Optimasi Parameter").
2. Tentukan rentang parameter yang masuk akal untuk dioptimasi (mis. periode MA, level SL/TP, dsb.) - jangan overfit dengan rentang yang terlalu sempit/spesifik ke satu periode data saja.
3. Bandingkan hasil optimasi menggunakan beberapa periode data berbeda (in-sample vs out-of-sample / forward test) untuk menghindari overfitting.
4. Pilih kandidat EA dengan metrik yang sehat: profit factor > 1, drawdown terkendali, jumlah trade cukup banyak untuk signifikan secara statistik, dan hasil yang tetap konsisten di data out-of-sample.
5. Dokumentasikan hasil (screenshot report, parameter final) di folder `results/`.

## Referensi

- Channel referensi utama: [**Rene Balke**](https://www.youtube.com/@ReneBalke) (pemrograman MQL5/EA).
