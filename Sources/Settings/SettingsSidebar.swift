import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            item(.general)
            sectionGroup("Notifications", sections: SettingsSection.notifications)
            sectionGroup("Live Activities", sections: [.nowPlaying])
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 54)
        .padding(.bottom, 16)
        .frame(width: 237)
        .background(.black.opacity(0.10))
    }

    private func sectionGroup(_ title: String, sections: [SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SettingsGroupHeading(title: title)
            VStack(spacing: 0) {
                ForEach(sections) { item($0) }
            }
        }
    }

    private func item(_ section: SettingsSection) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                SettingsSectionIcon(section: section)
                Text(section.rawValue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(selection == section ? SettingsPalette.selection : .clear, in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }
}
