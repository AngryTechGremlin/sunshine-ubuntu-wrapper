#!/usr/bin/env python3
import evdev
from evdev import ecodes
import select
import sys
import time

# Standard "Guide" button on Xbox/PlayStation controllers
# BTN_MODE = 316
GUIDE_BUTTONS = [ecodes.BTN_MODE, 316]

def main():
    print("Kill Switch started.", flush=True)
    devices_by_path = {}
    last_scan_time = 0

    while True:
        current_time = time.time()

        # 1. Scan for new devices every 2 seconds
        if current_time - last_scan_time > 2.0:
            last_scan_time = current_time
            try:
                found_paths = set(evdev.list_devices())
                current_paths = set(devices_by_path.keys())
                
                for path in found_paths - current_paths:
                    try:
                        dev = evdev.InputDevice(path)
                        devices_by_path[path] = dev
                        print(f"KillSwitch: Monitoring {dev.name}", flush=True)
                    except OSError:
                        pass
                
                for path in current_paths - found_paths:
                    if path in devices_by_path:
                        del devices_by_path[path]
            except Exception:
                pass

        if not devices_by_path:
            time.sleep(1)
            continue

        # 2. Monitor Input
        fd_to_dev = {dev.fd: dev for dev in devices_by_path.values()}
        r, _, _ = select.select(fd_to_dev.keys(), [], [], 1.0)
        
        for fd in r:
            dev = fd_to_dev[fd]
            try:
                for event in dev.read():
                    if event.type == ecodes.EV_KEY and event.value == 1:
                        # Check if it's a Guide Button
                        if event.code in GUIDE_BUTTONS:
                            print("🛑 GUIDE BUTTON DETECTED", flush=True)
                            sys.exit(0)
            except OSError:
                pass

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
