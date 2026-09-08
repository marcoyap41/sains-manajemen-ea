# Panduan Backtesting EA di MetaTrader 5

Panduan ini menjelaskan langkah demi langkah cara menguji file `.mq5` di repo ini menggunakan **Strategy Tester** bawaan MetaTrader 5, dan cara membaca hasilnya untuk tahu apakah EA "berhasil" (jalan tanpa error, benar-benar bertransaksi) sebelum masuk ke tahap optimasi.

## 1. Persiapan

1. Install **MetaTrader 5** dari broker mana saja (untuk keperluan tugas/edukasi, akun **demo** sudah cukup — tidak perlu akun real).
2. Buka MT5, lalu buka **MetaEditor**:
   - Klik ikon buku kecil di toolbar (biasanya di kiri atas), **atau**
   - Menu **Tools/Extras → MetaQuotes Language Editor** (tombol F4).

## 2. Memasukkan File EA ke MT5

1. Di MetaEditor, klik **File → Open Data Folder** dari MT5 (bukan MetaEditor) — atau di MT5: klik kanan pada **Expert Advisors** di jendela **Navigator** → **Open Folder**. Ini akan membuka folder `MQL5/Experts/`.
2. Salin file `.mq5` (misalnya `EA01_MA_Crossover.mq5`) dari folder `EAs/` repo ini ke dalam folder `MQL5/Experts/` tersebut (atau ke dalam sub-folder buatan sendiri, mis. `MQL5/Experts/Tugas10EA/`).
3. Kembali ke MetaEditor, di panel **Navigator** sebelah kiri, cari file yang baru disalin, lalu double-click untuk membukanya.
4. Klik tombol **Compile** (atau tekan **F7**).
   - Lihat panel **Errors** di bagian bawah. Target: **"0 error(s), 0 warning(s)"**.
   - Jika ada error, baca pesannya (biasanya menyebutkan nomor baris) dan perbaiki sebelum lanjut.
5. Setelah compile sukses, akan muncul file `.ex5` dengan nama yang sama di folder yang sama — ini file yang benar-benar dijalankan MT5.

## 3. Menjalankan Strategy Tester (Backtest Biasa)

1. Di MT5, buka **Strategy Tester**: menu **View → Strategy Tester**, atau tekan **Ctrl+R**.
2. Di tab **Settings** (atau bagian atas jendela tester):
   - **Expert Advisor**: pilih EA yang tadi sudah di-compile (mis. `EA01_MA_Crossover`).
   - **Symbol**: pilih pair yang ingin diuji, mis. `EURUSD`.
   - **Period** (timeframe): mis. `M15` atau `H1`.
   - **Date range**: centang **Custom period**, tentukan tanggal awal-akhir (mis. 1 tahun terakhir), supaya hasil reproducible dan bisa dibandingkan antar-EA.
   - **Model**: pilih **"Every tick based on real ticks"** untuk hasil paling akurat (lebih lambat), atau **"1 minute OHLC"** untuk uji cepat awal.
   - **Deposit**: mis. 10000 (mata uang sesuai broker, biasanya USD).
   - **Optimization**: pastikan **"Disabled"** dulu untuk backtest tunggal (mode optimization dijelaskan di bagian 4).
3. Klik tab **Inputs** untuk mengecek/mengubah parameter EA (mis. `InpFastMAPeriod`, `InpSlowMAPeriod`, `InpMagicNumber`, dll.) sebelum menjalankan.
4. Klik tombol **Start** (▶) di kanan bawah jendela tester.
5. Tunggu proses selesai (progress bar di bawah). Untuk data historis yang belum ada, MT5 akan otomatis mengunduhnya (butuh koneksi internet).

## 4. Membaca Hasil — "Berhasil" vs "Tidak"

Setelah selesai, cek beberapa tab hasil:

- **Tab Journal / Experts** (log teks): pastikan tidak ada pesan `ERROR` dari EA sendiri (mis. `"Buy() failed"`), dan pastikan muncul log normal seperti pesan inisialisasi EA serta pesan sinyal (`"Fast MA crossed ABOVE Slow MA -> BUY signal"` pada EA01).
- **Tab Results**: daftar semua transaksi yang dibuka/ditutup EA selama periode uji. Kalau kosong sama sekali, kemungkinan: parameter terlalu ketat, periode data terlalu pendek, atau ada bug logika (sinyal tidak pernah terpenuhi).
- **Tab Graph**: kurva ekuitas (equity curve). Idealnya naik dari kiri ke kanan meski ada naik-turun; kurva yang datar/nol total berarti EA tidak melakukan apa-apa.
- **Tab Backtest / Report** (klik kanan pada Results/Graph → **Report** → **Open XML/HTML**, atau menu di pojok kanan atas hasil), berisi ringkasan angka penting:
  - **Total Net Profit** — untung/rugi bersih.
  - **Profit Factor** — total profit dibagi total loss; > 1 berarti EA secara historis untung.
  - **Maximum Drawdown** — penurunan terbesar dari puncak ekuitas; makin kecil makin baik/terkendali risikonya.
  - **Total Trades** — jumlah transaksi; jumlah yang terlalu sedikit (misal < 20-30) membuat kesimpulan "profitable" kurang bisa dipercaya secara statistik.
  - **Sharpe Ratio / Expected Payoff** — indikator tambahan kualitas strategi.

**Kriteria minimal "EA berhasil di tahap ini" (sebelum optimasi):**
1. Compile tanpa error/warning.
2. Saat backtest, EA benar-benar membuka minimal beberapa transaksi (bukan nol).
3. Tidak ada pesan error runtime di tab Journal/Experts (order gagal terus-menerus, dsb.).
4. Equity curve bergerak (naik/turun mengikuti trade), bukan garis datar dari awal sampai akhir.

Kalau keempat hal ini terpenuhi, EA sudah "jalan dengan benar" dan siap masuk tahap optimasi. Profitable atau tidaknya parameter default itu **baru ditentukan lewat proses optimasi**, bukan syarat kelulusan tahap ini.

## 5. Optimasi Parameter (Tahap Lanjutan)

1. Di jendela **Strategy Tester**, ubah **Optimization** dari `Disabled` menjadi `Slow complete algorithm` (uji semua kombinasi, lebih lambat tapi menyeluruh) atau `Fast genetic based algorithm` (lebih cepat, untuk banyak parameter).
2. Di tab **Inputs**, untuk tiap parameter yang ingin dioptimasi (mis. `InpFastMAPeriod`, `InpSlowMAPeriod`, `InpStopLossPts`, `InpTakeProfitPts`):
   - Centang kotak kecil di kolom paling kiri parameter tersebut.
   - Isi kolom **Start**, **Step**, **Stop** (misalnya Fast MA: Start=10, Step=5, Stop=50).
3. Di tab **Settings**, pada bagian **Optimization criterion**, pilih metrik yang ingin dimaksimalkan, misalnya **Balance**, **Profit Factor**, atau **Custom max**. Untuk tugas ini, `Balance` atau `Profit Factor` sudah cukup sebagai titik awal.
4. Klik **Start**. MT5 akan menjalankan ribuan kombinasi dan menampilkan tabel hasil di tab **Optimization Results**, bisa diurutkan per kolom (klik header kolom, mis. urutkan berdasarkan Profit Factor tertinggi).
5. **Penting — hindari overfitting:**
   - Jangan langsung pakai kombinasi parameter dengan profit tertinggi begitu saja.
   - Bagi periode data jadi dua: mis. optimasi di data 2022-2023 (**in-sample**), lalu uji ulang (**tanpa optimasi**, cukup backtest biasa) kombinasi parameter terbaik itu di data 2024-2025 (**out-of-sample/forward test**).
   - Jika hasil di data out-of-sample masih wajar (profit factor tetap > 1, drawdown tidak meledak), parameter tersebut lebih layak dipercaya dibanding yang hanya bagus di data yang sama dipakai optimasi.
6. Catat parameter final + screenshot report untuk tiap EA yang lolos kriteria di atas, simpan di folder `results/`.

## 6. Troubleshooting Umum

| Gejala | Kemungkinan Penyebab |
|---|---|
| EA tidak muncul di daftar Navigator/Tester | File belum di-compile, atau disalin ke folder yang salah, atau perlu restart MT5/refresh Navigator (klik kanan → Refresh). |
| "0 error(s)" tapi tidak ada transaksi sama sekali | Kondisi sinyal terlalu jarang terpenuhi (mis. periode MA terlalu panjang dibanding rentang tanggal uji), atau `CopyBuffer` gagal karena histori data kurang — coba perpanjang rentang tanggal atau kurangi periode MA. |
| Order gagal terus (`ERROR: Buy() failed`) | Broker/simbol demo mungkin butuh volume lot minimum berbeda, atau jarak SL/TP terlalu dekat — cek `Symbol Properties` di Market Watch untuk volume & stop level minimum. |
| Hasil optimasi "terlalu bagus untuk jadi nyata" | Kemungkinan overfitting — selalu validasi dengan forward test di data yang tidak dipakai optimasi. |
