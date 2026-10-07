# Kevin

[Türkçe](../../README.md) · [English](README.en.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md) · [اردو](README.ur.md) · **Bahasa Indonesia**

Teman AI yang tinggal di desktopmu, bisa bicara, mengenalmu, dan memakai komputermu.
Karakter 3D bergaya Minecraft: berjalan-jalan di layar, duduk bersandar di tepi, dan kamu bisa
memegang lalu melemparnya. Sebut namanya, dia akan menoleh dan berbicara.

<p align="center"><img src="../gorseller/menu.png" width="520" alt="Kevin"></p>

## Unduh

Dari [rilis terbaru](https://github.com/Livicianaa/Kevin/releases/latest):

| Sistem | Berkas | Cara membuka |
|---|---|---|
| Windows 10/11 | `Kevin-Kurulum.exe` | Jalankan pemasang. Pintasan Kevin muncul di desktop. |
| Windows (tanpa pasang) | `Kevin-Windows.zip` | Ekstrak ke sebuah folder, klik dua kali `Kevin\Kevin.exe`. |
| Linux | `Kevin-x86_64.AppImage` | Klik kanan > Properties > tandai bisa dieksekusi, lalu klik dua kali. Terminal: `chmod +x Kevin-x86_64.AppImage && ./Kevin-x86_64.AppImage` |

Jika Windows menampilkan "Windows protected your PC", pilih "More info" > "Run anyway".
Saat pertama dibuka Kevin bersiap beberapa detik (layar pembuka), lalu jatuh ke desktopmu.

## Pengaturan pertama: kunci AI

Kevin butuh layanan AI untuk bicara. Tiap orang memakai kuncinya sendiri; kunci hanya disimpan di komputermu.

1. Saat pertama dibuka Kevin membuka pengaturannya sendiri (nanti: **klik kanan** karakter > **AI**).
2. Pilih penyedia dan klik **Ambil kunci**. Kunci gratis di Groq: [console.groq.com/keys](https://console.groq.com/keys)
3. Tempel kuncinya. Daftar model muncul sendiri; jika kuncinya benar akan tertulis "Terhubung".
4. **Simpan**.

Tanpa internet: pilih **Lokal (Ollama)**, pasang [Ollama](https://ollama.com/download) dan unduh model
(`ollama pull qwen3:8b`).

## Yang bisa dicoba

- Panggil **"Kevin"** (atau klik tengah dia), lalu bicara: "cuacanya gimana?", "putar lo-fi di YouTube",
  "lihat layarku, ini apa?"
- **Ceritakan tentang dirimu:** "namaku Ali, aku minum kopi tanpa gula". Dia ingat; koreksi dia, dia belajar.
  Di halaman Obrolan pada menu kamu bisa melihat dan menghapus yang dia tahu.
- **Minta kode:** "tulis pelempar dadu Python". Dia tidak membacakannya, tapi mengetiknya huruf demi huruf di jendelanya.
- **Kamera** (jika diaktifkan): "lihat aku", "ini aku, ingat aku", "aku pegang apa?"
- **Musik:** putar lagu, dia menari (tidak untuk video). Saat bicara dia bergerak sesuai suasana hati.
- **Fisika:** pegang, seret, lempar; tarik lengannya pelan, dia tersandung. Setelah jatuh dia bangun sendiri.
- **Menu (klik kanan):** tambah skin (skin Minecraft 64x64, `+`), ukuran, bahasa, perilaku. Esc menutup.
- **11 bahasa:** Türkçe, English, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी, اردو,
  Bahasa Indonesia. Suara tiap bahasa diunduh saat pertama dipilih (~60 MB).

## Kebutuhan

- Linux 64-bit atau Windows 10/11, mikrofon, speaker
- Disarankan RAM 8 GB. Kevin mengukur komputermu tiap kali dibuka; di mesin yang lebih lemah dia lebih jarang bergerak
  dan berjalan dengan fps lebih rendah.
- Internet untuk AI (atau Ollama lokal)

## Batasan yang diketahui

- **Windows:** menari mengikuti musik, kontrol layar, dan kamera untuk sementara hanya di Linux. Obrolan, suara,
  menu, skin, dan fisika juga jalan di Windows.
- **Linux:** paling banyak diuji di Hyprland. Di desktop lain, transparansi dan "selalu di atas" bisa berbeda.
- Fresh Animations tidak disertakan (lisensinya melarang distribusi ulang); Kevin berjalan dengan animasi bawaan.
  Jika kamu punya, taruh `player.jem` di folder `bin/cem/` aplikasi.

## Di mana pengaturan dan data?

| | Linux | Windows |
|---|---|---|
| Pengaturan, kunci, ingatan, riwayat, skin | `~/.config/kevin-pc-version/` | `%APPDATA%\kevin-pc-version\` |

Hapus folder ini untuk mengatur ulang Kevin.

## Dari kode sumber (pengembang)

Kevin terdiri dari dua bagian: **tubuh** (`body/`, Godot 4.7 + fisika Jolt) dan **otak** (Electron: suara,
obrolan, alat). Tubuh menyalakan otak sendiri.

```bash
npm install
npm run build:skin
body/run.sh
```

`bin/` (suara Piper, pengenalan whisper.cpp dan modelnya) tidak ada di git karena ukurannya; daftarnya ada di
[README bahasa Turki](../../README.md). Paket: `scripts/paketle.sh [linux|windows|hepsi]`.

## Terima kasih

Emotecraft emotes (CC0), Quaternius Universal Animation Library 2 (CC0), Piper (MIT), whisper.cpp (MIT),
Godot (MIT), Electron (MIT), Anton (OFL), Noto.

---

Created by Liviciana · Codemisk
