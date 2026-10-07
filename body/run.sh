#!/usr/bin/env bash
# Kevin'in govdesini baslatir. Hyprland'deysek pencere kurallarini (yuzen,
# blur/golge/kenarlik yok, her masaustunde) kullanicinin config'ine dokunmadan
# gecici olarak yukler.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Zaten aciksa ikinci bir Kevin (ve ikinci beyin) acma
if pgrep -f -- "--path $HERE( |$)" >/dev/null 2>&1; then
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
  # Kevin'in kod yazdigi pencere ("Kevin - dosya.py") de yuzer: doseli acilip
  # Super+surukle ile birakilinca Hyprland 0.56.2 dwindle assert'iyle
  # cokuyordu (30 Eyl, 2 Eki).
  KEVIN_MONITOR="$(hyprctl monitors -j | python3 -c 'import json,sys; m=min(json.load(sys.stdin), key=lambda m: m["scale"]); print(m["name"])')"
  cat > "$RULES" <<'EOF'
windowrule = float 1, match:class ^(Kevin)$
windowrule = pin 1, match:class ^(Kevin)$
windowrule = no_blur 1, match:class ^(Kevin)$
windowrule = no_shadow 1, match:class ^(Kevin)$
windowrule = no_anim 1, match:class ^(Kevin)$
windowrule = no_dim 1, match:class ^(Kevin)$
windowrule = no_initial_focus 1, match:class ^(Kevin)$
windowrule = float 1, match:title ^(Kevin - .+)$
windowrule = center 1, match:title ^(Kevin - .+)$
EOF
  echo "windowrule = monitor $KEVIN_MONITOR, match:class ^(Kevin)$" >> "$RULES"
  hyprctl keyword source "$RULES" >/dev/null
fi

exec "$GODOT" --path "$HERE" "$@"
