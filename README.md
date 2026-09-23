# Kevin (PC Version)

Masaustunde yasayan, cagrildiginda konusan AI karakter. Electron tabanli, Windows + Linux hedefli.
LLM icin kullanici kendi API key'ini girer (NVIDIA NIM / Groq / Gemini) - sunucu maliyeti yok.

## Faz durumu

- **Faz 0:** Transparan overlay pencere -> kose-ankorlu kucuk pencereye gecildi (Wayland click-through sorunu yuzunden).
- **Faz 1a:** LLM baglantisi, metin sohbeti. TAMAM.
- **Faz 1b:** Eller serbest sesli sohbet - VAD ile uyanma kelimesi -> whisper.cpp (STT) -> LLM -> Piper (TTS). TAMAM.
  Dil secimi UI'i henuz yok (sabit Turkce).
- **Faz 2:** Agent modu (MCP `computer-use-linux` + kendi araclarimiz) TAMAM. Vision (ekrani gorme) henuz yok.
- **Karakter animasyonlari:** 3D Minecraft rig'i uzerine durum makinesi. TAMAM - bkz. `docs/CHARACTER-SPEC.md`.
- **Faz 3:** Arka planda konusma ozetleme / hafiza sistemi. Yapilmadi.

## Calistirma

```bash
npm install
npm run build:skin     # renderer/skin-viewer-bundle.js uretir (gitignored)
npm start
```

Tek bir animasyonu incelemek icin:

```bash
npm start -- --anim=dance
npm start -- --anim=idle:sit
```

Animasyon motorunun regresyon testi (tarayici gerektirmez):

```bash
npm test
```

## bin/ klasoru (gitignored)

Piper (TTS) ve whisper.cpp (STT) binary'leri + model dosyalari `bin/` altinda,
buyuk olduklari icin git'e girmiyor. Bu repo'yu yeni bir yerde calistirmak icin:

- `bin/piper/` - Piper binary + .so dosyalari + `espeak-ng-data/`
- `bin/piper-voices/tr_TR-fahrettin-medium/` - Turkce ses modeli (.onnx + .onnx.json)
- `bin/whisper/` - whisper.cpp'den derlenen `whisper-cli` + `libggml*`/`libwhisper*` .so dosyalari
- `bin/whisper-models/ggml-small-q5_1.bin` - cok dilli whisper modeli (nicelenmis)

Kaynak: Piper https://github.com/rhasspy/piper , whisper.cpp https://github.com/ggerganov/whisper.cpp
(derleme: `cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j`).
Otomatik kurulum scripti henuz yazilmadi - acik is.

## Bilinen sorunlar

- Linux'ta `chrome-sandbox` setuid olmadigi icin `--no-sandbox` ile calisiyor; dagitimdan once cozulmeli.
- Olcek faktoru 1 olmayan ekranda (ornegin Hyprland `scale 1.5`) pencere yanlis boyutta ve
  yanlis konumda aciliyor - Electron'un Wayland konumlandirmasi guvenilir degil.
- Hyprland'de global `blur` acikken transparan pencereye de bulasiyor; compositor karari, uygulama cozemiyor.

---

Created by Liviciana
