# Kevin

**Türkçe** · [English](docs/readme/README.en.md) · [Español](docs/readme/README.es.md) · [Français](docs/readme/README.fr.md) · [Deutsch](docs/readme/README.de.md) · [Português](docs/readme/README.pt.md) · [Русский](docs/readme/README.ru.md) · [العربية](docs/readme/README.ar.md) · [हिन्दी](docs/readme/README.hi.md) · [اردو](docs/readme/README.ur.md) · [Bahasa Indonesia](docs/readme/README.id.md)

Masaüstünde yaşayan, konuşan, seni tanıyan ve bilgisayarını kullanabilen yapay zeka arkadaşı.
Minecraft görünümlü 3B bir karakter: ekranında gezinir, kenara yaslanıp oturur, onu tutup
fırlatabilirsin. Adını söyleyince döner ve sesli konuşur.

<p align="center"><img src="docs/gorseller/menu.png" width="520" alt="Kevin ve menüsü"></p>

## İndir

[Son sürüm (Releases)](https://github.com/Livicianaa/Kevin/releases/latest) sayfasından:

| Sistem | Dosya | Nasıl açılır |
|---|---|---|
| Windows 10/11 | `Kevin-Kurulum.exe` | Kurulumu çalıştır. Masaüstünde Kevin kısayolu çıkar. |
| Windows (kurulumsuz) | `Kevin-Windows.zip` | Zip'i bir klasöre çıkar, `Kevin\Kevin.exe`'ye çift tıkla. |
| Linux | `Kevin-x86_64.AppImage` | Dosyaya sağ tık > Özellikler > "Çalıştırılabilir" işaretle, sonra çift tıkla. Terminalden: `chmod +x Kevin-x86_64.AppImage && ./Kevin-x86_64.AppImage` |

Windows "Windows bilgisayarınızı korudu" derse "Ek bilgi" > "Yine de çalıştır".

İlk açılışta Kevin birkaç saniye hazırlanır (açılış ekranı), sonra masaüstüne düşer.

## İlk kurulum: yapay zeka anahtarı

Kevin'in konuşabilmesi için bir yapay zeka servisine bağlanması gerekir. Herkes kendi anahtarını
kullanır; anahtar sadece senin bilgisayarında saklanır.

1. Kevin ilk açılışta ayarlarını kendisi açar (sonra istediğin zaman: karaktere **sağ tık** > **Yapay Zeka**).
2. Sağlayıcı seç ve **Anahtar al** bağlantısına tıkla. Groq'ta ücretsiz anahtar:
   [console.groq.com/keys](https://console.groq.com/keys)
3. Anahtarı yapıştır. Model listesi kendiliğinden gelir; anahtar doğruysa "Bağlandı" yazar.
4. **Kaydet**.

İnternetsiz kullanmak istersen **Yerel (Ollama)** seç: [Ollama](https://ollama.com/download) kur ve
bir model indir (`ollama pull qwen3:8b`).

## Neler yapabilirsin

- **"Kevin"** diye seslen (ya da karaktere orta tıkla), sonra konuş: "hava nasıl?", "YouTube'da lo-fi aç",
  "ekranıma bak, bu ne?"
- **Kendinden bahset:** "benim adım Ali, kahveyi şekersiz içerim". Hatırlar; yanlış bir şey derse düzelt,
  öğrenir. Bildiklerini menüde Sohbet sayfasında görür, istediğini sildirirsin.
- **Kod yazdır:** "zar atan bir Python kodu yaz". Kodu sesli okumaz, kendi penceresinde harf harf yazar.
- **Kamera** (ayarlardan açılırsa): "bana bak", "bu benim, beni hatırla", "elimdeki ne?"
- **Müzik:** bir şarkı açınca dans eder (video izlerken etmez). Konuşurken duygusuna göre hareket eder.
- **Fizik:** tut, sürükle, fırlat; kolundan yavaşça çek, sendeler. Düşünce kendi kalkar.
- **Menü (sağ tık):** skin ekle (64x64 Minecraft skin, `+`), boyut, dil, davranış ayarları.
  Esc ile kapanır.
- **11 dil:** Türkçe, English, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी, اردو,
  Bahasa Indonesia. Seçilen dilin sesi ilk seferde indirilir (~60 MB).

## Sistem gereksinimleri

- 64 bit Linux ya da Windows 10/11, mikrofon, hoparlör
- 8 GB RAM önerilir. Kevin her açılışta bilgisayarını ölçer; zayıf makinede daha az hareket eder ve
  daha düşük kare hızında çalışır.
- Yapay zeka için internet (ya da yerelde Ollama)

## Bilinen kısıtlar

- **Windows:** müzikte dans, ekranı kontrol etme ve kamera şimdilik sadece Linux'ta çalışıyor.
  Sohbet, ses, menü, skinler ve fizik Windows'ta da var.
- **Linux:** en çok Hyprland üzerinde denendi. Başka masaüstlerinde pencere şeffaflığı ve
  "her zaman üstte" davranışı masaüstüne göre değişebilir.
- Paketlerde Fresh Animations yok (lisansı yeniden dağıtıma izin vermiyor); Kevin yerleşik
  animasyonlarla yürür. Kendi Fresh Animations paketin varsa `player.jem` dosyasını uygulamanın
  `bin/cem/` klasörüne koyabilirsin.

## Ayarlar ve veriler nerede?

| | Linux | Windows |
|---|---|---|
| Ayarlar, anahtar, hafıza, sohbet geçmişi, skinler | `~/.config/kevin-pc-version/` | `%APPDATA%\kevin-pc-version\` |

Kevin'i sıfırlamak için bu klasörü silmen yeterli.

## Kaynaktan çalıştırma (geliştirici)

Kevin iki parçadan oluşur: **gövde** (`body/`, Godot 4.7 + Jolt fizik) ve **beyin** (Electron: ses,
sohbet, araçlar). Gövde beyni kendisi başlatır.

```bash
npm install
npm run build:skin           # renderer/skin-viewer-bundle.js
body/run.sh                  # Godot 4.7.2 gerekir (godot ya da ~/.local/bin/godot)
```

`bin/` klasörü büyük olduğu için git'te yok:

- `bin/piper/` + `bin/piper-voices/tr_TR-fahrettin-medium/`: [Piper](https://github.com/rhasspy/piper) ses
- `bin/whisper/` + `bin/whisper-models/ggml-small-q5_1.bin`: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) ses tanıma
- İsteğe bağlı: `scripts/setup-whisper-gpu.sh` ile ekran kartında ses tanıma (Vulkan)

Testler (pencere ekranına düşmez, gizli çalışma alanında açılır): `body/test.sh --menu=karakter --shot=/tmp/x`

Paket üretme: `scripts/paketle.sh [linux|windows|hepsi]` → `dist/Kevin-x86_64.AppImage`, `dist/Kevin-Windows.zip`

## Teşekkürler

- Emote'lar: [Emotecraft emotes](https://github.com/KosmX/Emotecraft-emotes) (CC0)
- Kalkma animasyonu: Quaternius Universal Animation Library 2 (CC0)
- Ses: Piper (MIT), whisper.cpp (MIT) · Motor: Godot (MIT), Electron (MIT)
- Yazı tipleri: Anton (OFL), Noto

---

Created by Liviciana · Codemisk
