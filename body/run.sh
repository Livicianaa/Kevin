#!/usr/bin/env bash
# Kevin'in govdesini baslatir. Hyprland'deysek pencere kurallarini (yuzen,
# blur/golge/kenarlik yok, her masaustunde) kullanicinin config'ine dokunmadan
# gecici olarak yukler.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Zaten aciksa ikinci bir Kevin (ve ikinci beyin) acma
FILES=()
GODOT_ARGS=()
for a in "$@"; do
  case "$a" in file://*) a="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1][7:]))' "$a")" ;; esac
  if [ -e "$a" ]; then FILES+=("$(readlink -f "$a")"); else GODOT_ARGS+=("$a"); fi
done
set -- ${GODOT_ARGS[@]+"${GODOT_ARGS[@]}"}

send_files() {
  python3 - "$@" <<'PY'
import json, os, socket, sys, time
deadline = time.time() + float(sys.argv[1])
msg = (json.dumps({"type": "drop", "files": sys.argv[2:]}) + "\n").encode()
while time.time() < deadline:
    try:
        s = socket.create_connection(("127.0.0.1", 47630), timeout=2)
        time.sleep(float(os.environ.get("KEVIN_SEND_DELAY", "0.3")))
        s.sendall(msg)
        time.sleep(0.3)
        s.close()
        sys.exit(0)
    except OSError:
        time.sleep(1)
sys.exit(1)
PY
}

if pgrep -f -- "--path $HERE( |$)" >/dev/null 2>&1; then
  if [ ${#FILES[@]} -gt 0 ]; then
    send_files 5 "${FILES[@]}"
    exit $?
  fi
  echo "Kevin zaten calisiyor."
  exit 0
fi
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null; then
  RULES="${XDG_RUNTIME_DIR:-/tmp}/kevin-body-rules.conf"
  # Pencere ilk acildigi monitorun olcegini omur boyu tasiyor (XWayland,
  # force_zero_scaling). 1.5 olcekli laptop ekraninda acilinca butun X
  # koordinatlari 1.5'e bolunuyordu: pencere kuculuyor, Kevin ekranin
  # ortasinda havada duruyordu, fare ile pencere birbirini tutmuyordu.
  # En dusuk olcekli monitorde acilinca koordinatlar tutarli.
  # Esitlikte en soldaki secilir (olcekler 1'e esitlenince laptop secilip 1920 px kaymasin).
  # Cerceve/yuvarlama kapali: koyu duvar kagidinda Kevin'in etrafinda cizgi parlamasin.
  KEVIN_MONITOR="$(hyprctl monitors -j | python3 -c 'import json,sys; m=min(json.load(sys.stdin), key=lambda m: (m["scale"], m["x"])); print(m["name"])')"
  cat > "$RULES" <<'EOF'
windowrule = float 1, match:class ^(Kevin)$
windowrule = pin 1, match:class ^(Kevin)$
windowrule = no_blur 1, match:class ^(Kevin)$
windowrule = no_shadow 1, match:class ^(Kevin)$
windowrule = no_anim 1, match:class ^(Kevin)$
windowrule = no_dim 1, match:class ^(Kevin)$
windowrule = no_initial_focus 1, match:class ^(Kevin)$
windowrule = border_size 0, match:class ^(Kevin)$
windowrule = rounding 0, match:class ^(Kevin)$
windowrule = decorate 0, match:class ^(Kevin)$
windowrule = float 1, match:title ^(Kevin - .+)$
windowrule = center 1, match:title ^(Kevin - .+)$
EOF
  echo "windowrule = monitor $KEVIN_MONITOR, match:class ^(Kevin)$" >> "$RULES"
  hyprctl keyword source "$RULES" >/dev/null
fi

if [ ${#FILES[@]} -gt 0 ]; then
  "$GODOT" --path "$HERE" "$@" &
  GPID=$!
  sleep 4
  KEVIN_SEND_DELAY=10 send_files 90 "${FILES[@]}" || true
  wait "$GPID"
  exit $?
fi
exec "$GODOT" --path "$HERE" "$@"
