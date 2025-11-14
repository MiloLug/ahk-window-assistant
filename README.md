# Window Management Assistant in AHK

I miss the window navigation from DWM and Hyprland, so here I attempt to bring it with me to Windows.

## What is this?

This is an AutoHotkey-based window management helper (it doesn't replace the default WM in any way) that tries to make Windows WM behave in more intuitive ways, for me that is.

It's basically my way of not going insane after completely switching to Windows.

## ⚠️ NOT READY YET

Everything here is super experimental/spaghetti and will probably change dramatically. Don't expect stability - this is more of a "works on my machine" situation right now.

### Requirements (my actual machine)

- Windows 11 22H2+
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor)
- Enabled 'focus follows mouse' WITHOUT raising focused windows
- 'Virtual Desktop Preserve Taskbar Order' in Windhawk (recommended)

## What does it do?

The main script (`Main.ahk`) sets up a bunch of keyboard shortcuts:

### Virtual Desktop Navigation
- `Alt + 1-9`: Jump to desktop 1-9
- `Alt + 0` or `Alt + b`: Go to last desktop (like alt-tab but for desktops)

### Window Management
- `Alt + Shift + 1-9`: Move current window to desktop 1-9
- `Alt + Shift + 0` or `Alt + Shift + b`: Move current window to last desktop
- `Alt + h/j/k/l`: Navigate between windows and monitors (left/down/up/right)
- `Alt + i`: Navigate to next overlapping window
- `Alt + Ctrl + C`: Close current window
- `Alt + P`: Pin/unpin window (will appear on all desktops)
- `Alt + Ctrl + P`: Pin window and keep it on top

### Mouse Controls
- `Alt + Ctrl + Left Click`: Drag window freely (holding anywhere)
- `Alt + Ctrl + Right Click`: Resize window freely

### Other Stuff
- `Win + Tab`: Navigate through current app's windows (across desktops)
- `CapsLock`: Language switch (Shift+Alt)
- `Shift + CapsLock`: Original behavior of CapsLock
- Some fixes for mouse following new windows and keyboard focus (alt-tab)


#### Disclaimers

Windows is a registered trademark of Microsoft Corporation. This project is not affiliated with or endorsed by Microsoft.