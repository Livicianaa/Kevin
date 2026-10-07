#!/usr/bin/env bash
# whisper.cpp'yi ekran karti (Vulkan) destegiyle bin/whisper-gpu/ altina derler
# ve daha dogru large-v3-turbo modelini indirir. Kevin bu klasoru gorurse ses
# tanimayi GPU'da turbo modelle yapar; yoksa CPU'da small modelle devam eder
# (turbo CPU'da ~5 kat yavas, kullanilmiyor).
#
# Derleme dusuk oncelikte ve 4 cekirdekle: arka planda calisirken bilgisayar
# kilitlenmesin (12 cekirdekle shader derlemesi masaustunu 3 FPS'e dusuruyordu).
# Gereken: cmake, git, vulkan-headers, shaderc (glslc). SPIRV-Headers sistemde
# yoksa kaynaktan gecici olarak alinir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/bin/whisper-gpu"
MODEL="$ROOT/bin/whisper-models/ggml-large-v3-turbo-q5_0.bin"
JOBS="${JOBS:-4}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "eksik: $1"; exit 1; }; }
need git
need cmake
need glslc

PREFIX_ARGS=()
if ! pacman -Q spirv-headers >/dev/null 2>&1 && [ ! -d /usr/include/spirv/unified1 ]; then
  say "SPIRV-Headers kaynaktan aliniyor (sadece basliklar)"
  git clone -q --depth 1 https://github.com/KhronosGroup/SPIRV-Headers "$WORK/spirv"
  cmake -S "$WORK/spirv" -B "$WORK/spirv/build" -DCMAKE_INSTALL_PREFIX="$WORK/prefix" -DSPIRV_HEADERS_ENABLE_TESTS=OFF >/dev/null
  cmake --install "$WORK/spirv/build" >/dev/null
  # CMake paketi buluyor ama ggml-vulkan baslik yolunu derleyiciye gecmiyor
  PREFIX_ARGS=(-DCMAKE_PREFIX_PATH="$WORK/prefix" -DCMAKE_CXX_FLAGS="-I$WORK/prefix/include")
fi

say "whisper.cpp indiriliyor"
git clone -q --depth 1 https://github.com/ggerganov/whisper.cpp "$WORK/whisper.cpp"

say "Derleniyor (Vulkan, $JOBS cekirdek, dusuk oncelik; birkac dakika)"
nice -n 19 cmake -S "$WORK/whisper.cpp" -B "$WORK/whisper.cpp/build" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON -DGGML_VULKAN=ON -DWHISPER_BUILD_TESTS=OFF "${PREFIX_ARGS[@]}" >/dev/null
nice -n 19 cmake --build "$WORK/whisper.cpp/build" -j"$JOBS" --target whisper-cli

mkdir -p "$OUT"
cp "$WORK/whisper.cpp/build/bin/whisper-cli" "$OUT/"
find "$WORK/whisper.cpp/build" \( -name 'libggml*.so*' -o -name 'libwhisper*.so*' \) -exec cp -P {} "$OUT/" \;

if [ ! -f "$MODEL" ]; then
  say "large-v3-turbo modeli indiriliyor (~550 MB)"
  curl -fL -o "$MODEL.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
  mv "$MODEL.part" "$MODEL"
fi

say "Deneme"
LD_LIBRARY_PATH="$OUT" "$OUT/whisper-cli" --help >/dev/null && echo "Tamam: Kevin'i yeniden baslatinca ses tanima GPU'da calisir."
