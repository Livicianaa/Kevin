#!/usr/bin/env bash
# Kevin'in ses motorlarini (Piper TTS + whisper.cpp STT) bin/ altina kurar.
# Bu dosyalar buyuk oldugu icin git'e girmiyor; repoyu klonlayan bunu bir kez calistirir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PIPER_VERSION="2023.11.14-2"
PIPER_VOICE="${PIPER_VOICE:-tr_TR-dfki-medium}"
WHISPER_MODEL="${WHISPER_MODEL:-ggml-small-q5_1.bin}"

# tr_TR-fahrettin-medium -> locale=tr_TR, dil=tr, konusmaci=fahrettin, kalite=medium
VOICE_LOCALE="${PIPER_VOICE%%-*}"
VOICE_LANG="${VOICE_LOCALE%%_*}"
VOICE_QUALITY="${PIPER_VOICE##*-}"
VOICE_REST="${PIPER_VOICE#*-}"
VOICE_SPEAKER="${VOICE_REST%-*}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "eksik komut: $1"; exit 1; }; }

need curl
need tar

if [ -x "$BIN/piper/piper" ]; then
  say "Piper zaten kurulu, atlaniyor"
else
  say "Piper (TTS) indiriliyor"
  mkdir -p "$BIN"
  curl -fL -o "$WORK/piper.tar.gz" \
    "https://github.com/rhasspy/piper/releases/download/$PIPER_VERSION/piper_linux_x86_64.tar.gz"
  tar -xzf "$WORK/piper.tar.gz" -C "$BIN"
fi

VOICE_DIR="$BIN/piper-voices/$PIPER_VOICE"
if [ -f "$VOICE_DIR/$PIPER_VOICE.onnx" ]; then
  say "Ses modeli zaten var, atlaniyor"
else
  say "Ses modeli indiriliyor: $PIPER_VOICE"
  mkdir -p "$VOICE_DIR"
  BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/$VOICE_LANG/$VOICE_LOCALE/$VOICE_SPEAKER/$VOICE_QUALITY"
  curl -fL -o "$VOICE_DIR/$PIPER_VOICE.onnx" "$BASE/$PIPER_VOICE.onnx"
  curl -fL -o "$VOICE_DIR/$PIPER_VOICE.onnx.json" "$BASE/$PIPER_VOICE.onnx.json"
fi

if [ -x "$BIN/whisper/whisper-cli" ]; then
  say "whisper.cpp zaten kurulu, atlaniyor"
else
  say "whisper.cpp derleniyor (cmake + derleyici gerekiyor)"
  need git
  need cmake
  git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$WORK/whisper.cpp"
  cmake -S "$WORK/whisper.cpp" -B "$WORK/whisper.cpp/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
  cmake --build "$WORK/whisper.cpp/build" -j"$(nproc)"
  mkdir -p "$BIN/whisper"
  cp "$WORK/whisper.cpp/build/bin/whisper-cli" "$BIN/whisper/"
  find "$WORK/whisper.cpp/build" -name 'libggml*.so*' -o -name 'libwhisper*.so*' | while read -r lib; do
    cp -a "$lib" "$BIN/whisper/"
  done
fi

if [ -f "$BIN/whisper-models/$WHISPER_MODEL" ]; then
  say "Whisper modeli zaten var, atlaniyor"
else
  say "Whisper modeli indiriliyor: $WHISPER_MODEL"
  mkdir -p "$BIN/whisper-models"
  curl -fL -o "$BIN/whisper-models/$WHISPER_MODEL" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL"
fi

say "Kurulum bitti"
printf 'Piper   : %s\n' "$BIN/piper/piper"
printf 'Ses     : %s\n' "$VOICE_DIR/$PIPER_VOICE.onnx"
printf 'Whisper : %s\n' "$BIN/whisper/whisper-cli"
printf 'Model   : %s\n' "$BIN/whisper-models/$WHISPER_MODEL"
