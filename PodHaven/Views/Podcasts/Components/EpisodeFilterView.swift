// Copyright Justin Bishop, 2025

import SwiftUI

enum EpisodeFilterMethod: String, CaseIterable {
  case all = "All Episodes"
  case unstarted = "Unstarted"
  case unfinished = "Unfinished"
  case unqueued = "Unqueued"

  func filterMethod<T: EpisodeFilterable>(for type: T.Type) -> (T) -> Bool {
    switch self {
    case .all:
      return { _ in true }
    case .unstarted:
      return { !$0.started }
    case .unfinished:
      return { !$0.completed }
    case .unqueued:
      return { !$0.queued }
    }
  }
}

struct EpisodeFilterView: View {
  @Binding var entryFilter: String
  @Binding var currentFilterMethod: EpisodeFilterMethod

  var body: some View {
    VStack(spacing: 8) {
      Divider()

      HStack {
        SearchBar(
          text: $entryFilter,
          placeholder: "Filter episodes",
          imageName: "line.horizontal.3.decrease.circle"
        )

        Menu(
          content: {
            ForEach(EpisodeFilterMethod.allCases, id: \.self) { filterMethod in
              Button(filterMethod.rawValue) {
                currentFilterMethod = filterMethod
              }
              .disabled(currentFilterMethod == filterMethod)
            }
          },
          label: {
            Image(systemName: "line.horizontal.3.decrease.circle")
          }
        )
      }

      Divider()
    }
  }
}
