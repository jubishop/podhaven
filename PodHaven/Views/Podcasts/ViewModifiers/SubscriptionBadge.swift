// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - SubscriptionBadge

struct SubscriptionBadge: ViewModifier {
  let subscribed: Bool
  let badgeSize: CGFloat

  func body(content: Content) -> some View {
    if subscribed {
      content
        .overlay(alignment: .bottomLeading) {
          AppIcon.subscribed.image
            .font(.system(size: badgeSize, weight: .semibold))
            .padding(badgeSize / 4)
            .background(.ultraThinMaterial, in: Circle())
        }
    } else {
      content
    }
  }
}

// MARK: - View Extension

extension View {
  func subscriptionBadge(
    subscribed: Bool,
    badgeSize: CGFloat
  ) -> some View {
    modifier(SubscriptionBadge(subscribed: subscribed, badgeSize: badgeSize))
  }
}
