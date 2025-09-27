// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct MainTabView: View {
  @InjectedObservable(\.navigation) private var navigation

  @Binding var tabContentSafeAreaInset: CGFloat

  init(tabContentSafeAreaInset: Binding<CGFloat>) {
    _tabContentSafeAreaInset = tabContentSafeAreaInset
  }

  var body: some View {

  }

  @ViewBuilder
  private func tabContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.safeAreaInsets.bottom
      } action: { newInset in
        guard newInset > 0 else { return }
        tabContentSafeAreaInset = newInset
      }
  }
}
