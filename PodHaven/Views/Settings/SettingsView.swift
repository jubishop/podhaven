// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.userSettings) private var userSettings

  @State private var showShrinkPlaybarOnScrollPopOver = false

  private let viewModel = SettingsViewModel()

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.settings) {
      GeometryReader { geometry in
        Form {
          Section("Appearance") {
            HStack {
              Toggle("Shrink Playbar", isOn: $userSettings.shrinkPlayBarOnScroll)
              AppIcon.aboutInfo
                .imageButton {
                  showShrinkPlaybarOnScrollPopOver.toggle()
                }
                .popover(isPresented: $showShrinkPlaybarOnScrollPopOver) {
                  Text(
                    """
                    When enabled, \
                    the Playbar will automatically shrink when you scroll down, \
                    giving you more screen space to view content.  \
                    Scroll back up to reveal them again.
                    """
                  )
                  .frame(idealWidth: geometry.size.width * 0.7)
                  .multilineTextAlignment(.leading)
                  .padding()
                  .presentationCompactAdaptation(.popover)
                }
            }
          }

          Section("Importing / Exporting") {
            NavigationLink(
              value: Navigation.Destination.settingsSection(.opml),
              label: { Text("OPML") }
            )
          }

          if AppInfo.environment != .appStore {
            DebugSection()
          }
        }
        .navigationTitle("Settings")
      }
    }
  }
}

#if DEBUG
#Preview {
  SettingsView()
    .preview()
}
#endif
