// Copyright Justin Bishop, 2026

import Accessibility
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

  private static func accessibilityCustomContent(in object: NSObject) -> [AXCustomContent] {
    let selector = NSSelectorFromString("accessibilityCustomContent")
    guard object.responds(to: selector) else { return [] }
    return object.value(forKey: "accessibilityCustomContent") as? [AXCustomContent] ?? []
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
    "feedback photo picker is an announced button",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func feedbackPhotoPickerIsAnAnnouncedButton() throws {
    let window = try Self.makeWindow(
      NavigationStack {
        FeedbackFormView()
      }
    )
    defer { window.isHidden = true }

    let photoPicker = Self.accessibilityElements(in: window)
      .first {
        $0.accessibilityLabel == "Attach Photos"
      }

    #expect(photoPicker?.accessibilityTraits.contains(.button) == true)
  }

  @Test(
    "Settings overflow menu announces More Actions",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func settingsOverflowMenuAnnouncesMoreActions() throws {
    let window = try Self.makeWindow(SettingsView())
    defer { window.isHidden = true }

    let menu = Self.accessibilityElements(in: window)
      .first {
        $0.accessibilityLabel == "More Actions"
      }

    #expect(menu?.accessibilityTraits.contains(.button) == true)
  }

  @Test(
    "transcription queue capacity is adjustable and announces its value",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptionQueueCapacityIsAdjustable() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let window = try Self.makeWindow(SettingsView())
    defer { window.isHidden = true }

    let slider = Self.accessibilityElements(in: window)
      .first {
        $0.accessibilityLabel == "Maximum Transcription Queue Length"
      }

    #expect(slider?.accessibilityTraits.contains(.adjustable) == true)
    #expect(slider?.accessibilityValue == "50 episodes")
  }

  @Test(
    "queued transcription exposes a pause button",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func queuedTranscriptionExposesPauseButton() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let episode = try await Create.podcastEpisode()
    try await Container.shared.transcriptionQueue().enqueue(episode.id)
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(episode))

    let window = try Self.makeWindow(
      NavigationStack {
        EpisodeDetailView(viewModel: viewModel)
      }
    )
    defer { window.isHidden = true }

    let pauseButton = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Pause Transcription" }
    )
    #expect(pauseButton.accessibilityTraits.contains(.button))
  }

  @Test(
    "transcription queue announces live progress",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptionQueueAnnouncesLiveProgress() async throws {
    let title = "Accessible Transcription"
    let episode = try await Create.podcastEpisode(try Create.unsavedEpisode(title: title))
    let queue = Container.shared.transcriptionQueue()
    try await queue.enqueue(episode.id)
    queue.setProgress(0.42, for: episode.id)

    let window = try Self.makeWindow(
      NavigationStack {
        TranscriptionQueueView()
      }
    )
    defer { window.isHidden = true }

    try await Wait.until(
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel?.contains(title) == true }
      },
      { @MainActor in "Transcription queue row did not enter the accessibility tree" }
    )

    let row = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel?.contains(title) == true }
    )
    #expect(row.accessibilityValue == "Transcribing, 42 percent")
  }

  @Test(
    "transcription queue exposes row actions",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptionQueueExposesRowActions() async throws {
    let titles = ["First Queue Action", "Middle Queue Action", "Last Queue Action"]
    let queue = Container.shared.transcriptionQueue()
    for title in titles {
      let episode = try await Create.podcastEpisode(try Create.unsavedEpisode(title: title))
      try await queue.enqueue(episode.id)
    }

    let window = try Self.makeWindow(
      NavigationStack {
        TranscriptionQueueView()
      }
    )
    defer { window.isHidden = true }

    try await Wait.until(
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel?.contains(titles[1]) == true }
      },
      { @MainActor in "Middle transcription queue row did not enter the accessibility tree" }
    )

    let row = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel?.contains(titles[1]) == true }
    )
    let actions = Set(row.accessibilityCustomActions?.map(\.name) ?? [])
    #expect(actions == ["Move to Top", "Move to Bottom", "Remove from Queue"])
  }

  @Test(
    "transcription queue Edit button activates selection controls",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptionQueueEditButtonActivatesSelectionControls() async throws {
    let episode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Editable Transcription")
    )
    try await Container.shared.transcriptionQueue().enqueue(episode.id)

    let window = try Self.makeWindow(
      NavigationStack {
        TranscriptionQueueView()
      }
    )
    defer { window.isHidden = true }

    try await Wait.until(
      maxAttempts: 200,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        let labels = Set(
          Self.accessibilityElements(in: window).compactMap(\.accessibilityLabel)
        )
        return labels.contains { $0.contains("Editable Transcription") }
          && labels.contains("Edit")
      },
      { @MainActor in "Transcription queue and Edit button did not finish loading" }
    )

    let editButton = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Edit" }
    )
    #expect(editButton.accessibilityActivate())

    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        let labels = Set(
          Self.accessibilityElements(in: window).compactMap(\.accessibilityLabel)
        )
        return labels.contains("Select All") && labels.contains("0 episodes selected")
      },
      { @MainActor in "Edit did not expose transcription queue selection controls" }
    )
  }

  @Test(
    "Smart List rows announce episodes added during the open session as new",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func smartListRowsAnnounceNewEpisodes() async throws {
    let repo = Container.shared.repo()
    let pubDate = Date(timeIntervalSince1970: 1_700_000_000)
    let oldTitle = "Already Seen Episode"
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(title: oldTitle, pubDate: pubDate)]
      )
    )
    let smartList = try await Container.shared.smartListRepo()
      .insert(
        try UnsavedSmartList(
          title: "Accessible New Episodes",
          filter: SmartListFilter(),
          displayOrder: 0
        )
      )
    let window = try Self.makeWindow(
      NavigationStack {
        EpisodesListView(viewModel: EpisodesListViewModel(smartList: smartList))
      }
    )
    defer { window.isHidden = true }

    try await Wait.until(
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel?.contains(oldTitle) == true }
      },
      { @MainActor in "Already-seen episode did not enter the accessibility tree" }
    )

    let newTitle = "Arrived While Viewing"
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(title: newTitle, pubDate: pubDate)]
      )
    )

    try await Wait.until(
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel?.contains(newTitle) == true }
      },
      { @MainActor in "New episode did not enter the accessibility tree" }
    )

    let rows = Self.accessibilityElements(in: window)
    let oldRow = try #require(rows.first { $0.accessibilityLabel?.contains(oldTitle) == true })
    let newRow = try #require(rows.first { $0.accessibilityLabel?.contains(newTitle) == true })
    let oldValue = try #require(oldRow.accessibilityValue)
    let newValue = try #require(newRow.accessibilityValue)
    #expect(newValue == oldValue)

    let oldStatuses = Self.accessibilityCustomContent(in: oldRow)
      .filter { $0.label == "Status" }
    let newStatuses = Self.accessibilityCustomContent(in: newRow)
      .filter { $0.label == "Status" }
    #expect(oldStatuses.isEmpty)
    let newStatus = try #require(newStatuses.first)
    #expect(newStatus.value == "New")
    #expect(newStatus.importance == .high)
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
    #expect(AppIcon.pauseTranscription.text == "Pause Transcription")
    #expect(AppIcon.resumeTranscription.text == "Resume Transcription")
    #expect(AppIcon.discardTranscriptionProgress.text == "Discard Progress")
    #expect(TranscriptionStatus.none.toolbarAccessibilityLabel == "Transcribe")
    #expect(TranscriptionStatus.none.toolbarAccessibilityValue == "")
    let queued = TranscriptionStatus.queued(position: 1, total: 2)
    #expect(queued.toolbarAccessibilityLabel == "Pause Transcription")
    #expect(queued.toolbarAccessibilityValue == "Queued")
    #expect(
      TranscriptionStatus.transcribing(0.5).toolbarAccessibilityLabel == "Pause Transcription"
    )
    #expect(TranscriptionStatus.transcribing(0.5).toolbarAccessibilityValue == "Transcribing")
    #expect(TranscriptionStatus.paused(0.5).toolbarAccessibilityLabel == "Resume Transcription")
    #expect(TranscriptionStatus.paused(0.5).toolbarAccessibilityValue == "Paused")
    #expect(TranscriptionStatus.pausing.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.pausing.toolbarAccessibilityValue == "Pausing")
    #expect(TranscriptionStatus.discarding.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.discarding.toolbarAccessibilityValue == "Discarding Progress")
    #expect(TranscriptionStatus.transcribed.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.transcribed.toolbarAccessibilityValue == "Complete")
    #expect(TranscriptionStatus.failed.toolbarAccessibilityLabel == "Retry Transcription")
    #expect(TranscriptionStatus.failed.toolbarAccessibilityValue == "Failed")
  }
}
