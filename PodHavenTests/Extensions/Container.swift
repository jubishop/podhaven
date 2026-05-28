// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke

@testable import PodHaven

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    LogCapture.installOnce()

    appDB.context(.test) { AppDB.inMemory() }.scope(.cached)
    repo.context(.test) { FakeRepo(self.makeRepo()) }.scope(.cached)
    recommendationRepo.context(.test) {
      FakeRecommendationRepo(self.makeRecommendationRepo())
    }
    .scope(.cached)
    queue.context(.test) { FakeQueue(self.makeQueue()) }.scope(.cached)
    observatory.context(.test) { FakeObservatory(self.makeObservatory()) }.scope(.cached)

    cacheManagerSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    iTunesServiceSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    podcastFeedSession.context(.test) { FakeDataFetchable() }.scope(.cached)
    podcastOPMLSession.context(.test) { FakeDataFetchable() }.scope(.cached)

    notifications.context(.test) {
      { name in self.notifier().stream(for: name) }
    }

    mpRemoteCommandCenter.context(.test) { FakeMPRemoteCommandCenter() }.scope(.cached)
    mpNowPlayingInfoCenter.context(.test) { FakeMPNowPlayingInfoCenter() }.scope(.cached)
    // `avPlayer` is `@MainActor` in the production extension, so reading it
    // requires Main isolation. `autoRegister()` is a non-isolated protocol
    // requirement and runs on whichever actor first resolves any factory in
    // this container — under Swift Testing that's the cooperative pool, where
    // `MainActor.assumeIsolated` traps. Construct the registration directly
    // with the matching key (the production accessor uses `key: #function` =
    // `"avPlayer"`) so we don't touch the `@MainActor` accessor here. The
    // default closure is unreachable because xctest auto-activates `.test`.
    _ = Factory<any AVPlayable>(self, key: "avPlayer") {
      Assert.fatal("avPlayer default closure resolved in tests — .test override should always win")
    }
    .context(.test) {
      MainActor.assumeIsolated { FakeAVPlayer() }
    }
    .scope(.cached)
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

    continuousClockNow.context(.test) { { self.fakeContinuousClock().now } }
      .scope(.cached)

    userNotificationCenter.context(.test) { FakeUserNotificationCenter() }.scope(.cached)

    fileManager.context(.test) { FakeFileManager() }.scope(.cached)

    captureSentryFeedback.context(.test) { self.fakeSentryFeedbackCapture().capture }
      .scope(.cached)

    controlCenter.context(.test) { FakeControlCenter() }.scope(.cached)

    widgetCenter.context(.test) { FakeWidgetCenter() }.scope(.cached)

    standardDefaults.context(.test) { FakeKeyValueStore() }.scope(.cached)
    sharedDefaults.context(.test) { FakeKeyValueStore() }.scope(.cached)

    // Same reasoning as `avPlayer` above: `uiApplication` is `@MainActor` in
    // production. Match its `#function` key directly to register the `.test`
    // override without touching the `@MainActor` accessor.
    _ = Factory<any ApplicationProviding>(self, key: "uiApplication") {
      Assert.fatal(
        "uiApplication default closure resolved in tests — .test override should always win"
      )
    }
    .context(.test) { FakeApplication() }
    .scope(.cached)

    bgTaskScheduler.context(.test) { FakeBGTaskScheduler() }.scope(.cached)

    // nil = inherit from parent, avoiding priority-based starvation in tests.
    taskPriority.context(.test) { { _ in nil } }

    imagePipeline.context(.test) {
      ImagePipeline(configuration: ImagePipeline.Configuration(dataLoader: self.fakeDataLoader()))
    }
    .scope(.cached)
  }
}
