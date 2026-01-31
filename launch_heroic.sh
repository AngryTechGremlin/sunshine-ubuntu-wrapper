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

    # --- DEBUG: LOG ENVIRONMENT ---
    echo "--- ENVIRONMENT CHECK ---"
    env | grep -E "DISPLAY|XAUTHORITY|USER|HOME|XDG_"
    echo "--- PROCESS INFO ---"
    echo "My PID: $$"
    echo "My Parent PID: $PPID"
    echo "Command Line: $0 $@"
    echo "-------------------------"
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
# DEFAULT CODE: 0,1,0,1 (Up, Down, Up, Down)
SECRET_CODE="0,1,0,1" 
LOCK_TIMEOUT=30

# --- PRE-FLIGHT CHECK ---
# If the display system isn't ready, abort immediately to prevent zombie processes.
echo "Checking Display Readiness (DISPLAY=$DISPLAY)..."
if ! xset q >> "$LISTENER_LOG" 2>&1; then
    echo "❌ FATAL: Display not ready (xset failed). Aborting session."
    exit 1
fi

# --- KIOSK MESSAGE ---
# Kill any existing Firefox instances to prevent conflicts (User Request)
# Log what we find before killing to debug "suicide" issues
echo "Cleaning up old Firefox instances..."

# Use SAFE search (Process Name only, no -f) to avoid killing Sunshine/Script/Parent
PIDS_TO_KILL=$(pgrep -x "firefox|firefox-bin" | grep -vE "^($SCRIPT_PID|$PPID)$")

if [ -n "$PIDS_TO_KILL" ]; then
    echo "Found old Firefox processes: $PIDS_TO_KILL"
    # Sleep briefly to ensure logs flush before killing potentially dangerous processes
    sleep 1
    echo "$PIDS_TO_KILL" | xargs -r kill
else
    echo "No old Firefox processes found."
fi

# Wait for Firefox to close (max 1s) instead of hard sleep
for i in {1..10}; do
    pgrep -x "firefox|firefox-bin" | grep -v "^$SCRIPT_PID$" >/dev/null || break
    pgrep -x "firefox|firefox-bin" | grep -vE "^($SCRIPT_PID|$PPID)$" >/dev/null || break
    sleep 0.1
done

KIOSK_FILE="/home/hambergerclan/kiosk_lock.html"
# Create a temporary profile to bypass Keyring/Profile locks on reboot
# Use a directory in HOME because Snap Firefox often cannot read /tmp
KIOSK_PROFILE=$(mktemp -d "$HOME/firefox_kiosk_XXXXXX")
echo "Created Profile: $KIOSK_PROFILE"
ls -ld "$KIOSK_PROFILE"

echo "<html><body style='background-color:black;color:white;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;text-align:center;cursor:none;'><h1 style='font-size:4em;'>Please ask Mom and Dad<br>for permission</h1></body></html>" > "$KIOSK_FILE"

nohup firefox --kiosk --new-window --profile "$KIOSK_PROFILE" "file://$KIOSK_FILE" >> "$LISTENER_LOG" 2>&1 &
KIOSK_PID=$!
trap "kill $KIOSK_PID 2>/dev/null; rm -f \"$KIOSK_FILE\"; exit" SIGINT SIGTERM
echo "Launched Kiosk (PID: $KIOSK_PID)"

# Verify launch status
sleep 1
if ! kill -0 $KIOSK_PID 2>/dev/null; then
    wait $KIOSK_PID 2>/dev/null
    EXIT_CODE=$?
    echo "❌ FATAL: Firefox crashed immediately (Exit Code: $EXIT_CODE). Aborting."
    ls -A "$KIOSK_PROFILE"  # Log profile contents to see if it initialized
    rm -f "$KIOSK_FILE"
    [ -n "$KIOSK_PROFILE" ] && rm -rf "$KIOSK_PROFILE"
    exit 1
fi

trap "kill $KIOSK_PID 2>/dev/null; rm -f \"$KIOSK_FILE\"; [ -n \"$KIOSK_PROFILE\" ] && rm -rf \"$KIOSK_PROFILE\"; exit" SIGINT SIGTERM

echo "🔒 SECURITY LOCK ACTIVE"

python3 -c "
import struct, sys, time, select, glob, os

code = [$SECRET_CODE]
entered = []
timeout = $LOCK_TIMEOUT

# Manage devices: File Handle -> Info Dict
inputs = {}

print(f'DEBUG: Code required: {code}')
print('--- WATCHING FOR CONTROLLERS & KEYBOARDS ---')
sys.stdout.flush()

start_time = time.time()
last_scan = 0

# Detect architecture for event structure (64-bit vs 32-bit)
is_64bits = sys.maxsize > 2**32
ev_fmt = 'llHHi' if is_64bits else 'IIHHi'
ev_size = struct.calcsize(ev_fmt)

while True:
    current_time = time.time()
    
    # 1. TIMEOUT CHECK
    if current_time - start_time > timeout:
        print('TIMEOUT REACHED.')
        sys.exit(1)

    # 2. SCAN FOR NEW DEVICES (Every 0.5s)
    if current_time - last_scan > 0.5:
        try:
            js_paths = glob.glob('/dev/input/js*')
            
            # Improved Keyboard Discovery
            kbd_paths = glob.glob('/dev/input/by-id/*-kbd*')
            try:
                with open('/proc/bus/input/devices', 'r') as f:
                    for line in f:
                        if line.startswith('H:') and 'kbd' in line:
                            for part in line.split():
                                if part.startswith('event'):
                                    kbd_paths.append('/dev/input/' + part)
            except: pass
            
            # Helper to add device safely
            def add_dev(path, dtype):
                real = os.path.realpath(path)
                for info in inputs.values():
                    if info['real_path'] == real: return
                try:
                    f = open(path, 'rb')
                    inputs[f] = {'type': dtype, 'path': path, 'real_path': real}
                    print(f'Connected {dtype}: {path}')
                    sys.stdout.flush()
                except Exception as e:
                    print(f'Failed to connect {path}: {e}')
                    sys.stdout.flush()

            for p in js_paths: add_dev(p, 'js')
            for p in kbd_paths: add_dev(p, 'kbd')
            
            # Remove Lost
            found_paths = set(js_paths + kbd_paths)
            for f in list(inputs.keys()):
                if inputs[f]['path'] not in found_paths:
                    try: f.close()
                    except: pass
                    del inputs[f]
            last_scan = current_time
        except Exception:
            pass

    # 3. READ INPUTS
    if inputs:
        readable, _, _ = select.select(list(inputs.keys()), [], [], 0.1)

        for f in readable:
            try:
                dev_type = inputs[f]['type']
                btn_val = None

                if dev_type == 'js':
                    data = f.read(8)
                    if not data: continue 
                    _, value, type, number = struct.unpack('IhBB', data)
                    if type == 1 and value == 1: btn_val = number
                
                elif dev_type == 'kbd':
                    data = f.read(ev_size)
                    if not data: continue
                    _, _, type, code_val, value = struct.unpack(ev_fmt, data)
                    # Type 1=EV_KEY, Value 1=Pressed. 103=Up, 108=Down
                    if type == 1 and value == 1:
                        if code_val == 103: btn_val = 0
                        elif code_val == 108: btn_val = 1

                if btn_val is not None:
                    print(f'INPUT: {btn_val}')
                    sys.stdout.flush()
                    
                    if btn_val == code[len(entered)]:
                        entered.append(btn_val)
                        if entered == code:
                            print('ACCESS GRANTED.')
                            sys.exit(0)
                    else:
                        if len(entered) > 0:
                            print(f'DEBUG: Wrong input {btn_val}. Resetting sequence.')
                            sys.stdout.flush()
                        entered = []
                        if btn_val == code[0]:
                            entered.append(btn_val)
            except Exception:
                pass
    else:
        time.sleep(0.1)
"
LOCK_RESULT=$?

kill $KIOSK_PID 2>/dev/null
rm -f "$KIOSK_FILE"
[ -n "$KIOSK_PROFILE" ] && rm -rf "$KIOSK_PROFILE"

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
