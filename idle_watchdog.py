import evdev
import select
import time
import sys

# --- CONFIGURATION ---
# Timeout in seconds (10 minutes = 600 seconds)
TIMEOUT_SECONDS = 600

def main():
    print("Idle Watchdog started.", flush=True)
    
    # Track devices by path: path -> InputDevice
    devices_by_path = {}
    last_activity_time = time.time()
    last_scan_time = 0

    while True:
        current_time = time.time()
        
        # 1. Scan for new devices every 2 seconds
        if current_time - last_scan_time > 2.0:
            last_scan_time = current_time
            try:
                # Find new paths
                found_paths = set(evdev.list_devices())
                current_paths = set(devices_by_path.keys())
                
                # Add new devices
                for path in found_paths - current_paths:
                    try:
                        dev = evdev.InputDevice(path)
                        devices_by_path[path] = dev
                        print(f"Watchdog: Monitoring {dev.name}", flush=True)
                    except OSError:
                        pass
                
                # Remove disconnected devices
                for path in current_paths - found_paths:
                    if path in devices_by_path:
                        del devices_by_path[path]
            except Exception:
                pass

        # 2. Check Idle Time
        elapsed = current_time - last_activity_time
        
        if elapsed >= TIMEOUT_SECONDS:
            print(f"Idle limit reached ({TIMEOUT_SECONDS}s). Exiting.", flush=True)
            sys.exit(0) # Exit to signal the shell script to kill the game

        # 3. Wait for input
        if not devices_by_path:
            time.sleep(1)
            continue

        # Map file descriptors to devices for select()
        fd_to_dev = {dev.fd: dev for dev in devices_by_path.values()}
        remaining = TIMEOUT_SECONDS - elapsed
        
        # Wait up to 1.0s so we can loop back and scan for new devices
        r, _, _ = select.select(fd_to_dev.keys(), [], [], min(1.0, remaining))

        if r:
            # Input detected -> Reset Timer
            last_activity_time = time.time()
            for fd in r:
                try:
                    # Read events to clear buffer
                    for event in fd_to_dev[fd].read(): pass 
                except OSError:
                    pass

if __name__ == "__main__":
    main()
