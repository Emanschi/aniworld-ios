import SwiftUI

/// First-launch sheet that explains iCloud Drive sync and starts the folder picker.
struct SyncOnboardingView: View {
    @Environment(LibrarySyncService.self) private var sync
    @State private var showPicker = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Spacer(minLength: 12)
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accentGradient)
                Text("Geräte synchronisieren")
                    .font(AppFont.display(28))
                    .multilineTextAlignment(.center)
                Text("Favoriten, Weiterschauen-Verlauf und Fortschritt können über iCloud Drive zwischen deinen Geräten abgeglichen werden. Die Daten liegen in einem versteckten Ordner in deinem eigenen iCloud Drive.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "1.circle.fill").foregroundStyle(Theme.accent)
                    Text("Wähle im nächsten Schritt „iCloud Drive“ und tippe auf „Öffnen“.")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))

                Spacer(minLength: 12)

                Button {
                    showPicker = true
                } label: {
                    Text("iCloud Drive wählen").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle())

                Button("Später") { sync.skipOnboarding() }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 24)
        }
        .sheet(isPresented: $showPicker) {
            FolderPicker(onPick: { url in
                showPicker = false
                sync.configure(pickedFolder: url)
            }, onCancel: {
                showPicker = false
            })
            .ignoresSafeArea()
        }
    }
}

#Preview("Sync-Onboarding") {
    SyncOnboardingView().previewEnvironment()
}
