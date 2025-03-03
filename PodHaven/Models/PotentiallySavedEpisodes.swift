// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

class PotentiallySavedEpisodes {
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private var fetchAttempted: Set<MediaURL> = []
  private let unsavedEpisodes: IdentifiedArray<MediaURL, UnsavedEpisode>
  private var savedEpisodes: IdentifiedArray<MediaURL, Episode>

  // MARK: - Initialization

  init(unsavedEpisodes: IdentifiedArray<MediaURL, UnsavedEpisode>) {
    self.unsavedEpisodes = unsavedEpisodes
    self.savedEpisodes = IdentifiedArray(id: \.media)
  }
}
