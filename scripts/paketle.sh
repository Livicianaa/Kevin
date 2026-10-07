#!/usr/bin/env bash
# Kevin'i baskasina gondermek icin paketler:
#   dist/Kevin-x86_64.AppImage   (Linux, cift tikla calisir)
#   dist/Kevin-Windows.zip       (ac, Kevin klasorundeki Kevin.exe)
#   dist/Kevin-Kurulum.exe       (Windows kurulum programi; wine gerekir)
#
# Kullanim: scripts/paketle.sh [linux|windows|hepsi]
#   KEVIN_PAKET_CEM=1  Fresh Animations (bin/cem/player.jem) da girsin. Varsayilan
#                      KAPALI: paketin lisansi yeniden dagitima izin vermiyor;
#                      yoksa Kevin yerlesik animasyonlarla calisir.
#
# Gereken indirmeler dist/indirilenler/ altinda (betik eksikleri indirir).
# Godot disa aktarma sablonu kullanilmiyor: Godot calistiricisi projeyle
# birlikte paketleniyor (Kevin gelistirmede de boyle calisiyor).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
DL="$DIST/indirilenler"
HEDEF="${1:-hepsi}"
ELECTRON_VER="$(node -p "require('$ROOT/node_modules/electron/package.json').version")"
GODOT_VER="4.7.2"
WHISPER_TAG="b5454"
SURUM="$(node -p "require('$ROOT/package.json').version")-$(git -C "$ROOT" rev-parse --short HEAD)"

indir() {
  local url="$1" ad
  ad="$(basename "$url")"
  mkdir -p "$DL"
  if [ ! -s "$DL/$ad" ]; then
    echo "indiriliyor: $ad"
    curl -sSfL --max-time 900 -o "$DL/$ad.part" "$url"
    mv "$DL/$ad.part" "$DL/$ad"
  fi
}

# Uygulama dosyalari (iki platformda ortak) + platforma ozel ses programlari
uygulama() {
  local hedef="$1" os="$2"
  mkdir -p "$hedef"
  cp "$ROOT"/{main,preload,akil,langs,beat,browser,hypr,platform}.js "$ROOT/package.json" "$hedef/"
  rsync -a --exclude skin-viewer-src.js "$ROOT/renderer/" "$hedef/renderer/"
  rsync -a --exclude '.godot/editor' --exclude 'tools' "$ROOT/body/" "$hedef/body/"
  local haric=(--exclude electron --exclude esbuild --exclude @esbuild --exclude @types --exclude .bin)
  [ "$os" = windows ] && haric+=(--exclude @agent-sh)
  rsync -a "${haric[@]}" "$ROOT/node_modules/" "$hedef/node_modules/"

  mkdir -p "$hedef/bin/piper-voices" "$hedef/bin/whisper-models" "$hedef/bin/emotes"
  cp -r "$ROOT/bin/piper-voices/tr_TR-fahrettin-medium" "$hedef/bin/piper-voices/"
  cp "$ROOT/bin/whisper-models/ggml-small-q5_1.bin" "$hedef/bin/whisper-models/"
  if [ "${KEVIN_PAKET_CEM:-0}" = 1 ] && [ -f "$ROOT/bin/cem/player.jem" ]; then
    mkdir -p "$hedef/bin/cem" && cp "$ROOT/bin/cem/player.jem" "$hedef/bin/cem/"
  fi

  if [ "$os" = linux ]; then
    cp -r "$ROOT/bin/piper" "$hedef/bin/piper"
    # Arch'ta derlenen whisper eski glibc'li dagitimlarda acilmayabilir:
    # Ubuntu'da derlenmis resmi surum
    indir "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER_TAG/whisper-bin-ubuntu-x64.tar.gz"
    local tmp; tmp="$(mktemp -d)"
    tar xzf "$DL/whisper-bin-ubuntu-x64.tar.gz" -C "$tmp"
    mkdir -p "$hedef/bin/whisper"
    cp -a "$tmp"/whisper-bin-ubuntu-x64/whisper-cli "$tmp"/whisper-bin-ubuntu-x64/lib*.so* "$hedef/bin/whisper/"
    rm -rf "$tmp"
  else
    indir "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip"
    indir "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER_TAG/whisper-bin-x64.zip"
    unzip -q -o "$DL/piper_windows_amd64.zip" -d "$hedef/bin/"
    local tmp; tmp="$(mktemp -d)"
    unzip -q -o "$DL/whisper-bin-x64.zip" -d "$tmp"
    mkdir -p "$hedef/bin/whisper"
    cp "$tmp"/Release/whisper-cli.exe "$tmp"/Release/*.dll "$hedef/bin/whisper/"
    rm -rf "$tmp"
  fi
}

linux() {
  echo "== Linux AppImage"
  local appdir="$DIST/linux/Kevin.AppDir"
  rm -rf "$DIST/linux" && mkdir -p "$appdir/godot"
  cp -a "$ROOT/node_modules/electron/dist" "$appdir/kevin"
  mv "$appdir/kevin/electron" "$appdir/kevin/kevin"
  rm -f "$appdir/kevin/resources/default_app.asar"
  uygulama "$appdir/kevin/resources/app" linux
  cp "$(readlink -f "$(command -v godot || echo "$HOME/.local/bin/godot")")" "$appdir/godot/godot"
  echo "$SURUM" > "$appdir/SURUM"
  cp "$ROOT/body/ui/kevin-icon.png" "$appdir/kevin.png"
  cat > "$appdir/kevin.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Kevin
Comment=Masaustunde yasayan yapay zeka arkadasi
Exec=AppRun
Icon=kevin
Categories=Utility;
Terminal=false
EOF
  cat > "$appdir/AppRun" <<'EOF'
#!/usr/bin/env bash
# AppImage salt okunur: govde (Godot projesi) kullanicinin klasorune kopyalanir,
# Godot oradan calisir; beyin (Electron) paketin icinden acilir.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/kevin-pc-version"
SURUM="$(cat "$HERE/SURUM")"
if [ "$(cat "$DATA/body/.kevin-surum" 2>/dev/null || true)" != "$SURUM" ]; then
  rm -rf "$DATA/body"
  mkdir -p "$DATA"
  cp -r "$HERE/kevin/resources/app/body" "$DATA/body"
  chmod -R u+w "$DATA/body"
  echo "$SURUM" > "$DATA/body/.kevin-surum"
fi
export KEVIN_ROOT="$HERE/kevin/resources/app"
export KEVIN_ELECTRON="$HERE/kevin/kevin"
export GODOT="$HERE/godot/godot"
exec bash "$DATA/body/run.sh" "$@"
EOF
  chmod +x "$appdir/AppRun"
  indir "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$DL/appimagetool-x86_64.AppImage"
  ARCH=x86_64 "$DL/appimagetool-x86_64.AppImage" --appimage-extract-and-run --no-appstream \
    "$appdir" "$DIST/Kevin-x86_64.AppImage" >/dev/null
  echo "hazir: $DIST/Kevin-x86_64.AppImage ($(du -h "$DIST/Kevin-x86_64.AppImage" | cut -f1))"
}

windows() {
  echo "== Windows"
  local kok="$DIST/windows/Kevin"
  rm -rf "$DIST/windows" && mkdir -p "$kok/godot"
  indir "https://github.com/electron/electron/releases/download/v$ELECTRON_VER/electron-v$ELECTRON_VER-win32-x64.zip"
  indir "https://github.com/godotengine/godot/releases/download/$GODOT_VER-stable/Godot_v$GODOT_VER-stable_win64.exe.zip"
  unzip -q "$DL/electron-v$ELECTRON_VER-win32-x64.zip" -d "$kok"
  mv "$kok/electron.exe" "$kok/Kevin.exe"
  rm -f "$kok/resources/default_app.asar"
  uygulama "$kok/resources/app" windows
  local tmp; tmp="$(mktemp -d)"
  unzip -q "$DL/Godot_v$GODOT_VER-stable_win64.exe.zip" -d "$tmp"
  mv "$tmp/Godot_v$GODOT_VER-stable_win64.exe" "$kok/godot/godot.exe"
  rm -rf "$tmp"
  # Kevin.exe'nin ikonu (Electron logosu yerine Kevin)
  indir "https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe"
  python3 -c "from PIL import Image; Image.open('$ROOT/body/ui/kevin-icon.png').convert('RGBA').save('$DIST/windows/kevin.ico', sizes=[(256,256),(64,64),(48,48),(32,32),(16,16)])"
  if command -v wine >/dev/null; then
    WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wine "$DL/rcedit-x64.exe" "$kok/Kevin.exe" \
      --set-icon "$DIST/windows/kevin.ico" --set-version-string ProductName Kevin \
      --set-version-string FileDescription Kevin --set-version-string CompanyName Liviciana >/dev/null 2>&1 \
      || echo "uyari: ikon basilamadi"
  fi
  cat > "$kok/OKU-BENI.txt" <<'EOF'
Kevin - masaustunde yasayan yapay zeka arkadasi

1) Bu klasoru istedigin yere cikar (zip'in icinde calistirma).
2) Kevin.exe'ye cift tikla. Windows "bilinmeyen yayinci" derse
   "Ek bilgi" > "Yine de calistir".
3) Kevin acilinca karaktere sag tikla > Yapay Zeka: kendi API anahtarini
   gir (Groq ucretsiz: console.groq.com/keys) ya da Yerel (Ollama) sec.
4) Ne yapabilecegin: sag tik > Hakkinda.

Created by Liviciana
EOF
  rm -f "$DIST/Kevin-Windows.zip"
  (cd "$DIST/windows" && zip -qr -9 "$DIST/Kevin-Windows.zip" Kevin)
  echo "hazir: $DIST/Kevin-Windows.zip ($(du -h "$DIST/Kevin-Windows.zip" | cut -f1))"
  kurulum
}

# Tek dosyalik Windows kurulumu (Inno Setup, Wine'da): yonetici izni istemez,
# %LOCALAPPDATA%\Programs\Kevin'e kurar, baslat menusu + masaustu kisayolu,
# Programlar listesinden kaldirilir
kurulum() {
  command -v wine >/dev/null || { echo "uyari: wine yok, Kevin-Kurulum.exe atlandi"; return; }
  export WINEPREFIX="$DIST/wine-inno" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
  if [ ! -f "$WINEPREFIX/drive_c/inno/ISCC.exe" ]; then
    indir "https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/innosetup-7.1.0-x64.exe"
    wineboot -i >/dev/null 2>&1 || true
    wine "$DL/innosetup-7.1.0-x64.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER '/DIR=C:\inno' >/dev/null 2>&1
  fi
  sed "s/@SURUM@/$SURUM/" > "$DIST/windows/kevin.iss" <<'ISS'
[Setup]
AppId={{8C1F2A6E-4B7D-4E2A-9C1E-6A3F5B2D7E91}
AppName=Kevin
AppVersion=@SURUM@
AppPublisher=Liviciana
DefaultDirName={localappdata}\Programs\Kevin
DefaultGroupName=Kevin
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=Kevin-Kurulum
SetupIconFile=kevin.ico
UninstallDisplayIcon={app}\Kevin.exe
Compression=lzma2/normal
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "Kevin\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Kevin"; Filename: "{app}\Kevin.exe"
Name: "{userdesktop}\Kevin"; Filename: "{app}\Kevin.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Kevin.exe"; Description: "{cm:LaunchProgram,Kevin}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM godot.exe"; Flags: runhidden; RunOnceId: "KevinGovde"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM Kevin.exe"; Flags: runhidden; RunOnceId: "KevinBeyin"
ISS
  if (cd "$DIST/windows" && wine "$WINEPREFIX/drive_c/inno/ISCC.exe" /Q kevin.iss) >/dev/null 2>&1; then
    mv "$DIST/windows/Kevin-Kurulum.exe" "$DIST/Kevin-Kurulum.exe"
    echo "hazir: $DIST/Kevin-Kurulum.exe ($(du -h "$DIST/Kevin-Kurulum.exe" | cut -f1))"
  else
    echo "uyari: Kevin-Kurulum.exe derlenemedi"
  fi
}

case "$HEDEF" in
  linux) linux ;;
  windows) windows ;;
  hepsi) linux; windows ;;
  *) echo "kullanim: $0 [linux|windows|hepsi]"; exit 1 ;;
esac
