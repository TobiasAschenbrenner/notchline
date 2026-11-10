import Foundation

struct PowerState: Equatable {
    let percentage: Int
    let pluggedIn: Bool
    let lowPower: Bool

    var low: Bool { !pluggedIn && percentage <= 20 }

    func crossedWarning(from prior: PowerState?) -> Bool {
        guard !pluggedIn else { return false }
        if prior == nil || prior?.pluggedIn == true { return low }
        guard let prior else { return false }
        return [20, 10, 5].contains { prior.percentage > $0 && percentage <= $0 }
    }

    var icon: String {
        if pluggedIn { return "battery.100percent.bolt" }
        switch percentage {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }
}
