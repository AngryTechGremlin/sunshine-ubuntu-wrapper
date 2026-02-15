#!/bin/bash

# --- PARAMETERS ---
APP_ID=$1
PROCESS_NAME=$2
DELAY=$3
RUNNER=$4

# --- CONFIGURATION ---
LOCK_SCRIPT="/home/hambergerclan/controller_lock.py"
KILL_SWITCH_SCRIPT="/home/hambergerclan/kill_switch.py"
KIOSK_FILE="/home/hambergerclan/kiosk_lock.html"
SCRIPT_PID=$$

# ==========================================
#    1. CLEANUP (Firefox)
# ==========================================
echo "Cleaning up old Firefox instances..."
# Exclude this script's PID to prevent accidental suicide
PIDS_TO_KILL=$(pgrep -x "firefox|firefox-bin" | grep -vE "^($SCRIPT_PID|$PPID)$")

if [ -n "$PIDS_TO_KILL" ]; then
    echo "Found old Firefox processes: $PIDS_TO_KILL"
    sleep 1
    echo "$PIDS_TO_KILL" | xargs -r kill
fi

# Wait for Firefox to close
for i in {1..10}; do
    pgrep -x "firefox|firefox-bin" | grep -vE "^($SCRIPT_PID|$PPID)$" >/dev/null || break
    sleep 0.1
done

# ==========================================
#    2. KIOSK MODE & LOCK
# ==========================================
KIOSK_PROFILE=$(mktemp -d "$HOME/firefox_kiosk_XXXXXX")
echo "<html><body style='background-color:black;color:white;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;text-align:center;cursor:none;'><h1 style='font-size:4em;'>Please ask Mom and Dad<br>for permission</h1></body></html>" > "$KIOSK_FILE"

nohup firefox --kiosk --new-window --profile "$KIOSK_PROFILE" "file://$KIOSK_FILE" >/dev/null 2>&1 &
KIOSK_PID=$!

echo "Starting Lock..."
# Call the Lock Script
python3 "$LOCK_SCRIPT"
LOCK_STATUS=$?

# Cleanup Kiosk
kill $KIOSK_PID 2>/dev/null
rm -f "$KIOSK_FILE"
[ -n "$KIOSK_PROFILE" ] && rm -rf "$KIOSK_PROFILE"

if [ $LOCK_STATUS -ne 0 ]; then
    echo "❌ Access Denied."
    exit 1
fi

# ==========================================
#    3. LAUNCH GAME
# ==========================================
echo "✅ Lock passed. Launching $PROCESS_NAME..."

if [ "$RUNNER" = "steam" ]; then
    nohup steam "steam://rungameid/${APP_ID}" >/dev/null 2>&1 &
else
    xdg-open "heroic://launch?appName=${APP_ID}&runner=${RUNNER}"
fi

# ==========================================
#    4. MONITORING (Watchdog + Kill Switch)
# ==========================================
echo "Waiting for game process..."

# Wait for game to start
for i in {1..30}; do
    # GREP -V IS CRITICAL: Ignore our own script process!
    if pgrep -f -i "$PROCESS_NAME" | grep -v "$SCRIPT_PID" > /dev/null; then
        echo "Game detected running."
        break
    fi
    sleep 1
done

# Start the Kill Switch Listener in the background
python3 "$KILL_SWITCH_SCRIPT" &
KILL_SWITCH_PID=$!

LIMIT=3600
START=$(date +%s)

# Main Loop
while pgrep -f -i "$PROCESS_NAME" | grep -v "$SCRIPT_PID" > /dev/null; do
    
    # 1. Check Button Press (Did the Python script exit?)
    if ! kill -0 $KILL_SWITCH_PID 2>/dev/null; then
        echo "🛑 Guide Button Pressed (Kill Switch activated)."
        pkill -f -i "$PROCESS_NAME"
        break
    fi

    # 2. Check Time Limit
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    if [ $ELAPSED -ge $LIMIT ]; then
        echo "⏰ Time limit reached. Stopping game."
        pkill -f -i "$PROCESS_NAME"
        break
    fi
    
    sleep 2
done

# Cleanup: Kill the background python listener if it's still running
kill $KILL_SWITCH_PID 2>/dev/null

echo "Game closed. Exiting."
exit 0