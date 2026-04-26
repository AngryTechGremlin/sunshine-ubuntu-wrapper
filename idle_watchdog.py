import evdev
from evdev import ecodes
import select
import time
import sys

# --- CONFIGURATION ---
TIMEOUT_SECONDS = 600

def is_input_device(dev):
    """Filter for actual user input devices."""
    try:
        caps = dev.capabilities()
        if ecodes.EV_KEY in caps:
            keys = caps[ecodes.EV_KEY]
            if ecodes.KEY_A in keys or 304 in keys or 316 in keys or ecodes.BTN_LEFT in keys:
                return True
        if ecodes.EV_REL in caps:
            return True
        if ecodes.EV_ABS in caps:
            name = dev.name.lower()
            if any(x in name for x in ["touch", "pen", "pad", "tablet", "joystick", "gamepad"]):
                return True
    except:
        pass
    return False

def main():
    devices_by_path = {}
    last_activity_time = time.time()
    last_scan_time = 0

    while True:
        current_time = time.time()
        if current_time - last_scan_time > 5.0:
            last_scan_time = current_time
            try:
                found_paths = set(evdev.list_devices())
                current_paths = set(devices_by_path.keys())
                for path in found_paths - current_paths:
                    try:
                        dev = evdev.InputDevice(path)
                        if is_input_device(dev):
                            devices_by_path[path] = dev
                    except OSError: pass
                for path in current_paths - found_paths:
                    if path in devices_by_path: del devices_by_path[path]
            except Exception: pass

        elapsed = current_time - last_activity_time
        if elapsed >= TIMEOUT_SECONDS:
            sys.exit(0)

        if not devices_by_path:
            time.sleep(1)
            continue

        fd_to_dev = {dev.fd: dev for dev in devices_by_path.values()}
        try:
            r, _, _ = select.select(fd_to_dev.keys(), [], [], min(1.0, TIMEOUT_SECONDS - elapsed))
            if r:
                last_activity_time = time.time()
                for fd in r:
                    try:
                        for event in fd_to_dev[fd].read(): pass 
                    except (OSError, BlockingIOError): pass
        except:
            devices_by_path = {}
            continue

if __name__ == "__main__":
    main()
