#!/usr/bin/env bash
# Kevin'in govdesini baslatir. Hyprland'deysek pencere kurallarini (yuzen,
# blur/golge/kenarlik yok, her masaustunde) kullanicinin config'ine dokunmadan
# gecici olarak yukler.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null; then
  RULES="${XDG_RUNTIME_DIR:-/tmp}/kevin-body-rules.conf"
  cat > "$RULES" <<'EOF'
windowrule = float 1, match:class ^(Kevin)$
windowrule = pin 1, match:class ^(Kevin)$
windowrule = no_blur 1, match:class ^(Kevin)$
windowrule = no_shadow 1, match:class ^(Kevin)$
windowrule = no_anim 1, match:class ^(Kevin)$
windowrule = no_dim 1, match:class ^(Kevin)$
windowrule = no_initial_focus 1, match:class ^(Kevin)$
EOF
  hyprctl keyword source "$RULES" >/dev/null
fi

exec "$GODOT" --path "$HERE" "$@"
