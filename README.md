# Sunshine Ubuntu Wrapper & Gamepad Monitoring

A robust suite of scripts for Sunshine on Ubuntu/Linux that provides automated game discovery, idle timeouts, and immediate session termination when a game exits.

## 🚀 Key Features

- **Desktop Security**: Automatically closes the Sunshine session the moment a game is exited. Prevents unattended desktop access.
- **Auto-Discovery**: Scans Steam, Heroic (Epic/GOG/Amazon), and Nile to automatically populate Sunshine's `apps.json`.
- **Idle Watchdog**: Terminates the session after 10 minutes of inactivity. Filters out system "noise" (audio/video events) to only reset on actual user input.
- **Emergency Kill Switch**: Press the "Guide/Mode" button on your gamepad to immediately close the game and the session.

## 🛠 Setup

1. **Install Dependencies**:
   ```bash
   sudo apt install python3-evdev jq
   ```

2. **Permissions**:
   Ensure your user has access to `/dev/input/`:
   ```bash
   sudo usermod -aG input $USER
   ```

3. **Deploy Scripts**:
   Place these scripts in your home directory:
   - `launch_heroic.sh`
   - `idle_watchdog.py`
   - `kill_switch.py`
   - `sync_games.sh`

4. **Sync Games**:
   Run the sync script to populate Sunshine:
   ```bash
   ./sync_games.sh --apply
   ```
