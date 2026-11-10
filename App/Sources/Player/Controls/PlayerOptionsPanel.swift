import SwiftUI
import AniworldKit

/// Language and hoster selection plus the intro/outro editor.
struct PlayerOptionsPanel: View {
    let vm: PlayerViewModel
    let onClose: () -> Void
    let onOpen: (PlayerPanel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlayerPanelHeader(title: "Optionen", subtitle: nil, onClose: onClose)
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
                    if vm.availableLanguages.isEmpty && vm.availableHosters.isEmpty {
                        sectionTitle("Sprache & Hoster")
                        Text("Für diese Folge gibt es keine Auswahl, z. B. weil sie als Download offline läuft.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sectionTitle("Intro & Outro")
                    Button {
                        onOpen(.introEditor)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "scissors")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text("Intro & Outro bearbeiten")
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.surfaceHigh.opacity(0.6))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
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
