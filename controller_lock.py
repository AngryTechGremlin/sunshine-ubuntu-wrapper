#!/usr/bin/env python3
import evdev
from evdev import ecodes
import sys
import select
import time

# ==========================================
#        UNIVERSAL INPUT MAPPING
# ==========================================
INPUT_MAP = {
    # Keyboard
    ecodes.KEY_A: 'ACTION_A',
    ecodes.KEY_B: 'ACTION_B',
    
    # Controller
    ecodes.BTN_SOUTH: 'ACTION_A',
    ecodes.BTN_EAST:  'ACTION_B',
    ecodes.BTN_A:     'ACTION_A',
    ecodes.BTN_B:     'ACTION_B',
}

UNLOCK_SEQUENCE = ['ACTION_A', 'ACTION_B', 'ACTION_A', 'ACTION_B']
TIMEOUT = 30

def get_input_devices():
    """Returns all devices that have buttons or keys."""
    try:
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    except Exception:
        return []
        
    input_devices = []
    for dev in devices:
        if ecodes.EV_KEY in dev.capabilities():
            input_devices.append(dev)
    return input_devices

def main():
    print(f"🔒 SECURITY LOCK ACTIVE", flush=True)
    print(f"   Waiting for code (A -> B -> A -> B)...", flush=True)

    start_time = time.time()
    entered_sequence = []
    last_scan = 0
    devices = []

    while True:
        current_time = time.time()

        # 1. TIMEOUT
        if current_time - start_time > TIMEOUT:
            print("\n❌ TIMEOUT.", flush=True)
            sys.exit(1)

        # 2. DEVICE SCAN (Every 1.0s)
        if current_time - last_scan > 1.0:
            devices = get_input_devices()
            last_scan = current_time
            if not devices:
                time.sleep(0.5)
                continue

        # 3. READ INPUTS
        if not devices:
            time.sleep(0.1)
            continue
        
        # Map file descriptors to device objects
        read_map = {dev.fd: dev for dev in devices}
        
        # Wait for input on ANY device
        r, _, _ = select.select(read_map.keys(), [], [], 0.1)

        for fd in r:
            dev = read_map[fd]
            try:
                for event in dev.read():
                    # FIX WAS HERE: Ensure this line is complete
                    if event.type == ecodes.EV_KEY and event.value == 1:
                        
                        if event.code in INPUT_MAP:
                            logical_input = INPUT_MAP[event.code]
                            
                            print(".", end="", flush=True)
                            entered_sequence.append(logical_input)

                            if len(entered_sequence) > len(UNLOCK_SEQUENCE):
                                entered_sequence.pop(0)

                            if entered_sequence == UNLOCK_SEQUENCE:
                                print("\n✅ ACCESS GRANTED", flush=True)
                                sys.exit(0)
            except OSError:
                pass 

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)