// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests", .container)
struct PodcastFeedTests {
  @DynamicInjected(\.repo) private var repo

  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Pod Save America")
    #expect(unsavedPodcast.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast.image.absoluteString.contains("simplecastcdn"))
    let unsavedEpisode = feed.toUnsavedEpisodes().first!
    #expect(unsavedEpisode.duration == CMTime.seconds(2643))
  }

  @Test("parsing the Marketplace feed with an invalid MediaURL")
  func parseMarketplaceFeedWithInvalidMediaURL() async throws {
    let data = PreviewBundle.loadAsset(named: "marketplace", in: .FeedRSS)
    let feed = try await PodcastFeed.parse(data, from: FeedURL(URL.valid()))
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = feed.toUnsavedEpisodes()
    #expect(unsavedPodcast.title == "Marketplace")
    #expect(unsavedPodcast.subscribed == false)

    // title: "What will a GOP-ruled Congress do with Trump" is removed for invalid MediaURL
    #expect(unsavedEpisodes.count == 49)
    #expect(unsavedEpisodes.first!.title == "Happy New Year! The cold weather could cost you.")
    #expect(unsavedEpisodes.last!.title == "What’s better, a pension or a 401(k)?")
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "land_of_the_giants", in: .FeedRSS)
    let fakeURL = FeedURL(URL.valid())
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = feed.toUnsavedEpisodes()
    #expect(unsavedPodcast.title == "Land of the Giants")
    #expect(unsavedPodcast.subscribed == false)
    #expect(unsavedEpisodes.count == 71)
    #expect(unsavedEpisodes.first!.title == "Disney is a Tech Company?")
    #expect(unsavedEpisodes.last!.title == "The Rise of Amazon")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "game_informer_invalid", in: .FeedRSS)
    let fakeURL = FeedURL(URL.valid())
    await #expect {
      try await PodcastFeed.parse(data, from: fakeURL)
    } throws: { error in
      guard let error = error as? FeedError
      else { return false }

      if case .parseFailure(let thrownURL, _) = error {
        return thrownURL.rawValue == fakeURL.rawValue
      }

      return false
    }
  }

  // This is invalid behavior by a feed but sadly dumb dumbs still do it.
  @Test("parsing the seattle official feed with duplicate guids")
  func parseSeattleOfficialFeedWithDuplicateGuids() async throws {
    let data = PreviewBundle.loadAsset(named: "seattle_official", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let episodes = feed.toUnsavedEpisodes()
    let duplicatedEpisode = episodes.first(where: {
      $0.guid == GUID("178f32e0-7246-11ec-b14e-19521896ea35")
    })!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2024)
  }

  @Test("parsing the morningbrew feed with duplicate mediaURLs")
  func parseMorningBrewFeedWithDuplicateMediaURLs() async throws {
    let data = PreviewBundle.loadAsset(named: "morningbrew", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    let episodes = feed.toUnsavedEpisodes()
    let mediaURLs: [MediaURL: Int] = episodes.reduce(into: [:]) { counts, episode in
      counts[episode.mediaURL, default: 0] += 1
    }
    for (mediaURL, count) in mediaURLs where count > 1 {
      Issue.record("Duplicate media url found: \(mediaURL) with count: \(count)")
    }

    let episodesByMediaURL = IdentifiedArray(uniqueElements: episodes, id: \.mediaURL)
    let duplicatedEpisode = episodesByMediaURL[
      id: MediaURL(
        URL(
          string:
            "https://www.podtrac.com/pts/redirect.mp3/pdst.fm/e/tracking.swap.fm/track/bHsDpvy53mYwJpnc1UL5/traffic.megaphone.fm/MOBI2606610581.mp3?updated=1750937895"
        )!
      )
    ]!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2026)
  }

  @Test("parsing the seattlenow feed with a <p> tagged description")
  func parseSeattleNowFeedWithPTagInDescription() async throws {
    let data = PreviewBundle.loadAsset(named: "seattlenow", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(
      unsavedPodcast.description
        == "<p>A daily news podcast for a curious city. Seattle Now brings you quick, informal, and hyper-local news updates every weekday.</p>"
    )
  }

  @Test("parsing the makingsense feed with items missing media urls")
  func parseMakingSenseFeedWithMissingMediaUrls() async throws {
    let data = PreviewBundle.loadAsset(named: "makingsense", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let episodes = feed.toUnsavedEpisodes()

    // 19 episodes exist in the RSS file,
    // but the last two are dropped because they have no media URLs
    #expect(episodes.count == 17)
  }

  @Test("parsing the considerthis feed with items missing guids")
  func parseConsiderThisFeedWithMissingGuids() async throws {
    let data = PreviewBundle.loadAsset(named: "considerthis", in: .FeedRSS)
    let feed = try await PodcastFeed.parse(data, from: FeedURL(URL.valid()))
    let episodes = feed.toUnsavedEpisodes()

    // These are the mediaURLs of the two entries with no guids
    #expect(
      episodes.contains(where: {
        $0.guid
          == GUID(
            "https://chrt.fm/track/138C95/prfx.byspotify.com/e/play.podtrac.com/npr-510355/traffic.megaphone.fm/NPR8510690925.mp3?d=736&size=11791509&e=1254697878&t=podcast&p=510355"
          )
      }
      )
    )
    #expect(
      episodes.contains(where: {
        $0.guid
          == GUID(
            "https://chrt.fm/track/138C95/prfx.byspotify.com/e/play.podtrac.com/npr-510355/traffic.megaphone.fm/NPR7873235626.mp3?d=489&size=7834271&e=1254264642&t=podcast&p=510355"
          )
      }
      )
    )
  }

  @Test("parsing with invalid feedURL throws error")
  func parseWithInvalidFeedURL() async throws {
    let url = URL(string: "file://invalid.url")!

    await #expect(throws: FeedError.self) {
      try await PodcastFeed.parse(FeedURL(url))
    }
  }

  @Test("parsing the jon_stewart feed with content:encoded priority")
  func parseJonStewartFeedWithContentEncodedPriority() async throws {
    let data = PreviewBundle.loadAsset(named: "jon_stewart", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://feeds.megaphone.fm/BVLLC2163264914")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisode = feed.toUnsavedEpisodes().first!

    #expect(unsavedPodcast.title == "The Weekly Show with Jon Stewart")

    // Podcast description should use content:encoded (has HTML)
    #expect(unsavedPodcast.description.contains("<p>On Mondays"))

    // Episode description should use content:encoded (has HTML)
    #expect(unsavedEpisode.description!.contains("<p>As the Pentagon"))

    // Verify HTML formatting is preserved from content:encoded
    #expect(unsavedEpisode.description!.contains("<strong>"))
  }

  @Test("parsing and inserting the twentyminutevc feed via repo")
  func parseTwentyMinuteVCFeedAndInsert() async throws {
    let data = PreviewBundle.loadAsset(named: "twentyminutevc", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://thetwentyminutevc.libsyn.com/rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = feed.toUnsavedEpisodes()

    #expect(
      unsavedPodcast.title
        == "The Twenty Minute VC (20VC): Venture Capital | Startup Funding | The Pitch"
    )
    #expect(unsavedEpisodes.count > 0)

    // Test inserting via repo
    // This feed has duplicate MediaURLs so this is ensuring those got deduped.
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: unsavedEpisodes
      )
    )

    #expect(podcastSeries.podcast.title == unsavedPodcast.title)
    #expect(podcastSeries.episodes.count == unsavedEpisodes.count)
  }
}
