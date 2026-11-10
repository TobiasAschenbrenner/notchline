# Notchline

Notchline is a macOS menu-bar app for Now Playing, active-output volume, brightness and system activity.

## Open Notchline

1. Unzip **Notchline.zip** and move **Notchline.app** to a permanent folder.
2. Quit any other app that draws over the notch, then open **Notchline.app**. This local build is signed for Apple silicon and targets macOS 14 or later.
3. Use the capsule icon in the menu bar to open **Settings** or hide the notch.

Hover over the notch to open the player. Move the pointer out of the notch and its panel to close it. A slider drag can finish before the panel closes. The idle state uses the hardware notch, and the overlay stays hidden in full-screen Spaces. Sound, Display, Focus and battery share a HUD shell. AirPods uses the narrower playback width.

## Playback and volume

Notchline follows the session macOS exposes in Control Center’s Now Playing panel. Play something in Spotify or in a browser tab that exposes a system media session. The notch shows the title and available artwork. Timed playback gets a scrubber, and live streams get a Live indicator and play/pause. The Mac or AirPods button opens the active output’s volume slider.

The bundled [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter) reads the system session and sends controls locally. It uses a private macOS framework whose behavior can change with system updates. Its BSD 3-Clause license is bundled with the app and source.

## System activity

Compact playback and the standard system alerts share the menu-bar height. A level alert that interrupts the hovered player is slightly larger until the pointer leaves. Focus shows On or Off on the right. The brief track peek and expanded player have room below the menu bar. Settings includes sample states, brightness and volume controls, and alert preferences.

To use the notch for hardware volume and brightness keys, open **Notchline Settings → System → Open Accessibility Settings…** and allow Notchline. **Keyboard indicators** shows **Notchline** when the key handler is active. The keys fall back to macOS when the notch is hidden, the permission is unavailable, or the device rejects the adjustment.

The system provides the available signals. **Detect Bluetooth connections** enables accessory connection alerts. The AirPods ring uses the lower reported earbud charge when both buds report. It uses the available headset charge when only one value is reported. The ring can fill in shortly after connection as Bluetooth data arrives. **Allow Focus Status** requests macOS Focus access. The brightness slider targets the built-in display.

## Build from source

With macOS Command Line Tools installed, run these commands from this folder.

```sh
./build.sh
open build/Notchline.app
build/Notchline.app/Contents/MacOS/Notchline --self-test
```
