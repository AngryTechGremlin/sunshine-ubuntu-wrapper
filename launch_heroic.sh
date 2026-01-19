#!/bin/bash

# --- PARAMETERS ---
APP_ID=$1

# --- CONFIGURATION ---
DEBUG="false"  # Set to "true" to enable file logging and verbose output
LOG_DIR="/home/hambergerclan/logs"

if [ "$DEBUG" = "true" ]; then
    mkdir -p "$LOG_DIR"
    # Clean up logs older than 7 days
    find "$LOG_DIR" -type f -name "session_*.log" -mtime +7 -delete
    LOG_FILE="$LOG_DIR/session_$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    set -x
    LISTENER_LOG="$LOG_FILE"
else
    LISTENER_LOG="/dev/null"
fi

PROCESS_NAME=$2
DELAY=$3
RUNNER=$4

# --- SAFETY CHECKS ---
if [ -z "$APP_ID" ] || [ -z "$PROCESS_NAME" ] || [ -z "$DELAY" ] || [ -z "$RUNNER" ]; then
    echo "ERROR: Missing arguments."
    exit 1
fi

SCRIPT_PID=$$

# ==========================================
#      THE CONTROLLER LOCK (FIXED EXIT)
# ==========================================
# DEFAULT CODE: 0,1,0,1 (Update this to your code!)
SECRET_CODE="0,1,0,1" 
LOCK_TIMEOUT=30

# --- KIOSK MESSAGE ---
# Kill any existing Firefox instances to prevent conflicts (User Request)
pkill -f firefox
# Wait for Firefox to close (max 1s) instead of hard sleep
for i in {1..10}; do
    pgrep -f firefox | grep -v "^$SCRIPT_PID$" >/dev/null || break
    sleep 0.1
done

KIOSK_FILE="/home/hambergerclan/kiosk_lock.html"
echo "<html><body style='background-color:black;color:white;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;text-align:center;cursor:none;'><h1 style='font-size:4em;'>Please ask Mom and Dad<br>for permission</h1></body></html>" > "$KIOSK_FILE"

nohup firefox --kiosk --new-window "file://$KIOSK_FILE" >/dev/null 2>&1 &
KIOSK_PID=$!
trap "kill $KIOSK_PID 2>/dev/null; rm -f \"$KIOSK_FILE\"; exit" SIGINT SIGTERM

echo "🔒 SECURITY LOCK ACTIVE"

python3 -c "
import struct, sys, time, select, glob

code = [$SECRET_CODE]
entered = []
timeout = $LOCK_TIMEOUT

# Manage devices: Path -> File Handle
devices = {}

print('--- WATCHING FOR CONTROLLERS ---')
sys.stdout.flush()

start_time = time.time()
last_scan = 0

while True:
    current_time = time.time()
    
    # 1. TIMEOUT CHECK
    if current_time - start_time > timeout:
        print('TIMEOUT REACHED.')
        sys.exit(1)

    # 2. SCAN FOR NEW DEVICES (Every 0.5s)
    if current_time - last_scan > 0.5:
        try:
            found_paths = glob.glob('/dev/input/js*')
            
            # Add New
            for path in found_paths:
                if path not in devices:
                    try:
                        devices[path] = open(path, 'rb')
                        print(f'Connected: {path}')
                        sys.stdout.flush()
                    except Exception:
                        pass
            
            # Remove Lost
            for path in list(devices.keys()):
                if path not in found_paths:
                    try:
                        devices[path].close()
                    except Exception:
                        pass
                    del devices[path]
            last_scan = current_time
        except Exception:
            pass

    # 3. READ INPUTS
    if devices:
        inputs = list(devices.values())
        readable, _, _ = select.select(inputs, [], [], 0.1)

        for f in readable:
            try:
                data = f.read(8)
                if not data: continue 
                
                _, value, type, number = struct.unpack('IhBB', data)
                
                # Type 1 = Button, Value 1 = Pressed
                if type == 1 and value == 1:
                    print(f'BUTTON: {number}')
                    sys.stdout.flush()
                    
                    if number == code[len(entered)]:
                        entered.append(number)
                        if entered == code:
                            print('ACCESS GRANTED.')
                            sys.exit(0)
                    else:
                        entered = []
                        if number == code[0]:
                            entered.append(number)
            except Exception:
                pass
    else:
        time.sleep(0.1)
"
LOCK_RESULT=$?

kill $KIOSK_PID 2>/dev/null
rm -f "$KIOSK_FILE"

if [ $LOCK_RESULT -ne 0 ]; then
    echo "❌ ACCESS DENIED."
    exit 1
fi

# ==========================================
#        END LOCK - LAUNCH GAME
# ==========================================

# (Trap will be installed after the watchdog is started)

if [ "$RUNNER" = "steam" ]; then
    nohup steam "steam://rungameid/${APP_ID}" >/dev/null 2>&1 &
else
    xdg-open "heroic://launch?appName=${APP_ID}&runner=${RUNNER}"
fi

# ==========================================
#      XBOX BUTTON LISTENER (BACKGROUND)
# ==========================================
# Listens for Button 8 (Guide) to kill the game immediately
python3 -c "
import struct, sys, time, select, glob, os, signal

proc_name = '$PROCESS_NAME'
script_pid = '$SCRIPT_PID'

devices = {}
last_scan = 0
while True:
    try:
        current_time = time.time()
        # Scan for devices every 2 seconds
        if current_time - last_scan > 2.0:
            last_scan = current_time
            found = glob.glob('/dev/input/js*')
            for p in found:
                if p not in devices:
                    try: devices[p] = open(p, 'rb')
                    except: pass
            for p in list(devices.keys()):
                if p not in found:
                    try: devices[p].close()
                    except: pass
                    del devices[p]

        # Read inputs
        if devices:
            r, _, _ = select.select(list(devices.values()), [], [], 0.1)
            for f in r:
                try:
                    data = f.read(8)
                    if not data: continue
                    _, val, type, num = struct.unpack('IhBB', data)
                    # Button (1) Pressed (1) and is Guide (8)
                    if type == 1 and val == 1 and num == 8:
                        # Safe Kill: Kill game, ignore main script
                        os.kill(int(script_pid), signal.SIGTERM)
                        sys.exit(0)
                except: pass
        else:
            time.sleep(1)
    except:
        time.sleep(1)
" >> "$LISTENER_LOG" 2>&1 &
LISTENER_PID=$!

# ------------------------------------------
# Start a watchdog to enforce a 1-hour play limit
# ------------------------------------------
PLAYTIME_LIMIT=3600
START_TIME=$(date +%s)

# Define cleanup to prevent double-execution (Trap fires on signal AND exit)
cleanup() {
    trap - SIGTERM SIGINT EXIT
    echo "Stopping game..."
    kill $LISTENER_PID 2>/dev/null
    pgrep -f -i "$PROCESS_NAME" | grep -v "^$SCRIPT_PID$" | xargs -r kill
    exit
}
trap cleanup SIGTERM SIGINT EXIT

echo "Waiting for game to start (max $DELAY seconds)..."
for ((i=0; i<DELAY; i++)); do
    if pgrep -f -i "$PROCESS_NAME" | grep -v "^$SCRIPT_PID$" | grep -v "^$LISTENER_PID$" > /dev/null; then
        echo "✅ Game started early! Switching to watchdog."
        break
    fi
    sleep 1
done

while pgrep -f -i "$PROCESS_NAME" | grep -v "^$SCRIPT_PID$" | grep -v "^$LISTENER_PID$" > /dev/null; do
    # DEBUG: Print what processes are keeping the session alive
    pgrep -f -a -i "$PROCESS_NAME" | grep -v "^$SCRIPT_PID$" | grep -v "^$LISTENER_PID$"
    # Check for timeout
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - START_TIME)) -ge $PLAYTIME_LIMIT ]; then
        echo "⏰ Playtime exceeded. Stopping game..."
        pgrep -f -i "$PROCESS_NAME" | grep -v "^$SCRIPT_PID$" | xargs -r kill
        break
    fi
    sleep 0.5
done