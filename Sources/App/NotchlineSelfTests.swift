import AppKit

@MainActor
enum NotchlineSelfTests {
    static func run() -> Bool {
        let model = NotchModel()
        let geometry = NotchGeometry.preview
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let frame = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.example.player","title":"Example","artist":"Artist","playing":true,"durationMicros":100000000,"elapsedTimeMicros":40000000,"timestampEpochMicros":1700000000000000,"playbackRate":1}}"#
        let track = MediaRemoteAdapter.decode(Data(frame.utf8), now: now)?.track
        let liveFrame = #"{"type":"data","diff":false,"payload":{"parentApplicationBundleIdentifier":"com.google.Chrome","title":"Live stream","playing":true,"durationMicros":120000000,"isLiveStream":true}}"#
        let browserFrame = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome","title":"Video","durationMicros":635000000,"prohibitsSkip":true}}"#
        let unknownFrame = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"Loading"}}"#
        let liveTrack = MediaRemoteAdapter.decode(Data(liveFrame.utf8), now: now)?.track
        let browserTrack = MediaRemoteAdapter.decode(Data(browserFrame.utf8), now: now)?.track
        let unknownTrack = MediaRemoteAdapter.decode(Data(unknownFrame.utf8), now: now)?.track
        let cleared = MediaRemoteAdapter.decode(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8), now: now)
        let compact: [NotchPresentation] = [.idle, .compact, .alert(.volume), .alert(.brightness), .alert(.headphones)]
        let low = PowerState(percentage: 10, pluggedIn: false, lowPower: false)
        let prior = PowerState(percentage: 11, pluggedIn: false, lowPower: false)

        model.updateTrack(track)
        let showsPeek = NotchPresentation(model: model) == .peek
        model.show(.volume(0.8, muted: true), isPreview: true)
        let initialAlert = model.alert
        model.show(.focus(true))
        let preservesPreview = model.alert == initialAlert && NotchPresentation(model: model) == .alert(.volume)
        model.setExpanded(true)
        model.outputVolumeOpen = true
        let showsVolume = NotchPresentation(model: model) == .volumeControl
        model.setExpanded(false)

        var hover = NotchHover()
        let waitsToOpen = hover.expansion(inside: true, expanded: false, dragging: false, now: 1) == nil
        let opens = hover.expansion(inside: true, expanded: false, dragging: false, now: 1.10) == true
        let keepsOpen = hover.expansion(inside: false, expanded: true, dragging: true, now: 2) == nil
        let waitsToClose = hover.expansion(inside: false, expanded: true, dragging: false, now: 3) == nil
        let closes = hover.expansion(inside: false, expanded: true, dragging: false, now: 3.15) == false
        let report = #"{"SPBluetoothDataType":[{"device_connected":[{"Earbuds":{"device_address":"11:22:33:44:55:66","device_batteryLevelLeft":"82%","device_batteryLevelRight":"65%","device_batteryLevelCase":"12%"}},{"Other":{"device_batteryLevelMain":"2%"}}]}]}"#
        let battery = AccessoryBattery.charge(in: Data(report.utf8), name: "Earbuds", address: "11-22-33-44-55-66")
        let absentBattery = AccessoryBattery.charge(in: Data(report.utf8), name: "Unknown", address: nil)
        model.show(.headphones("Earbuds", "airpodspro", connected: true), isPreview: true)
        let headphonePreview = model.alert
        model.dismissAlert()
        let batteryModel = NotchModel()
        if batteryModel.headphonesAlerts {
            batteryModel.showHeadphones("Earbuds", icon: "airpodspro", connected: true)
            batteryModel.updateHeadphoneBattery("Earbuds", battery: 65)
        }
        let updatesCharge = !batteryModel.headphonesAlerts || batteryModel.alert?.subtitle == "Connected, 65% battery"
        batteryModel.dismissAlert()

        let alerts: [NotchAlert] = [.volume(0.6, muted: false), .brightness(0.7), .focus(true),
                                    .headphones("Earbuds", "airpodspro", connected: true, battery: 65),
                                    .power(low, title: "Low battery")]
        let standardHUD = geometry.size(for: .alert(.volume))
        let matchesAlertGeometry = alerts.allSatisfy { alert in
            model.show(alert, isPreview: true)
            let presentation = NotchPresentation(model: model)
            let expected = alert.kind == .headphones ? geometry.size(for: .compact) : standardHUD
            return presentation == .alert(alert.kind) && geometry.size(for: presentation) == expected
        }

        let motionModel = NotchModel()
        motionModel.updateTrack(track)
        motionModel.setExpanded(true)
        let compactFrame = NotchFrame(.compact, geometry: geometry)
        let playerMotion = NotchMotion(from: compactFrame, to: NotchScene(model: motionModel), geometry: geometry, at: 0)
        let playerSize = geometry.size(for: .expanded)
        let playerPeak = playerMotion.frame(at: 0.26)
        motionModel.show(.volume(0.5, muted: false), isPreview: true)
        let hoveredHUD = NotchPresentation(model: motionModel)
        let playerToHUD = NotchMotion(from: playerPeak, to: NotchScene(model: motionModel), geometry: geometry, at: 1)
        let playerHUDHandoff = playerToHUD.frame(at: 1 + NotchMotion.handoffDuration)
        motionModel.endLevelHover()
        let keepsLevelOnExit = NotchPresentation(model: motionModel) == .alert(.volume)
        motionModel.show(.volume(0.7, muted: false), isPreview: true)
        let stillSameHUD = NotchPresentation(model: motionModel) == .alert(.volume) && motionModel.alert?.value == 0.7
        let startHUD = NotchFrame(.alert(.volume), geometry: geometry, alert: motionModel.alert)
        motionModel.dismissAlert()
        let returnMotion = NotchMotion(from: startHUD, to: NotchScene(model: motionModel), geometry: geometry, at: 2)
        let handoff = returnMotion.frame(at: 2 + NotchMotion.handoffDuration)
        let retarget = NotchMotion(from: handoff, to: NotchScene(model: motionModel), geometry: geometry, at: 3)
        model.dismissAlert()
        let airPods = SoundOutput(id: 1, source: nil, name: "AirPods Pro", transport: nil, volume: 0.6, muted: false)

        let checks: [(String, Bool)] = [
            ("Compact states align with the menu bar", compact.allSatisfy { geometry.size(for: $0).height == geometry.cameraHeight }),
            ("Track peek and intentional expansion", showsPeek && showsVolume && !model.outputVolumeOpen && geometry.size(for: .volumeControl).height < geometry.panelHeight),
            ("Monochrome HUD mute state", initialAlert?.value == 0 && initialAlert?.icon == "speaker.slash.fill" && initialAlert?.duration == 1.65),
            ("Preview isolation", preservesPreview && model.alert == nil && headphonePreview?.icon == "airpodspro"),
            ("Hover dwell, exit and drag hold", waitsToOpen && opens && keepsOpen && waitsToClose && closes),
            ("AirPods bud charge, case exclusion and late update", battery == 65 && absentBattery == nil && updatesCharge),
            ("Standard HUD and AirPods compact geometry", matchesAlertGeometry && standardHUD.width < geometry.panelWidth),
            ("AirPods Pro model is bundled", Bundle.main.url(forResource: "AirPodsPro", withExtension: "usdz") != nil),
            ("Headphone alert hands off to and from compact playback", headphonePlaybackHandoff(track: track, geometry: geometry)),
            ("White HUD rail, device icon and volume bounds", NotchHUDMetrics.railWidth == 68 && NotchHUDMetrics.railHeight == 4
                && alerts[0].symbol(for: airPods) == "airpodspro"
                && initialAlert?.symbol(for: airPods) == "airpodspro"
                && geometry.size(for: .volumeControl).height - playerSize.height == 32),
            ("Player content reveals during expansion and geometry overshoots",
                playerMotion.frame(at: 0.04).player == 0 && playerMotion.frame(at: 0.16).player > 0.7
                && playerPeak.size.width > playerSize.width && playerPeak.size.height > playerSize.height
                && playerPeak.size.height < playerSize.height + 6
                && playerMotion.frame(at: 0.6).size == playerSize),
            ("Hover-held level alert survives pointer exit and repeat inputs",
                hoveredHUD == .alert(.volume, hovered: true) && keepsLevelOnExit && stillSameHUD
                && playerHUDHandoff.player < 0.01 && playerHUDHandoff.hud == 0),
            ("HUD retracts before playback and interruption preserves geometry",
                handoff.size.width < compactFrame.size.width && handoff.hud < 0.01 && handoff.media == 0
                && retarget.frame(at: 3).size == handoff.size && returnMotion.frame(at: 3).size == compactFrame.size),
            ("Sound, Display and Focus labels", alerts[0].leadingLabel == "Sound" && alerts[1].leadingLabel == "Display"
                && alerts[2].trailingLabel == "On" && NotchAlert.focus(false).trailingLabel == "Off"),
            ("Hardware level step bounds and fine adjustments", LevelKey.soundUp.nextLevel(from: 0.5, fine: false) == 0.5625
                && LevelKey.displayDown.nextLevel(from: 0.5, fine: true) == 0.484375
                && LevelKey.displayUp.nextLevel(from: 1, fine: false) == 1
                && LevelKey.soundDown.nextLevel(from: 0, fine: false) == 0),
            ("Keyboard filter owns complete presses and passes unsupported keys to macOS", levelKeyRouting()),
            ("Legacy alerts preference migrates and volume and brightness stay independent", independentLevelAlerts()),
            ("System media frame and elapsed position", track?.title == "Example" && track?.position(at: now.addingTimeInterval(20)) == 60),
            ("Media stream handles split frames and discards oversized lines", mediaStreamFraming(frame: frame, now: now)),
            ("Live, timed video and unavailable timelines", liveTrack?.isLive == true && liveTrack?.canSeek == false && liveTrack?.canSkip == false
                && browserTrack?.canSeek == true && browserTrack?.canSkip == false && browserTrack?.fallbackArtwork == "play.rectangle.fill"
                && unknownTrack?.isLive == false && unknownTrack?.canSeek == false),
            ("Empty system media session", cleared != nil && cleared?.track == nil),
            ("Battery threshold crosses once", low.crossedWarning(from: prior) && !low.crossedWarning(from: low))
        ]
        for (name, passed) in checks { print("\(passed ? "PASS" : "FAIL")  \(name)") }
        return checks.allSatisfy { $0.1 }
    }

    private static func mediaStreamFraming(frame: String, now: Date) -> Bool {
        let bytes = Data(frame.utf8)
        let midpoint = bytes.count / 2
        var stream = MediaRemoteAdapter.StreamDecoder(maximumLineBytes: bytes.count)
        guard stream.consume(bytes.prefix(midpoint), now: now).isEmpty else { return false }

        var remainder = Data(bytes.dropFirst(midpoint))
        remainder.append(contentsOf: "\n{\"type\":\"data\",\"diff\":false,\"payload\":{}}\n".utf8)
        let split = stream.consume(remainder, now: now)
        guard split.count == 2, split[0].track?.title == "Example", split[1].track == nil else { return false }

        let oversized = Data(repeating: 0x20, count: bytes.count + 1)
        guard stream.consume(oversized, now: now).isEmpty else { return false }
        let recovered = stream.consume(Data("\(frame)\n\(frame)\n".utf8), now: now)
        return recovered.count == 1 && recovered.first?.track?.title == "Example"
    }

    private static func headphonePlaybackHandoff(track: MediaTrack?, geometry: NotchGeometry) -> Bool {
        let model = NotchModel()
        model.setExpanded(true)
        model.updateTrack(track)
        model.setExpanded(false)
        guard NotchPresentation(model: model) == .compact else { return false }

        let compact = NotchFrame(.compact, geometry: geometry)
        model.show(.headphones("AirPods Pro", "airpodspro", connected: true, battery: 45), isPreview: true)
        let opening = NotchMotion(from: compact, to: NotchScene(model: model), geometry: geometry, at: 0)
        let connected = opening.frame(at: opening.endsAt)

        model.dismissAlert()
        let closing = NotchMotion(from: connected, to: NotchScene(model: model), geometry: geometry, at: 6)
        let restored = closing.frame(at: closing.endsAt)
        let swaps = [opening.frame(at: NotchMotion.handoffDuration), closing.frame(at: 6 + NotchMotion.handoffDuration)]

        return connected.size == compact.size && connected.hud == 1 && connected.media == 0
            && connected.contour.shoulder == compact.contour.shoulder && connected.contour.corner == compact.contour.corner
            && swaps.allSatisfy { $0.size.width < compact.size.width && $0.media == 0 && $0.hud == 0 }
            && restored.size == compact.size && restored.hud == 0 && restored.media == 1 && model.track == track
    }

    private static func independentLevelAlerts() -> Bool {
        let domain = "local.notchline.self-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else { return false }
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "levelAlerts")

        let model = NotchModel(defaults: defaults)
        guard !model.isAlertEnabled(.volume), !model.isAlertEnabled(.brightness) else { return false }
        model.volumeAlerts = true
        let restored = NotchModel(defaults: defaults)
        restored.show(.brightness(0.5))
        guard restored.alert == nil else { return false }
        restored.show(.volume(0.5, muted: false))
        return restored.alert?.kind == .volume && !restored.isAlertEnabled(.brightness)
    }

    private static func levelKeyRouting() -> Bool {
        let tap = LevelKeyTap()
        var adjusted: [LevelKey] = []
        var fineStep = false
        func send(_ key: LevelKey, state: Int = 0xA, repeatKey: Bool = false, flags: CGEventFlags = []) -> Bool {
            tap.consumeAuxiliary(data: key.rawValue << 16 | state << 8 | (repeatKey ? 1 : 0), flags: flags)
        }
        tap.apply = { key, fine in
            adjusted.append(key)
            fineStep = fine
            return key != .soundDown
        }
        return send(.displayUp, flags: [.maskShift, .maskAlternate]) && fineStep
            && send(.displayUp, repeatKey: true) && send(.displayUp, state: 0xB)
            && send(.mute) && send(.mute, repeatKey: true) && send(.mute, state: 0xB)
            && !send(.soundDown) && !send(.soundDown, repeatKey: true) && !send(.soundDown, state: 0xB)
            && !send(.soundUp, flags: .maskAlternate) && !send(.soundUp, state: 0xB)
            && !tap.consumeAuxiliary(data: 16 << 16 | 0xA << 8, flags: [])
            && adjusted == [.displayUp, .displayUp, .mute, .soundDown]
    }
}
