#!/bin/bash

# --- PARAMETERS ---
APP_ID=$1
PROCESS_NAME=$2
DELAY=$3
RUNNER=$4

# --- CONFIGURATION ---
KILL_SWITCH_SCRIPT="/home/hambergerclan/kill_switch.py"
IDLE_SCRIPT="/home/hambergerclan/idle_watchdog.py"
SCRIPT_PID=$$

# Set to true to enable logging, false to disable
ENABLE_LOGGING=true
if [ "$ENABLE_LOGGING" = true ]; then
    LOG_FILE="/home/hambergerclan/heroic_launch.log"
    export PYTHONUNBUFFERED=1
else
    LOG_FILE="/dev/null"
fi

if [ -z "$PROCESS_NAME" ]; then
    echo "Error: PROCESS_NAME is required." | tee -a "$LOG_FILE"
    exit 1
fi

# ==========================================
#    1. LAUNCH GAME
# ==========================================
echo "Launching $PROCESS_NAME..."

if [ "$RUNNER" = "steam" ]; then
    nohup steam "steam://rungameid/${APP_ID}" >/dev/null 2>&1 &
else
    xdg-open "heroic://launch?appName=${APP_ID}&runner=${RUNNER}"
fi

# ==========================================
#    2. MONITORING (Watchdog + Kill Switch)
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
echo "Starting Kill Switch..." | tee -a "$LOG_FILE"
python3 "$KILL_SWITCH_SCRIPT" >> "$LOG_FILE" 2>&1 &
KILL_SWITCH_PID=$!
sleep 1
# Start the Idle Watchdog
# This script should exit if no input is detected for 5 minutes
echo "Starting Idle Watchdog..." | tee -a "$LOG_FILE"
python3 "$IDLE_SCRIPT" >> "$LOG_FILE" 2>&1 &
WATCHDOG_PID=$!

echo "Monitoring for inactivity (5 mins) or Guide Button..."

# Main Loop
while pgrep -f -i "$PROCESS_NAME" | grep -v "$SCRIPT_PID" > /dev/null; do
    
    # 1. Check Guide Button (Did the Python script exit?)
    if ! kill -0 $KILL_SWITCH_PID 2>/dev/null; then
        echo "🛑 Guide Button Pressed (Kill Switch activated)."
        pkill -f -i "$PROCESS_NAME"
        break
    fi

    # 2. Check Idle Watchdog (Did the Python script exit?)
    if ! kill -0 $WATCHDOG_PID 2>/dev/null; then
        echo "💤 Idle timeout reached. Stopping game."
        pkill -f -i "$PROCESS_NAME"
        break
    fi
    
    sleep 2
done

# Cleanup: Kill the background python listener if it's still running
kill $KILL_SWITCH_PID 2>/dev/null
kill $WATCHDOG_PID 2>/dev/null

echo "Game closed. Exiting."
exit 0
