# Kevin (PC Version)

Masaustunde yasayan, cagrildiginda konusan AI karakter. Electron tabanli, Windows + Linux hedefli.

## Faz durumu

- **Faz 0:** Transparan overlay pencere -> kose-ankorlu kucuk pencereye gecildi (Wayland click-through sorunu yuzunden). Placeholder karakter (`renderer/assets/kevin.png`).
- **Faz 1a:** LLM baglantisi (kullanici kendi API key'ini girer - NVIDIA/Groq), metin sohbeti. TAMAM.
- **Faz 1b (bu commit):** Sesli sohbet - mikrofon kaydi -> whisper.cpp (STT) -> LLM -> Piper (TTS) -> sesli cevap. Dil secimi UI'i henuz yok (sabit Turkce).
- **Faz 2:** Ekran/kamera gorme (vision), davranis genisletme.
- **Faz 3:** Arka planda konusma ozetleme / hafiza sistemi.

## Calistirma

```bash
npm install
npm start
```

## bin/ klasoru (gitignored)

Piper (TTS) ve whisper.cpp (STT) binary'leri + model dosyalari `bin/` altinda,
buyuk olduklari icin git'e girmiyor. Bu repo'yu yeni bir yerde calistirmak icin:

- `bin/piper/` - Piper binary + .so dosyalari + `espeak-ng-data/`
- `bin/piper-voices/tr_TR-fahrettin-medium/` - Turkce ses modeli (.onnx + .onnx.json)
- `bin/whisper/` - whisper.cpp'den derlenen `whisper-cli` + `libggml*`/`libwhisper*` .so dosyalari
- `bin/whisper-models/ggml-base.bin` - cok dilli whisper modeli

Kaynak: Piper https://github.com/rhasspy/piper , whisper.cpp https://github.com/ggerganov/whisper.cpp
(derleme: `cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j`).
Otomatik kurulum scripti henuz yazilmadi - acik is.
