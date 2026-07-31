// Copyright Justin Bishop, 2026

import SwiftUI

struct StackedToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      configuration.label
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)

      Toggle(isOn: configuration.$isOn) {
        configuration.label
      }
      .labelsHidden()
      .toggleStyle(.switch)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension ToggleStyle where Self == StackedToggleStyle {
  static var stacked: StackedToggleStyle { StackedToggleStyle() }
}
