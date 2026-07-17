// Copyright Justin Bishop, 2025

import SwiftUI

struct AppIconImage: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  let icon: AppIcon

  var body: some View {
    icon.rawImage
      .foregroundStyle(icon.color(for: colorScheme))
      .opacity(isEnabled ? 1 : 0.4)
  }
}

struct AppIconLabel: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  let icon: AppIcon
  let textKey: LocalizedStringKey

  init(icon: AppIcon) {
    self.icon = icon
    self.textKey = icon.textKey
  }

  init(icon: AppIcon, textKey: LocalizedStringKey) {
    self.icon = icon
    self.textKey = textKey
  }

  var body: some View {
    Label {
      Text(textKey)
    } icon: {
      icon.rawImage
        .foregroundStyle(icon.color(for: colorScheme))
    }
    .opacity(isEnabled ? 1 : 0.4)
  }
}

struct AppIconLabelButton: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  let icon: AppIcon
  let textKey: LocalizedStringKey
  let action: () -> Void

  init(icon: AppIcon, action: @escaping () -> Void) {
    self.icon = icon
    self.textKey = icon.textKey
    self.action = action
  }

  init(icon: AppIcon, textKey: LocalizedStringKey, action: @escaping () -> Void) {
    self.icon = icon
    self.textKey = textKey
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      AppIconLabel(icon: icon, textKey: textKey)
    }
    .tint(icon.color(for: colorScheme))
    .opacity(isEnabled ? 1 : 0.4)
  }
}

struct AppIconImageButton: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  let icon: AppIcon
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      AppIconImage(icon: icon)
    }
    .accessibilityLabel(Text(icon.textKey))
    .tint(icon.color(for: colorScheme))
    .opacity(isEnabled ? 1 : 0.4)
  }
}
