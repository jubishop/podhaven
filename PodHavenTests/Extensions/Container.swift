// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    appDB.context(.test) { AppDB.inMemory() }.scope(.cached)
    repo.context(.test) { FakeRepo(self.makeRepo()) }.scope(.cached)
    queue.context(.test) { FakeQueue(self.makeQueue()) }.scope(.cached)

    cacheManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    iTunesServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    podcastFeedSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    podcastOPMLSession.context(.test) { FakeDataFetchable() }.scope(.cached)

    notifications.context(.test) {
      { name in self.notifier().stream(for: name) }
    }

    mpRemoteCommandCenter.context(.test) { FakeMPRemoteCommandCenter() }.scope(.cached)
    mpNowPlayingInfoCenter.context(.test) { FakeMPNowPlayingInfoCenter() }.scope(.cached)
    avPlayer.context(.test) { @MainActor in FakeAVPlayer() }.scope(.cached)
    loadEpisodeAsset.context(.test) { self.fakeEpisodeAssetLoader().loadEpisodeAsset }
    configureAudioSession.context(.test) {
      {
        let fake = Container.shared.fakeAudioSession()
        if let error = fake.configureError() {
          await Container.shared.alert()(
            title: "Couldn't start audio playback",
            ErrorKit.message(for: error)
          )
          return false
        }
        Task { try await fake.configure() }
        return true
      }
    }
    .scope(.cached)
    setAudioSessionActive.context(.test) {
      { active in
        Task { try await self.fakeAudioSession().setActive(active) }
      }
    }

    nlContextualEmbedding.context(.test) { FakeEmbeddable() }.scope(.cached)

    sleeper.context(.test) { FakeSleeper() }.scope(.cached)

    userNotificationCenter.context(.test) { FakeUserNotificationCenter() }.scope(.cached)

    fileManager.context(.test) { FakeFileManager() }.scope(.cached)

    controlCenter.context(.test) { FakeControlCenter() }.scope(.cached)

    widgetCenter.context(.test) { FakeWidgetCenter() }.scope(.cached)

    standardDefaults.context(.test) { FakeKeyValueStore() }.scope(.cached)
    sharedDefaults.context(.test) { FakeKeyValueStore() }.scope(.cached)

    uiApplication.context(.test) { @MainActor in FakeApplication() }.scope(.cached)

    bgTaskScheduler.context(.test) { FakeBGTaskScheduler() }.scope(.cached)

    // nil = inherit from parent, avoiding priority-based starvation in tests.
    taskPriority.context(.test) { { _ in nil } }

    imagePipeline.context(.test) {
      ImagePipeline(configuration: ImagePipeline.Configuration(dataLoader: self.fakeDataLoader()))
    }
    .scope(.cached)
  }
}
