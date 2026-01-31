# Parental Control Game Wrapper for Sunshine

This is gen AI that will be personalized at a future point

A robust Bash wrapper script designed for launching games via **Heroic Games Launcher** or **Steam** on Linux. It is built specifically for game streaming setups using **Sunshine** and **Moonlight**.
This wrapper adds a layer of parental control and session management that standard launchers lack.

## 🛡️ Features

*   **🎮 Controller and Keyboard Security Lock**: Before the game launches, a "kiosk" lock screen (via Firefox) appears. The game only starts after a specific button code (e.g., A, B, A, B) is entered on a connected gamepad. Added support for keyboard using the same pattern but instead of A and B its Up and Down. Code set by default using keyboad Up Down Up Down.
*   **⏳ Playtime Limits**: Enforces a hard playtime limit (default: 1 hour). The game automatically closes when time is up.
*   **💀 Kill Switch**: Pressing the **Xbox / Guide button** on the controller immediately kills the game and the session. Perfect for quickly exiting stubborn games.
*   **👀 Process Watchdog**: Monitors the game process. If the game crashes or is closed manually, the script cleans up immediately.
*   **📝 Logging**: Optional debug logging to track usage and issues.

## 📋 Requirements

*   **Linux OS**
*   **Python 3** (Standard library only, no `pip` packages required)
*   **Firefox** (Used for the lock screen kiosk mode)
*   **Heroic Games Launcher** or **Steam**
*   **Sunshine** (Required)

## ⚙️ Configuration

Open `launch_heroic.sh` in a text editor to customize:

1.  **Secret Code**: Change `SECRET_CODE="0,1,0,1"` to your desired button sequence.
    *   *Note: 0=A, 1=B, etc. Check your controller mappings.*
2.  **Playtime**: Change `PLAYTIME_LIMIT=3600` (in seconds) to set the allowed session duration.
3.  **Lock Screen**: The script generates a temporary HTML file for the lock screen. You can customize the HTML in the `KIOSK_FILE` section.

### Firefox Configuration (This may no longer be needed with profiles working)
To prevent Firefox from getting stuck in "Safe Mode" or showing a crash recovery dialog after the script kills it:
1.  Open Firefox and go to `about:config`.
2.  Search for `toolkit.startup.max_resumed_crashes`.
3.  Set the value to `-1`.

## 🚀 Usage

The script requires 4 arguments:

```bash
./launch_heroic.sh <APP_ID> <PROCESS_NAME> <STARTUP_TIMEOUT> <RUNNER>
