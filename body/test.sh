#!/usr/bin/env bash
# Kevin'in govdesini TEST icin acar: pencere kullanicinin ekranina hic dusmez.
#
# Neden: test pencereleri kuralsiz acilinca Hyprland onlari ekrana doseyip
# buyuk aciyordu; ustune pencere kendi konumunu her karede degistirince,
# kullanici onu SUPER+surukle ile kenara cekerken Hyprland 0.56.2 coktu
# (dwindle assert, 30 Eylul 2026).
#
# Cozum: ayni projeyi "KevinTest" adiyla (farkli pencere sinifi) acip Hyprland'e
# o sinifi gizli bir calisma alanina, yuzen olarak gondermesini soyluyoruz.
# Render ve --shot calismaya devam ediyor.
#
# Kullanim: body/test.sh --emote=dab --shot=/tmp/x --shots=1,2
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
TEST_DIR="$HERE/../.body-test"

mkdir -p "$TEST_DIR"
for f in "$HERE"/* "$HERE"/.godot; do
  name="$(basename "$f")"
  [ "$name" = "project.godot" ] && continue
  [ -e "$TEST_DIR/$name" ] || ln -s "$f" "$TEST_DIR/$name"
done
sed 's/^config\/name=.*/config\/name="KevinTest"/' "$HERE/project.godot" > "$TEST_DIR/project.godot"

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null; then
  RULES="${XDG_RUNTIME_DIR:-/tmp}/kevin-test-rules.conf"
  cat > "$RULES" <<'EOF'
windowrule = workspace special:kevintest silent, match:class ^(KevinTest)$
windowrule = float 1, match:class ^(KevinTest)$
windowrule = no_initial_focus 1, match:class ^(KevinTest)$
windowrule = no_anim 1, match:class ^(KevinTest)$
EOF
  hyprctl keyword source "$RULES" >/dev/null
fi

exec "$GODOT" --path "$TEST_DIR" --disable-vsync -- --offscreen "$@"
