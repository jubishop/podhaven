// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    // Test setup
    appDB.context(.test) { AppDB.inMemory() }.scope(.cached)
    repo.context(.test) { FakeRepo(self.makeRepo()) }.scope(.cached)
    queue.context(.test) { FakeQueue(self.makeQueue()) }.scope(.cached)
    searchServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    feedManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    shareServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    cacheManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    podcastFeedSession.context(.preview) { FakeDataFetchable() }.scope(.cached)
    podcastOPMLSession.context(.preview) { FakeDataFetchable() }.scope(.cached)
    notifications.context(.test) {
      { name in self.notifier().stream(for: name) }
    }
    commandCenter.context(.test) { FakeCommandCenter() }.scope(.cached)
    mpNowPlayingInfoCenter.context(.test) { FakeMPNowPlayingInfoCenter() }.scope(.cached)
    avPlayer.context(.test) { @MainActor in FakeAVPlayer() }.scope(.cached)
    loadEpisodeAsset.context(.test) { self.fakeEpisodeAssetLoader().loadEpisodeAsset }
    imageFetcher.context(.test) { FakeImageFetcher() }.scope(.cached)
    sleeper.context(.test) { FakeSleeper() }.scope(.cached)
  }
}
