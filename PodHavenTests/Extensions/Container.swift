// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    appDB.context(.test) { AppDB.inMemory() }.scope(.cached)
    repo.context(.test) { FakeRepo(Repo.initForTest(self.appDB())) }.scope(.cached)
    searchServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    feedManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    notifications.context(.test) {
      { name in self.notifier().stream(for: name) }
    }
    commandCenter.context(.test) { FakeCommandCenter() }.scope(.cached)
    mpNowPlayingInfoCenter.context(.test) { FakeMPNowPlayingInfoCenter() }.scope(.cached)
    avQueuePlayer.context(.test) { @MainActor in FakeAVQueuePlayer() }.scope(.cached)
    loadEpisodeAsset.context(.test) { self.fakeEpisodeAssetLoader().loadEpisodeAsset }
    imageFetcher.context(.test) { FakeImageFetcher() }.scope(.cached)
  }
}
