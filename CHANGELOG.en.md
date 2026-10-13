# Changelog

<p>
  <a href="CHANGELOG.md">繁體中文</a> · <strong>English</strong>
</p>

## 2.0 — 2026-10-13

- New: **MX Flow**. Keep pushing the pointer against a screen edge and the mouse moves to another computer (the Easy-Switch channel you chose).
  - Each of the four edges (top, bottom, left, right) can target its own channel. With several displays only the outer edge of the outermost display triggers; edges between displays and corners never do.
  - Adjustable trigger time (0.1–2.0 s), and an optional held key: Control, Option, Shift, Command or a button on the mouse.
  - Resting at the edge, sliding along it, dragging with the left or right button, or an open ring or gesture never triggers a switch.
  - When the mouse comes back, the pointer can appear at the edge you set.
  - The menu bar menu also has an MX Flow item (ticked while on), so it can be switched without opening the settings window.
  - No network connection is made, no clipboard or files are transferred, and the keyboard does not follow.
- Shows the computer name and connection type stored for each of the three Easy-Switch channels, with a button to switch directly.

## 1.1.1 — 2026-10-13

- Works over the Logi Bolt receiver.
- Fixed: the mouse was not found when the receiver was already plugged in and the mouse switched to it later.
- Fixed: the mouse was not found over Bluetooth while the receiver stayed plugged in.
- After the mouse switches between Bluetooth and Logi Bolt the app follows it without a restart; while disconnected it retries every 3 seconds.

## 1.1 — 2026-10-13

First public release. The version number matches MX Master Portable 1.1 for Windows.

- Lives in the menu bar; can be paused, can launch at login, and switches between Traditional Chinese and English.
- Button mapping: middle button, gesture button, both side buttons, thumb wheel left and right, and the Actions Ring button.
- About 50 built-in actions, plus custom shortcuts and opening an app, file, folder or URL.
- Actions Ring: eight customizable slices; hold mode and click mode; Ring and Bubbles looks; adjustable overall size, bubble size and opacity.
- Four-way thumb gestures with all four directions customizable.
- Device settings: battery, firmware version, pointer speed (DPI), SmartShift, scroll direction (Natural / Standard) and haptic feedback; applied values are saved and re-applied when the mouse reconnects.
- After the mouse switches to another host and back, the special buttons are re-enabled automatically.
- Settings window: Buttons (with a mouse diagram), Gestures & Ring (with a live preview), Pointer & Wheel, and Advanced (permission status and engineering mode).
