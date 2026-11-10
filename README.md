# Notchline

Notchline is a native macOS menu bar app that brings media controls and system alerts to the notch. Hover to open the player, or glance at the notch for a volume change, a battery warning, or an AirPods connection.

---

## ✨ Features

- Compact and expanded Now Playing views with artwork, playback controls, a scrubber for timed media, and a live indicator for streams
- A volume slider for the active audio output, when the device supports it
- Notch alerts for volume, brightness, battery, Focus, and headphone connections
- A rotating 3D AirPods Pro model and a battery ring when charge data is available
- A notch overlay that follows desktop switches and hides on the lock screen and in full-screen Spaces
- Settings with previews for playback and alerts, plus Liquid Glass on macOS 26 or later when built with its SDK or newer

---

## 🚀 Getting Started

### Build from source

- macOS 14 or later
- Xcode 16 or later, or the corresponding Xcode Command Line Tools for a terminal build

```sh
git clone https://github.com/TobiasAschenbrenner/notchline.git
cd notchline
./build.sh
open build/Notchline.app
```

The script builds and ad-hoc signs the app locally. Use the capsule icon in the menu bar to open **Settings**, show or hide the notch, or quit.

### Package a ZIP

Run `./build.sh --zip` to create a distributable ZIP in `build/` for the current architecture. Extract the ZIP and move **Notchline.app** to **Applications**.

The packaged app is ad-hoc signed and has not been notarized by Apple, so macOS may show a warning on first launch if you download the ZIP. [Apple’s guidance for opening downloaded apps](https://support.apple.com/en-au/102445)

### Develop in Xcode

```sh
open Notchline.xcodeproj
```

Select the **Notchline** scheme and **My Mac**, then press **⌘R**. Use **Notch States** and **Notchline Settings** in Xcode Canvas to preview the interface while editing. [Notch preview](Sources/Notch/NotchView.swift) · [Settings preview](Sources/Settings/SettingsView.swift)

---

## ▶️ Using Notchline

- **Playback.** Start media in an app or browser tab that appears in macOS Control Center’s Now Playing panel. Hover over the notch for controls. Select the output icon to show its volume slider.
- **Sound and Display.** Enable **Volume alerts** or **Brightness alerts** in the corresponding Settings panel, then select **Allow Keyboard Controls…** to grant Accessibility access. macOS handles keys that Notchline cannot adjust. The brightness slider controls the built-in display.
- **Connectivity.** Enable **Detect Bluetooth connections** for Bluetooth accessory alerts. The AirPods ring uses the lower reported earbud charge when both buds report. It can fill in shortly after connection as charge data arrives.
- **Focus.** Select **Allow Focus Status…** in Settings to share Focus status with Notchline.

---

## 🛠 Tech Stack

- **Swift, SwiftUI, and AppKit** for the notch, menu bar, settings, and animations
- **RealityKit** for the AirPods Pro model
- **Core Audio, IOKit, and IOBluetooth** for system activity and device controls
- **Objective-C and Perl** for the bundled MediaRemote Adapter

---

## 📁 Project Structure

```text
notchline/
├── Sources/
│   ├── App/          App lifecycle, menu, and self-tests
│   ├── Notch/        Overlay, playback views, layout, and animation
│   ├── Playback/     Now Playing metadata, stream decoding, and commands
│   ├── Settings/     Preferences, controls, and previews
│   └── System/       Audio, display, battery, Bluetooth, and Focus
├── Resources/        App icon and AirPods Pro model
├── Vendor/           Bundled MediaRemote Adapter
├── Notchline.xcodeproj
└── build.sh          Terminal build and local signing
```

---

## 🧪 Quality Checks

Build and run the hardware-independent self-tests from the repository root.

```sh
./build.sh
build/Notchline.app/Contents/MacOS/Notchline --self-test
```

The checks cover media parsing, hover and alert transitions, keyboard event routing, settings migration, and battery data.

---

## 🙌 Platform Notes and Credits

- Notchline uses private macOS interfaces for Now Playing, display brightness, and Spaces detection. Those interfaces can change between macOS releases.
- The bundled MediaRemote Adapter is by Jonas van den Berg and contributors and is distributed under the BSD 3-Clause license. [Upstream project](https://github.com/ungive/mediaremote-adapter) · [Bundled license](Vendor/MediaRemoteAdapter/LICENSE)
- The AirPods Pro glyph adapts Jayrenn Reeve’s CC0 model to show the two earbuds. [Model source](https://www.blendkit.com/asset-gallery-detail/27fb8b1c-fc79-41d4-9e2b-fef9d75329c1/)
- The notch and Settings designs take inspiration from [Alcove](https://tryalcove.com/).
