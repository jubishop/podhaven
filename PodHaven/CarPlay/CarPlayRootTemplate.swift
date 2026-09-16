// Copyright Justin Bishop, 2026

import CarPlay
import SwiftUI

@MainActor
enum CarPlayRootTemplate {
  enum State {
    case ready
    case unavailable
  }

  enum Tab: String, CaseIterable {
    case upNext = "Up Next"
    case episodes = "Episodes"
    case podcasts = "Podcasts"

    var icon: AppIcon {
      switch self {
      case .upNext: .upNext
      case .episodes: .episodes
      case .podcasts: .podcasts
      }
    }

    var placeholder: String {
      switch self {
      case .upNext: "Your queue will appear here."
      case .episodes: "Your episodes will appear here."
      case .podcasts: "Your podcasts will appear here."
      }
    }
  }

  static func make(state: State, retry: @escaping @MainActor () -> Void) -> CPTabBarTemplate {
    let tabs = Tab.allCases.map { tab in
      let sections: [CPListSection]
      switch state {
      case .ready:
        sections = []
      case .unavailable:
        let item = CPListItem(text: "Retry", detailText: "Couldn't load CarPlay.")
        item.handler = { _, completion in
          completion()
          retry()
        }
        sections = [CPListSection(items: [item])]
      }
      let list = CPListTemplate(title: tab.rawValue, sections: sections)
      list.tabTitle = tab.rawValue
      list.tabImage = UIImage(systemName: tab.icon.systemImageName)
      list.emptyViewTitleVariants = [tab.rawValue]
      list.emptyViewSubtitleVariants = [tab.placeholder]
      return list
    }
    return CPTabBarTemplate(templates: tabs)
  }
}

#if DEBUG
private struct CarPlayTemplatePreview: View {
  let state: CarPlayRootTemplate.State

  var body: some View {
    TabView {
      ForEach(CarPlayRootTemplate.Tab.allCases, id: \.self) { tab in
        Group {
          switch state {
          case .ready:
            ContentUnavailableView {
              tab.icon.label
            } description: {
              Text(tab.placeholder)
            }
          case .unavailable:
            List {
              Button("Retry") {}
              Text("Couldn't load CarPlay.")
            }
          }
        }
        .tabItem { tab.icon.label(tab.rawValue) }
      }
    }
  }
}

#Preview("CarPlay placeholder content") {
  CarPlayTemplatePreview(state: .ready)
}

#Preview("CarPlay retry content") {
  CarPlayTemplatePreview(state: .unavailable)
}
#endif
