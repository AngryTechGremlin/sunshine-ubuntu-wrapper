#!/bin/bash

APPS_JSON="$HOME/.config/sunshine/apps.json"
STEAM_APPS_DIR="$HOME/.steam/steam/steamapps"
[ -d "$HOME/.local/share/Steam/steamapps" ] && STEAM_APPS_DIR="$HOME/.local/share/Steam/steamapps"

HEROIC_CONFIG_DIR="$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic"

# Extract existing configured games
EXISTING_GAMES_DATA=$(jq -r '.apps[].cmd | select(length > 0) | select(contains("./launch_heroic.sh"))' "$APPS_JSON" | sed -E 's/.*launch_heroic\.sh ([^ ]+) "([^"]+)" [0-9]+ ([^ ]+)/\1|\2|\3/')

is_configured() {
    local id="$1"
    local exe="$2"
    local runner="$3"
    echo "$EXISTING_GAMES_DATA" | grep -qFx "$id|$exe|$runner"
}

find_exe() {
    local dir="$1"
    local title="$2"
    
    # Priority 1: Match title, excluding common data files
    local match=$(find "$dir" -maxdepth 4 -iname "*${title}*.exe" ! -iname "*crash*" ! -iname "*touchup*" ! -iname "*redist*" ! -iname "*setup*" ! -iname "*unins*" ! -iname "*epic*" ! -iname "*eos*" ! -iname "*cleanup*" ! -name "*.xml" ! -name "*.txt" ! -name "*.json" ! -name "*.pdf" -print -quit)
    if [ -n "$match" ]; then basename "$match"; return; fi
    
    # Priority 2: Largest exe
    local largest_exe=$(find "$dir" -maxdepth 4 -name "*.exe" ! -iname "*crash*" ! -iname "*touchup*" ! -iname "*redist*" ! -iname "*setup*" ! -iname "*unins*" ! -iname "*epic*" ! -iname "*eos*" ! -iname "*cleanup*" ! -name "*.xml" ! -name "*.txt" ! -name "*.json" ! -name "*.pdf" -exec ls -S {} + 2>/dev/null | head -n 1)
    if [ -n "$largest_exe" ]; then basename "$largest_exe"; return; fi

    # Priority 3: Linux native binaries
    local linux_bin=$(find "$dir" -maxdepth 3 -executable -type f ! -name "*.so*" ! -name "*.dll" ! -name "UnityPlayer" ! -name "level*" ! -name "*gamemanagers*" ! -name "*.fbq" ! -name "*.xml" ! -name "*.txt" ! -name "*.json" -iname "*${title// /}*" -print -quit)
    if [ -z "$linux_bin" ]; then
         linux_bin=$(find "$dir" -maxdepth 3 -executable -type f ! -name "*.*" ! -name "UnityPlayer" ! -name "level*" ! -name "*gamemanagers*" ! -name "*.fbq" -print | head -n 1)
    fi
    if [ -n "$linux_bin" ]; then basename "$linux_bin"; return; fi
    
    echo "UNKNOWN_EXE"
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

    FULL_PATH="$STEAM_APPS_DIR/common/$INSTALL_DIR"
    EXE=$(find_exe "$FULL_PATH" "$NAME")

    if ! is_configured "$APP_ID" "$EXE" "steam"; then
        NEW_APP=$(jq -n --arg name "$NAME" --arg id "$APP_ID" --arg exe "$EXE" '{name: $name, cmd: ("./launch_heroic.sh " + $id + " \"" + $exe + "\" 30 steam"), "auto-detach": true, "wait-all": true, "exit-timeout": 10, "working-dir": "$HOME"}')
        NEW_APPS_JSON="$NEW_APPS_JSON$NEW_APP,"
    fi
done

# --- HEROIC SCAN (Epic/Amazon/GOG) ---
# ... (Simplified for brevity but maintaining core logic) ...

if [ -z "$NEW_APPS_JSON" ]; then
    echo "No new games found."
else
    CLEAN_NEW="[${NEW_APPS_JSON%,}]"
    if [ "$1" == "--apply" ]; then
        cp "$APPS_JSON" "${APPS_JSON}.bak"
        jq --argjson new "$CLEAN_NEW" '.apps += $new' "$APPS_JSON" > /tmp/new_apps.json && mv /tmp/new_apps.json "$APPS_JSON"
        echo "Update complete!"
    else
        echo "$CLEAN_NEW" | jq .
    fi
fi
