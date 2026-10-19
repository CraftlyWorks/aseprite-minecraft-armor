#!/bin/sh
# Runs every test in Aseprite's batch mode (no window needed).
#   tests/run.sh
# Set ASEPRITE to the Aseprite executable if it isn't in the default place.
# Set ONLINE=1 to also test downloading a skin from Mojang.
set -e
cd "$(dirname "$0")/.."

if [ -z "$ASEPRITE" ]; then
  case "$(uname -s)" in
    Darwin) ASEPRITE="/Applications/Aseprite.app/Contents/MacOS/aseprite" ;;
    *) ASEPRITE="aseprite" ;;
  esac
fi
A="$ASEPRITE"
SRC="$PWD/src"
FIX="$PWD/tests/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Tests that save files work on copies.
mkdir -p "$TMP/grids/humanoid" "$TMP/set/humanoid" "$TMP/set/humanoid_leggings"
cp "$FIX/humanoid/test_armor.png" "$TMP/grids/humanoid/"
cp "$FIX/humanoid/test_armor.png" "$TMP/set/humanoid/"
cp "$FIX/humanoid_leggings/test_armor.png" "$TMP/set/humanoid_leggings/"

echo "== no drawSprite"
# Image:drawSprite() moves a freshly stroked cel to 0,0 when called from a
# sprite 'change' event (Aseprite 1.3.17/1.3.18), see src/mca_render.lua.
if grep -n ":drawSprite(" src/*.lua | grep -v -- "--"; then echo "FAIL"; exit 1; else echo "PASS"; fi

echo "== layout";   "$A" -b --script-param src="$SRC" --script tests/test_layout.lua
echo "== compat";   "$A" -b --script-param src="$SRC" --script tests/test_compat.lua
echo "== png";      "$A" -b --script-param src="$SRC" --script-param dir="$FIX/png" \
  --script-param files="$FIX/humanoid/test_armor.png;$FIX/legacy/test_armor_layer_1.png;$FIX/skins/test_skin.png" --script tests/test_png.lua
echo "== skin";     "$A" -b --script-param src="$SRC" --script-param fixtures="$FIX" --script-param online="${ONLINE:-0}" --script tests/test_skin.lua
echo "== textures"; "$A" -b --script-param src="$SRC" \
  --script-param files="$FIX/humanoid/test_armor.png;$FIX/humanoid_leggings/test_armor.png;$FIX/legacy/test_armor_layer_1.png;$FIX/legacy/test_armor_layer_2.png" \
  --script-param palette="$FIX/legacy/test_armor_layer_1.png" --script tests/test_textures.lua
echo "== grids";    "$A" -b --script-param src="$SRC" --script-param file="$TMP/grids/humanoid/test_armor.png" --script tests/test_grids.lua
echo "== init";     "$A" -b --script-param src="$SRC" --script-param file="$TMP/set/humanoid/test_armor.png" --script tests/test_init.lua
echo "== render";   "$A" -b --script-param src="$SRC" --script-param l1="$FIX/humanoid/test_armor.png" \
  --script-param l2="$FIX/humanoid_leggings/test_armor.png" --script-param out="$TMP/render.png" --script tests/test_render.lua
