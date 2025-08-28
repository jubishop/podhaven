// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    // Test setup  
    let sharedDB = AppDB.inMemory()
    appDB.context(.test) { sharedDB }.scope(.cached)
    backgroundAppDB.context(.test) { sharedDB }.scope(.cached)
    repo.context(.test) { FakeRepo(self.makeRepo()) }.scope(.cached)
    backgroundRepo.context(.test) { FakeRepo(self.makeBackgroundRepo()) }.scope(.cached)
    queue.context(.test) { FakeQueue(self.makeQueue()) }.scope(.cached)
    searchServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    feedManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    shareServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    cacheManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    podcastOPMLSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    notifications.context(.test) {
      { name in self.notifier().stream(for: name) }
    }
    commandCenter.context(.test) { FakeCommandCenter() }.scope(.cached)
    mpNowPlayingInfoCenter.context(.test) { FakeMPNowPlayingInfoCenter() }.scope(.cached)
    avPlayer.context(.test) { @MainActor in FakeAVPlayer() }.scope(.cached)
    loadEpisodeAsset.context(.test) { self.fakeEpisodeAssetLoader().loadEpisodeAsset }
    configureAudioSession.context(.test) {
      {
        Task { try await self.fakeAudioSession().configure() }
      }
    }
    setAudioSessionActive.context(.test) {
      { active in
        Task { try await self.fakeAudioSession().setActive(active) }
      }
    }
    imageFetcher.context(.test) { FakeImageFetcher() }.scope(.cached)
    sleeper.context(.test) { FakeSleeper() }.scope(.cached)
    podFileManager.context(.test) { FakeFileManager() }.scope(.cached)
  }
}
