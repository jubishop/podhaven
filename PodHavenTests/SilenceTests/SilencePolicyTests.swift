// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("Silence modes and speed scaling", .container)
struct SilencePolicyTests {
  @Test("all precedence combinations distinguish Off from inheritance")
  func precedence() {
    let choices: [SilenceMode?] = [nil] + SilenceMode.allCases.map { Optional($0) }
    for global in SilenceMode.allCases {
      for podcast in choices {
        for temporary in choices {
          #expect(
            SilenceMode.resolve(temporary: temporary, podcast: podcast, global: global)
              == (temporary ?? podcast ?? global)
          )
        }
      }
    }
  }

  @Test("global defaults to Off and persists a typed selection")
  func globalSetting() {
    let settings = Container.shared.userSettings()
    #expect(settings.silenceMode == .off)
    settings.$silenceMode.new(.balanced)
    Container.shared.userSettings.reset(.scope)
    #expect(Container.shared.userSettings().silenceMode == .balanced)
    #expect(PodcastSettings.defaults.silenceMode == nil)
  }

  @Test("podcast selection round trips and clearing restores inheritance")
  func podcastSetting() async throws {
    let episode = try await Create.podcastEpisode()
    let repo = Container.shared.repo()
    var settings = episode.podcast.settings
    for mode: SilenceMode? in [.gentle, .balanced, .aggressive, .off, nil] {
      settings.silenceMode = mode
      try await repo.updatePodcastSettings(episode.podcast.id, settings)
      let refreshed = try await repo.podcastEpisode(episode.id)
      #expect(refreshed?.podcast.silenceMode == mode)
    }
  }

  @Test("presets stay ordered and retain protection at every supported speed")
  func scaling() {
    for rate in stride(from: 0.8, through: 2.0, by: 0.1) {
      let policies = [SilenceMode.gentle, .balanced, .aggressive]
        .map {
          SilencePolicy(mode: $0, rate: rate)
        }
      #expect(policies[0].minimumGap > policies[1].minimumGap)
      #expect(policies[1].minimumGap > policies[2].minimumGap)
      #expect(policies[0].padding > policies[1].padding)
      #expect(policies[1].padding > policies[2].padding)
      for policy in policies {
        #expect(policy.padding >= 0.1)
        #expect(policy.cut(in: QuietInterval(start: 1, end: 4), from: 2) == 4 - policy.padding)
        #expect(policy.cut(in: QuietInterval(start: 1, end: 4), from: 3.95) == nil)
        #expect(policy.cut(in: QuietInterval(start: 1, end: 1.2), from: 1.1) == nil)
        #expect(policy.cut(in: QuietInterval(start: 1, end: 4), from: 0.9) == nil)
      }
    }
    let normal = SilencePolicy(mode: .gentle, rate: 1)
    let fast = SilencePolicy(mode: .gentle, rate: 2)
    #expect(abs(fast.minimumGap - normal.minimumGap / sqrt(2)) < 0.00001)
    #expect(abs(fast.padding - normal.padding / sqrt(2)) < 0.00001)
    #expect(
      SilencePolicy(mode: .off, rate: 2).cut(in: QuietInterval(start: 0, end: 10), from: 2) == nil
    )
  }
}
