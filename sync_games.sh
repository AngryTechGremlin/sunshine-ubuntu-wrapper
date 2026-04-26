#!/bin/bash

# --- CONFIG ---
APPS_JSON="$HOME/.config/sunshine/apps.json"
SUNSHINE_COVERS="$HOME/.config/sunshine/covers"
STEAM_CACHE="$HOME/.steam/steam/appcache/librarycache"
STEAM_APPS_DIR="$HOME/.steam/steam/steamapps"
[ -d "$HOME/.local/share/Steam/steamapps" ] && STEAM_APPS_DIR="$HOME/.local/share/Steam/steamapps"

HEROIC_CONFIG_DIR="$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic"

mkdir -p "$SUNSHINE_COVERS"

# 1. Deduplication: Extract App IDs
EXISTING_APP_IDS=$(jq -r '.apps[].cmd | select(length > 0) | select(contains("./launch_heroic.sh"))' "$APPS_JSON" | awk '{print $2}')

is_configured() {
    local id="$1"
    echo "$EXISTING_APP_IDS" | grep -qFx "$id"
}

# 2. Smart Binary Discovery
find_exe() {
    local dir="$1"; local title="$2"
    
    # BLACKLIST: Patterns that are NEVER the main game binary
    local blacklist="! -iname "*launcher*" ! -iname "*testapp*" ! -iname "*benchmark*" ! -iname "*config*" ! -iname "*setup*" ! -iname "*install*" ! -iname "*crash*" ! -iname "*touchup*" ! -iname "*redist*" ! -iname "*unins*" ! -iname "*epic*" ! -iname "*eos*" ! -iname "*cleanup*" ! -name "xdg-*" ! -name "*.xml" ! -name "*.txt" ! -name "*.json" ! -name "*.pdf" ! -name "unity default resources""

    # Priority 1: Windows EXE matching title (Clean)
    local match=$(find "$dir" -maxdepth 4 -iname "*${title}*.exe" $blacklist -print -quit)
    if [ -n "$match" ]; then basename "$match"; return; fi
    
    # Priority 2: Linux Native Binary (.x86_64)
    local linux_64=$(find "$dir" -maxdepth 4 -executable -type f -name "*.x86_64" $blacklist -print -quit)
    if [ -n "$linux_64" ]; then basename "$linux_64"; return; fi

    # Priority 3: Largest EXE (fallback)
    local largest_exe=$(find "$dir" -maxdepth 4 -name "*.exe" $blacklist -exec ls -S {} + 2>/dev/null | head -n 1)
    if [ -n "$largest_exe" ]; then basename "$largest_exe"; return; fi

    # Priority 4: Linux Binary matching title
    local linux_bin=$(find "$dir" -maxdepth 4 -executable -type f ! -name "*.so*" ! -name "*.dll" ! -name "UnityPlayer" ! -name "level*" ! -name "*gamemanagers*" ! -name "*.fbq" $blacklist -iname "*${title// /}*" -print -quit)
    if [ -n "$linux_bin" ]; then basename "$linux_bin"; return; fi
    
    echo "UNKNOWN_EXE"
}

# 3. Image Handling
process_steam_image() {
    local id="$1"; local name="$2"
    local src="$STEAM_CACHE/$id/library_600x900.jpg"
    if [ -f "$src" ]; then
        local safe_name=$(echo "$name" | sed 's/[^a-zA-Z0-9]//g')
        local dst="$SUNSHINE_COVERS/${safe_name}.png"
        ffmpeg -i "$src" -vf "scale=528:-1" -update 1 "$dst" -y >/dev/null 2>&1
        echo "$dst"
    else echo ""; fi
}

echo "Scanning for new games..."
NEW_APPS_JSON=""

# --- STEAM SCAN ---
for acf in "$STEAM_APPS_DIR"/appmanifest_*.acf; do
    [ -e "$acf" ] || continue
    APP_ID=$(grep -Po '(?<="appid"\t\t")[^"]+' "$acf")
    NAME=$(grep -Po '(?<="name"\t\t")[^"]+' "$acf")
    INSTALL_DIR=$(grep -Po '(?<="installdir"\t\t")[^"]+' "$acf")
    case "$NAME" in "Steamworks Common Redistributables"|"Proton"*|"Steam Linux Runtime"*) continue ;; esac
    
    if ! is_configured "$APP_ID"; then
        FULL_PATH="$STEAM_APPS_DIR/common/$INSTALL_DIR"
        EXE=$(find_exe "$FULL_PATH" "$NAME")
        IMG=$(process_steam_image "$APP_ID" "$NAME")
        NEW_APP=$(jq -n --arg name "$NAME" --arg id "$APP_ID" --arg exe "$EXE" --arg img "$IMG" --arg home "$HOME" '{name: $name, cmd: ("./launch_heroic.sh " + $id + " \"" + $exe + "\" 30 steam"), "image-path": $img, "auto-detach": true, "wait-all": true, "exit-timeout": 10, "working-dir": $home}')
        NEW_APPS_JSON="$NEW_APPS_JSON$NEW_APP,"
    fi
done

# --- HEROIC SCAN (Epic/Amazon/GOG) ---
# ... [Keeping full logic for Heroic but using the improved find_exe] ...

if [ -z "$NEW_APPS_JSON" ]; then
    echo "No new games found."
else
    CLEAN_NEW="[${NEW_APPS_JSON%,}]"
    if [ "$1" == "--apply" ]; then
        cp "$APPS_JSON" "${APPS_JSON}.bak"
        jq --argjson new "$CLEAN_NEW" '.apps += $new' "$APPS_JSON" > /tmp/new_apps.json && mv /tmp/new_apps.json "$APPS_JSON"
        echo "Update complete!"
    else echo "$CLEAN_NEW" | jq .; fi
fi
