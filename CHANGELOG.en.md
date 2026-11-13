# Changelog

<p>
  <a href="CHANGELOG.md">繁體中文</a> · <strong>English</strong>
</p>

## 2.4 — 2026-11-14

- New Receiver page (between Keyboard and Advanced): pair a new mouse or keyboard with a Logi Bolt receiver (including the passkey typed on a keyboard or clicked on a mouse), list the paired devices and unpair them, without installing Logi Bolt or Logi Options+. Before unpairing, the app checks that the slot still holds the same device; with more than one receiver plugged in, receivers are shown but not changed.
- When the channel a mouse or keyboard uses for this computer stores a different name (a channel paired through Logi Bolt is stored as "Logitech Bolt receiver", for one), this computer's name is written to the device, so MX Flow shows the right computer and the keyboard-follows matching is more accurate (as Logi Options+ does; only the current channel is written).
- Pointer & Wheel: new ratchet torque (1–100), device-side thumb-wheel inversion (the left/right action mappings stay as they are) and high resolution for the main wheel (scrolling may become faster). Shown only when the device supports them; applied values are saved and re-applied when the mouse reconnects.
- Keyboard page: new switches for the keys the keyboard allows to disable (Caps Lock, for one), the OS layout for the current Easy-Switch channel, and backlight delays for hands away, hands near and external power (1–600 seconds, in 5-second steps).
- Every new setting is read back after writing, and other settings in the same group are left untouched.

## 2.3.1 — 2026-11-14

- Fix: with the mouse and a Logitech keyboard that supports button diversion (an MX Mechanical, for one) on the same Logi Bolt receiver and the keyboard in an earlier slot, the app took the keyboard for the mouse and never connected to the mouse. The device type is now checked and slots that are not a mouse are skipped.
- Fix: with the mouse connected through a Logi Bolt receiver, a connection notice from another device on the same receiver (a keyboard waking up or coming back from another computer) also made the app re-check the mouse, and an idle mouse could be taken as disconnected and reconnected. Only notices from the mouse's own slot are acted on now.

## 2.3 — 2026-11-13

- New Keyboard page (between MX Flow and Advanced) for a Logitech keyboard connected to this Mac over Bluetooth (tested with an MX Mechanical Mini). Like the mouse it shows connection, battery and firmware; it sets the backlight (automatic, manual brightness or off) and whether the top row sends media keys or F1–F12, and lists the keyboard's Easy-Switch channels. Settings live on the keyboard and count as applied once it confirms them.
- MX Flow: the keyboard follows the mouse. When the mouse moves to another computer (screen edge, a Switch-to-channel action or the Switch button), the keyboard moves to the matching channel, only after the mouse switch went out. Each mouse channel can pick a keyboard channel; Automatic uses the channel with the same computer name, otherwise the same number, and a channel can also leave the keyboard where it is. A keyboard on a Bolt receiver is not supported on the Mac yet.
- The bottom-left corner of the settings window shows both mouse and keyboard battery (one row each, with a device icon).
- Screenshots retaken (the sidebar now has Keyboard).

## 2.2.1 — 2026-10-17 (updated 2026-10-23)

- Fix: when writing the precision-mode speed failed, the hint still said "Pointer speed restored". The hint now waits for the mouse to confirm; a failed write is retried once, then "Pointer speed not restored" shows and the speed is written again on quit (the saved speed is also restored on reconnect). A failed switch into precision mode is reported too instead of staying on.
- Fix: turning the low-battery alert on while the battery was already below the threshold never alerted.
- Fix: pausing while holding the MX Flow key and releasing it before resuming left the key counted as held, so pushing a screen edge could switch computers by mistake.
- Fix: if the mouse didn't confirm the new speed when turning on precision mode (for example a read-back timeout after the speed had actually dropped), the pointer could stay at the precision speed even after releasing the button. The normal speed is now written back in the background, and once more on quit if that also fails.
- Fix: changing the pointer speed on the Pointer & Wheel page while precision mode was on left the pointer at the precision speed if the mouse didn't confirm the new value. The normal speed is now restored.

## 2.2 — 2026-10-17

- New Haptics page (between Pointer & Wheel and MX Flow). The haptic strength moves here from Pointer & Wheel, and four haptic moments can each be switched on or off, given a waveform and tried:
  - Actions Ring slices (moved from the Gestures & Ring page; the setting carries over)
  - Gesture recognized (new, on by default, soft bump)
  - MX Flow switch, right before the mouse leaves (new, on by default, crisp bump)
  - Mode changes: precision mode on/off and ratchet / free spin (new, on by default, crisp)
- New precision mode: hold the chosen button to drop the pointer to a slower DPI (400 by default) for detailed work; release to go back. Set the speed and pick the trigger on the Pointer & Wheel page.
- New Mouse category in the action menu: Precision mode (hold), Precision mode (toggle), Toggle ratchet / free spin. Available on buttons, gestures and the ring; from the ring or a gesture, "hold" works as a toggle.
- On-screen hint: when precision mode or the wheel mode changes, the new state shows briefly at the bottom of the screen (can be turned off on Pointer & Wheel).
- The "Subtle (default)" waveform is now just "Subtle", since each haptic moment has its own default.
- New Switch to channel 1 / 2 / 3 actions (Easy-Switch category): a button, gesture or Actions Ring slice moves the mouse straight to that Easy-Switch channel. The ring shows "Channel N"; the menu adds the computer name stored on the channel. Nothing happens on the current channel or an unpaired one.
- Low-battery alert (new Battery card on the Advanced page, on by default): one system notification when the level drops to the threshold (15% by default, 5–30%) while not charging; it alerts again only after charging. If notifications are turned off, a hint shows at the bottom of the screen instead.
- Pause haptics on low battery (Haptics page, on by default): below the threshold and not charging, no automatic taps play; the Try buttons still do. The page says so while paused.
- The Permissions card on the Advanced page has a new Notifications row, so low-battery notifications can be allowed in advance; once declined, its button opens the Notifications page of System Settings.
- Gesture sensitivity (Gestures & Ring page, 50% = the original distance): higher means a shorter swipe picks a direction.
- The Haptics page's "MX Flow switch" is now "Computer switch" and also covers the Switch to channel actions.
- Smaller default Actions Ring (matching the Windows edition 2.2): the new Overall size 50% (the default) equals the old 44%. Saved percentages are kept, so an existing ring shows about 6% smaller.

## 2.1 — 2026-10-15

- Actions Ring: new "Haptic tick on each slice" (on by default) — the mouse taps lightly as the pointer moves onto another slice. Choose from six waveforms (picking one plays it at once, and there is a Try button); the strength follows Haptic feedback on the Pointer & Wheel page.
- Actions Ring: new White color option ("Color" on the Gestures & Ring page; dark stays the default).
- New action "MX Settings": a button, gesture or Actions Ring slice can open this app's settings window.

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
- Fix: the mouse was not found when the receiver was already plugged in and the mouse switched to it later.
- Fix: the mouse was not found over Bluetooth while the receiver stayed plugged in.
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
