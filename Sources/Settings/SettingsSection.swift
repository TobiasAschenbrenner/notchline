import SwiftUI

enum SettingsSection: String, Identifiable {
    case general = "General"
    case battery = "Battery"
    case connectivity = "Connectivity"
    case focus = "Focus"
    case display = "Display"
    case sound = "Sound"
    case nowPlaying = "Now Playing"

    static let notifications: [Self] = [.battery, .connectivity, .focus, .display, .sound]

    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .battery: return "bolt.fill"
        case .connectivity: return "headphones"
        case .focus: return "moon.fill"
        case .display: return "sun.max.fill"
        case .sound: return "speaker.wave.2.fill"
        case .nowPlaying: return "play.fill"
        }
    }

    var iconColors: [Color] {
        switch self {
        case .general: return [Color(red: 0.67, green: 0.64, blue: 0.61), Color(red: 0.47, green: 0.44, blue: 0.42)]
        case .battery: return [Color(red: 1, green: 0.72, blue: 0.58), Color(red: 0.93, green: 0.54, blue: 0.38)]
        case .connectivity: return [Color(red: 0.35, green: 0.87, blue: 0.66), Color(red: 0.07, green: 0.68, blue: 0.50)]
        case .focus: return [Color(red: 0.58, green: 0.56, blue: 1), Color(red: 0.39, green: 0.37, blue: 0.90)]
        case .display: return [Color(red: 0.84, green: 0.49, blue: 0.95), Color(red: 0.64, green: 0.29, blue: 0.90)]
        case .sound: return [Color(red: 0.98, green: 0.42, blue: 0.96), Color(red: 0.80, green: 0.20, blue: 0.85)]
        case .nowPlaying: return [Color(red: 1, green: 0.45, blue: 0.56), Color(red: 0.93, green: 0.24, blue: 0.39)]
        }
    }
}

struct SettingsSectionIcon: View {
    let section: SettingsSection

    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(width: 23, height: 23)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: section.iconColors, startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                    }
            }
            .accessibilityHidden(true)
    }
}
