// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

private let supportsHostedAccessibilityInspection = ProcessInfo.processInfo.isiOSAppOnMac

@Suite("of accessibility semantics tests", .container)
@MainActor struct AccessibilitySemanticsTests {
  private static func makeWindow<V: View>(_ rootView: V) throws -> UIWindow {
    let host = UIHostingController(rootView: rootView)
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return window
  }

  private static func accessibilityElements(in root: NSObject) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []

    func collect(from object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }

      var result = object.isAccessibilityElement ? [object] : []
      if let view = object as? UIView {
        result.append(contentsOf: view.subviews.flatMap { collect(from: $0) })
      }

      let count = object.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        for index in 0..<count {
          if let child = object.accessibilityElement(at: index) as? NSObject {
            result.append(contentsOf: collect(from: child))
          }
        }
      }

      return result
    }

    return collect(from: root)
  }

  @Test(
    "playback progress is adjustable",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func playbackProgressIsAdjustable() throws {
    let window = try Self.makeWindow(PlayBarSheet(viewModel: PlayBarViewModel()))
    defer { window.isHidden = true }

    let progress = Self.accessibilityElements(in: window)
      .first {
        $0.accessibilityLabel == "Playback Position"
      }

    #expect(progress?.accessibilityTraits.contains(.adjustable) == true)
  }

  @Test(
    "current Up Next episode is a button",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func currentUpNextEpisodeIsAButton() async throws {
    let title = "Accessible Current Episode"
    let episode = try await Create.podcastEpisode(try Create.unsavedEpisode(title: title))
    Container.shared.userSettings().$showNowPlayingInUpNext.new(true)
    Container.shared.sharedState().$onDeck.new(OnDeck(from: episode))

    let window = try Self.makeWindow(UpNextView(viewModel: UpNextViewModel()))
    defer { window.isHidden = true }

    let currentEpisodeControl = Self.accessibilityElements(in: window)
      .first {
        $0.accessibilityLabel?.contains(title) == true && $0.accessibilityTraits.contains(.button)
      }

    #expect(currentEpisodeControl != nil)
  }

  @Test(
    "artwork overlays hide covered detail content",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func artworkOverlaysHideCoveredDetailContent() async throws {
    let podcast = try Create.unsavedPodcast(title: "Accessible Podcast")
    let episode = try Create.unsavedEpisode(title: "Accessible Episode")
    let podcastEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: podcast,
      unsavedEpisode: episode
    )

    try await verifyArtworkOverlay(
      EpisodeDetailView(
        viewModel: EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
      ),
      triggerLabel: "Show Episode Artwork",
      overlayLabels: ["Episode Artwork", "Image unavailable"]
    )
    try await verifyArtworkOverlay(
      PodcastDetailView(
        viewModel: PodcastDetailViewModel(podcast: DisplayedPodcast(podcast))
      ),
      triggerLabel: "Show Podcast Artwork",
      overlayLabels: ["Podcast Artwork", "Image unavailable"]
    )
  }

  private func verifyArtworkOverlay<V: View>(
    _ rootView: V,
    triggerLabel: String,
    overlayLabels: Set<String>
  ) async throws {
    let window = try Self.makeWindow(rootView)
    defer { window.isHidden = true }

    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains {
            $0.accessibilityLabel == triggerLabel
          }
      },
      { @MainActor in "Artwork trigger did not enter the accessibility tree" }
    )
    let trigger = try #require(
      Self.accessibilityElements(in: window).first { $0.accessibilityLabel == triggerLabel }
    )
    #expect(trigger.accessibilityActivate())

    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        let elements = Self.accessibilityElements(in: window)
        return elements.contains { overlayLabels.contains($0.accessibilityLabel ?? "") }
          && !elements.contains { $0.accessibilityLabel == triggerLabel }
      },
      { @MainActor in "Artwork overlay did not isolate the covered detail content" }
    )
  }

  @Test("seek actions include their configured interval")
  func seekActionsIncludeTheirConfiguredInterval() {
    #expect(AppIcon.seekBackward(30).text == "Seek Backward 30 Seconds")
    #expect(AppIcon.seekForward(45).text == "Seek Forward 45 Seconds")
  }

  @Test("selection controls describe the action they perform")
  func selectionControlsDescribeTheirAction() {
    #expect(AppIcon.selectionEmpty.text == "Select")
    #expect(AppIcon.selectionFilled.text == "Deselect")
  }

  @Test("playback status icons announce their actual state")
  func playbackStatusIconsAnnounceTheirActualState() {
    #expect(PlaybackStatus.playing.statusIconAccessibilityLabel == "Playing")
    #expect(PlaybackStatus.waiting.statusIconAccessibilityLabel == "Waiting to Play")
    #expect(PlaybackStatus.paused.statusIconAccessibilityLabel == "Paused")
    #expect(PlaybackStatus.loading("Episode").statusIconAccessibilityLabel == "Loading")
    #expect(PlaybackStatus.stopped.statusIconAccessibilityLabel == "Stopped")
  }

  @Test("transcription toolbar distinguishes actions and states")
  func transcriptionToolbarDistinguishesActionsAndStates() {
    #expect(TranscriptionStatus.none.toolbarAccessibilityLabel == "Transcribe")
    #expect(TranscriptionStatus.none.toolbarAccessibilityValue == "")
    #expect(TranscriptionStatus.queued.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.queued.toolbarAccessibilityValue == "Queued")
    #expect(TranscriptionStatus.transcribing(0.5).toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.transcribing(0.5).toolbarAccessibilityValue == "Transcribing")
    #expect(TranscriptionStatus.transcribed.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.transcribed.toolbarAccessibilityValue == "Complete")
    #expect(TranscriptionStatus.failed.toolbarAccessibilityLabel == "Retry Transcription")
    #expect(TranscriptionStatus.failed.toolbarAccessibilityValue == "Failed")
  }
}
