# Display Volume

Control the volume of an external monitor on macOS — with the keyboard volume keys, like on Windows.

When a Mac sends sound to a monitor over HDMI or DisplayPort, macOS gives you no volume control: the volume keys do nothing, and the sound plays at the monitor's full level. Display Volume fixes that in software. It lowers the sound on the Mac before it reaches the monitor, so it works even when the monitor does not accept volume commands (DDC/CI) and you cannot reach its buttons.

## Features

- Keyboard volume up, down and mute keys work again, with an on-screen volume pop-up.
- Hold **Shift + Option** while pressing a volume key for finer steps, like macOS.
- Menu bar slider with the exact percentage, and a Mute option.
- Only steps in when the current output has no volume control of its own. On outputs that have their own volume, such as the built-in speakers, macOS volume works as usual.
- Remembers your level. Optional **Open at Login**.
- No driver, no kernel extension, no admin password. Free and open source.

## Requirements

- macOS 14.4 (Sonoma) or later.
- Apple Silicon or Intel Mac (universal app).

Tested on a MacBook Air (M4) with macOS 26.5 and a DisplayPort monitor. The Intel build has not been tested on real hardware yet.

## Install

### Download

1. Download `Display-Volume-x.y.z.zip` from the [latest release](https://github.com/davidleora/display-volume/releases/latest).
2. Unzip it and move **Display Volume.app** to **Applications**.
3. Open it. The app is not notarized by Apple, so macOS blocks the first launch. Allow it once:
   - open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to "Display Volume", or
   - run `xattr -dr com.apple.quarantine "/Applications/Display Volume.app"` in Terminal, then open the app.

### Build from source

Needs Xcode or the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/davidleora/display-volume.git
cd display-volume
./build.sh install   # builds, copies to /Applications and starts it
```

## First run: two permissions

macOS asks for these the first time:

| Permission | Why |
|---|---|
| **System Audio Recording** | To take the sound that goes to the monitor and play it back at your volume. Nothing is recorded or saved. |
| **Accessibility** | To use the keyboard volume keys. |

If macOS does not ask, add the app yourself in **System Settings → Privacy & Security** (**Screen & System Audio Recording** and **Accessibility**). The menu bar icon has shortcuts to these pages. After you allow Accessibility, the keys start working within about two seconds.

## Use

1. Choose your monitor as the sound output (menu bar sound icon, or **System Settings → Sound**).
2. Press the volume keys, or click the **speaker icon** in the menu bar and drag the slider.

The menu shows what the app is doing:

- **Controlling *monitor name*** — the volume keys and slider set this monitor's volume.
- ***device* uses the normal macOS volume** — the current output has its own volume, so the app does nothing.
- **Error: …** — something failed; click **Try Again**.

**Control Displays Without Volume** turns the app off without quitting. **Open at Login** starts it automatically.

## Troubleshooting

- **No sound at all from the monitor:** System Audio Recording is not allowed. Allow it (see above), or turn off **Control Displays Without Volume**.
- **The volume keys do nothing:** allow Accessibility. Quit other apps that also take over the volume keys (for example MonitorControl), since only one app can handle them.
- **macOS asks for permissions again after updating:** the app is signed locally (ad-hoc), so macOS sees each new build as a new app. Allow it again.

## How it works

Display Volume uses the Core Audio process tap API (macOS 14.2+):

1. It creates a tap on the monitor's output that captures every app's sound and mutes the original.
2. It creates a private aggregate device with that tap as input and the monitor as output.
3. In the audio callback it copies the sound from the tap to the monitor, multiplied by your volume (level², with a short ramp to avoid clicks).

It watches the default output device. When you switch to an output that has its own volume control, it removes the tap and the aggregate device and lets the volume keys pass through to macOS. Quitting the app also removes them, so the monitor goes back to its normal (full) level.

The volume keys are read with a `CGEventTap`. They are only taken over while the app is controlling a monitor.

## Uninstall

Quit it from the menu bar icon, delete **Display Volume.app** from Applications, and remove it from **Privacy & Security → Accessibility** and **Screen & System Audio Recording**.

## Development

```sh
./build.sh test      # core tests (key parsing, volume steps, audio copy)
./build.sh           # build build/Display Volume.app
./build.sh install   # build and install to /Applications
./build.sh release   # build and zip for a GitHub release
```

Code is in `Sources/`: `Core.swift` (pure logic), `AudioBridge.swift` (tap and aggregate device), `KeyTap.swift` (volume keys), `HUD.swift` (pop-up), `main.swift` (menu bar app).

## License

[MIT](LICENSE)
