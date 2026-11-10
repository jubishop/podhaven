// Copyright Justin Bishop, 2026

import SwiftUI

extension Alert {
  func confirmPodcastDeletion(titles: [String], delete: @MainActor @escaping () -> Void) {
    let message: String =
      if titles.count == 1, let title = titles.first {
        "Are you sure you want to delete \"\(title)\"?"
      } else {
        "Are you sure you want to delete \(titles.count) podcasts?"
      }

    self(title: titles.count == 1 ? "Delete Podcast?" : "Delete Podcasts?", message) {
      Button("Delete", role: .destructive, action: delete)
      Button("Cancel", role: .cancel) {}
    }
  }
}
