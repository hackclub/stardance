# Native Mac movement detector

1. In Thonny, open `main.py` from this folder. Save a copy to **Raspberry Pi Pico** with the exact name `main.py`. This replaces any existing startup script of that name.
2. Quit Thonny, then unplug and reconnect the Pico without pressing BOOT. The saved script starts automatically.
3. Double-click `Start.command` in Finder. A 🥀 icon appears in the Mac menu bar. You can close Terminal afterward.
4. Use any app normally. Above 70%, a native popup covers the screen under your pointer and plays the included MP3 once. The detector rearms after the score drops to 30% or lower.

Use the 🥀 menu's **Test popup + audio** to check without shaking. **Escape** or **Dismiss / stop audio** closes it and restores the previous app. Use **Quit detector** before opening Thonny again. No browser is needed. This is not installed as a login item; relaunch it after restarting your Mac. macOS lock screens and protected system screens are not covered.

Wiring: sensor S to GPIO2, sensor minus to GND, center pin disconnected. The score measures recent switch activity, not a probability or exact movement count.

No Python packages are required. The native app reads the Python worker through a local pipe, with no web server. Audio and readings stay local. Existing firmware that prints `Suspicion: 80%` in the previous format is also compatible. The optional old browser dashboard is still available with `python3 server.py` when the native detector is closed.
