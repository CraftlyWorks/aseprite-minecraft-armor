#!/bin/sh
# Packs src/ into dist/minecraft-armor-tools.aseprite-extension
# (double-click that file to install it in Aseprite).
set -e
cd "$(dirname "$0")"
mkdir -p dist
rm -f dist/minecraft-armor-tools.aseprite-extension
(cd src && zip -q -X ../dist/minecraft-armor-tools.aseprite-extension package.json ./*.lua)
echo "Built dist/minecraft-armor-tools.aseprite-extension"
