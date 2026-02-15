#!/usr/bin/env python3
import evdev
from evdev import ecodes
import select
import sys

# Standard "Guide" button on Xbox/PlayStation controllers
# BTN_MODE = 316
GUIDE_BUTTONS = [ecodes.BTN_MODE, 316]

def get_devices():
    return [evdev.InputDevice(path) for path in evdev.list_devices()]

def main():
    # We exit with 0 immediately if the button is pressed
    # We exit with 1 if we are killed or fail
    devices = get_devices()
    
    # Map file descriptors
    device_map = {dev.fd: dev for dev in devices}
    
    if not device_map:
        # No devices? Just sleep forever (monitor does nothing)
        select.select([], [], [])
        return

    while True:
        # Wait for input
        r, _, _ = select.select(device_map.keys(), [], [])
        
        for fd in r:
            dev = device_map[fd]
            try:
                for event in dev.read():
                    if event.type == ecodes.EV_KEY and event.value == 1:
                        # Check if it's a Guide Button
                        if event.code in GUIDE_BUTTONS:
                            # print("🛑 GUIDE BUTTON DETECTED") 
                            # (Commented out print to keep logs clean)
                            sys.exit(0)
            except OSError:
                pass # Device disconnected

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)