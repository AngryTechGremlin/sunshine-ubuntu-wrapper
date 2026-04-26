#!/bin/bash

# --- PARAMETERS ---
APP_ID=$1
PROCESS_NAME=$2
DELAY=$3
RUNNER=$4

# --- CONFIGURATION ---
KILL_SWITCH_SCRIPT="$HOME/kill_switch.py"
IDLE_SCRIPT="$HOME/idle_watchdog.py"
SCRIPT_PID=$$

# Set to true to enable logging, false to disable
ENABLE_LOGGING=true
if [ "$ENABLE_LOGGING" = true ]; then
    LOG_FILE="$HOME/heroic_launch.log"
    export PYTHONUNBUFFERED=1
else
    LOG_FILE="/dev/null"
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

if [ -z "$PROCESS_NAME" ]; then
    log "Error: PROCESS_NAME is required."
    exit 1
fi

# ==========================================
#    1. LAUNCH GAME
# ==========================================
log "Launching $PROCESS_NAME ($APP_ID) via $RUNNER..."

if [ "$RUNNER" = "steam" ]; then
    nohup steam "steam://rungameid/${APP_ID}" >/dev/null 2>&1 &
else
    xdg-open "heroic://launch?appName=${APP_ID}&runner=${RUNNER}"
fi

# ==========================================
#    2. MONITORING (Watchdog + Kill Switch)
# ==========================================
log "Waiting for game process..."

# Wait for game to start
GAME_PID=""
for i in {1..45}; do
    GAME_PID=$(pgrep -f -i "$PROCESS_NAME" | grep -v "$SCRIPT_PID" | head -n 1)
    if [ -n "$GAME_PID" ]; then
        log "Game detected running with PID: $GAME_PID"
        break
    fi
    sleep 1
done

if [ -z "$GAME_PID" ]; then
    log "Warning: Game process not detected after 45s. Still monitoring..."
fi

# Start Sidecars
python3 "$KILL_SWITCH_SCRIPT" >> "$LOG_FILE" 2>&1 &
KILL_SWITCH_PID=$!

python3 "$IDLE_SCRIPT" >> "$LOG_FILE" 2>&1 &
WATCHDOG_PID=$!

log "Monitoring for inactivity (10 mins) or Guide Button..."

# Main Loop
while true; do
    if ! pgrep -f -i "$PROCESS_NAME" | grep -v "$SCRIPT_PID" > /dev/null; then
        log "Game process $PROCESS_NAME no longer detected."
        break
    fi
    
    if ! kill -0 $KILL_SWITCH_PID 2>/dev/null; then
        log "🛑 Guide Button Pressed (Kill Switch activated)."
        pkill -f -i "$PROCESS_NAME"
        break
    fi

    if ! kill -0 $WATCHDOG_PID 2>/dev/null; then
        log "💤 Idle timeout reached. Stopping game."
        pkill -f -i "$PROCESS_NAME"
        break
    fi
    sleep 2
done

kill $KILL_SWITCH_PID 2>/dev/null
kill $WATCHDOG_PID 2>/dev/null

log "Game closed. Exiting session."
exit 0
