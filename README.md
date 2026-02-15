# Parental Control Game Wrapper for Sunshine

This is gen AI that will be personalized at a future point

A robust Bash wrapper script designed for launching games via **Heroic Games Launcher** or **Steam** on Linux. It is built specifically for game streaming setups using **Sunshine** and **Moonlight**.
This wrapper adds a layer of parental control and session management that standard launchers lack.

## 🛡️ Features

*   **🎮 Controller and Keyboard Security Lock**: Before the game launches, a "kiosk" lock screen (via Firefox) appears. The game only starts after a specific button code (e.g., A, B, A, B) is entered on a connected gamepad or keyboard. The default code sequence is A, B, A, B.
*   **⏳ Playtime Limits**: Enforces a hard playtime limit (default: 1 hour). The game automatically closes when time is up.
*   **💀 Kill Switch**: Pressing the **Xbox / Guide button** on the controller immediately kills the game and the session. Perfect for quickly exiting stubborn games.
*   **👀 Process Watchdog**: Monitors the game process. If the game crashes or is closed manually, the script cleans up immediately.
*   **📝 Logging**: Optional debug logging to track usage and issues.

## 📋 Requirements

*   **Linux OS**
*   **Python 3** and **pip**
*   **python-evdev** library (e.g., `sudo pip install evdev`)
*   **Firefox** (Used for the lock screen kiosk mode)
*   **Heroic Games Launcher** or **Steam**
*   **Sunshine** (Required)

## ⚙️ Configuration

Configuration is done by editing the scripts directly.

1.  **Secret Code**: Open `controller_lock.py` and modify the `UNLOCK_SEQUENCE` list.
    *   This sequence applies to both controllers and keyboards.
    *   `ACTION_A` is the 'A' button on a controller or 'A' key on the keyboard.
    *   `ACTION_B` is the 'B' button on a controller or 'B' key on the keyboard.

2.  **Playtime Limit**: Open `launch_heroic.sh` and change the `LIMIT=3600` variable (value is in seconds).

3.  **Lock Screen Message**: Open `launch_heroic.sh` and find the `echo "<html>..."` line to change the message displayed on the lock screen.

## 🚀 Usage

The script requires 4 arguments:

```bash
./launch_heroic.sh <APP_ID> <PROCESS_NAME> <STARTUP_TIMEOUT> <RUNNER>
