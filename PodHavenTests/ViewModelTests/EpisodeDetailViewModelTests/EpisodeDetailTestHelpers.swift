// Copyright Justin Bishop, 2026

import Testing

@testable import PodHaven

enum EpisodeDetailTestHelpers {
  @MainActor
  static func appear(_ viewModel: EpisodeDetailViewModel) async throws {
    viewModel.appear()
    try await Wait.until(
      { @MainActor in viewModel.appearTask == nil },
      { @MainActor in
        """
        Expected appear to finish.
        appearTask: \(String(describing: viewModel.appearTask))
        """
      }
    )
  }
}
