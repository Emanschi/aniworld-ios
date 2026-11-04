import SwiftUI
import AniworldKit

/// Language and hoster selection.
struct PlayerOptionsPanel: View {
    let vm: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlayerPanelHeader(title: "Sprache & Hoster", subtitle: nil, onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !vm.availableLanguages.isEmpty {
                        sectionTitle("Sprache")
                        ForEach(vm.availableLanguages, id: \.self) { language in
                            PlayerChoiceRow(
                                title: language.displayName,
                                selected: language == vm.currentLanguage
                            ) {
                                vm.switchLanguage(language)
                                onClose()
                            }
                        }
                    }
                    if !vm.availableHosters.isEmpty {
                        sectionTitle("Hoster")
                        ForEach(vm.availableHosters, id: \.self) { name in
                            PlayerChoiceRow(
                                title: name,
                                selected: name == vm.currentHoster
                            ) {
                                vm.switchHoster(name)
                                onClose()
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }
}
