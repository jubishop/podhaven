// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

private let supportsHostedAccessibilityInspection = ProcessInfo.processInfo.isiOSAppOnMac

@Suite("of PlayBarSheet tests", .container)
@MainActor struct PlayBarSheetTests {
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

  @Test("transcribed episodes expand to a synchronized full-height transcript")
  func transcribedEpisodeOffersFullHeightDetent() async throws {
    let episode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Expandable Transcript")
    )
    let transcript = Transcript(
      segments: [
        TranscriptSegment(
          start: 0,
          end: 4,
          text: "Follow along",
          words: [
            TranscriptWord(start: 0, end: 2, text: "Follow"),
            TranscriptWord(start: 2, end: 4, text: " along"),
          ]
        )
      ],
      locale: "en-US",
      createdAt: Date()
    )
    try await Container.shared.repo()
      .updateTranscript(
        episode.id,
        transcript: transcript.jsonString()
      )
    let transcribedEpisode = try #require(
      try await Container.shared.repo().podcastEpisode(episode.id)
    )
    Container.shared.stateManager().setOnDeck(transcribedEpisode)
    Container.shared.stateManager().setCurrentTime(.seconds(3))

    let viewModel = PlayBarViewModel()
    let transcriptObservationTask = Task {
      await viewModel.observeTranscript()
    }
    defer { transcriptObservationTask.cancel() }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in viewModel.canExpandTranscript },
      { @MainActor in "Transcribed play bar never loaded its transcript" }
    )

    let window = try Self.makeWindow(PlayBarSheet(viewModel: viewModel))
    defer {
      window.isHidden = true
    }

    guard supportsHostedAccessibilityInspection else { return }
    let presentedView = try #require(window.rootViewController?.view)
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        Self.accessibilityElements(in: presentedView)
          .contains { $0.accessibilityLabel == "Show Transcript" }
      },
      { "Play bar never exposed the Show Transcript action" }
    )
    let showTranscriptButton = try #require(
      Self.accessibilityElements(in: presentedView)
        .first { $0.accessibilityLabel == "Show Transcript" }
    )
    #expect(showTranscriptButton.accessibilityActivate())
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        presentedView.setNeedsLayout()
        presentedView.layoutIfNeeded()
        return Self.accessibilityElements(in: presentedView)
          .contains { $0.accessibilityLabel == "Follow along" }
      },
      { "Expanded play bar never exposed its transcript segment" }
    )
    let transcriptSegment = try #require(
      Self.accessibilityElements(in: presentedView)
        .first { $0.accessibilityLabel == "Follow along" }
    )
    #expect(transcriptSegment.accessibilityValue == "Current word along")
  }

  @Test(
    "transcription action mirrors the episode toolbar",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptionActionMirrorsEpisodeToolbar() async throws {
    let episode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Play Bar Transcription")
    )
    Container.shared.transcriptionAvailability().$state.new(.available)
    Container.shared.stateManager().setOnDeck(episode)

    let window = try Self.makeWindow(PlayBarSheet(viewModel: PlayBarViewModel()))
    defer { window.isHidden = true }

    let expectedActions = ["Share Episode", "Transcribe", "Rate Episode"]
    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        let labels = Set(
          Self.accessibilityElements(in: window).compactMap(\.accessibilityLabel)
        )
        return expectedActions.allSatisfy(labels.contains)
      },
      { @MainActor in "Play bar did not expose Share, Transcribe, and Rate actions" }
    )

    let orderedActions = Self.accessibilityElements(in: window)
      .filter { element in
        guard let label = element.accessibilityLabel else { return false }
        return expectedActions.contains(label)
      }
      .sorted { $0.accessibilityFrame.minX < $1.accessibilityFrame.minX }
      .compactMap(\.accessibilityLabel)
    #expect(orderedActions == expectedActions)

    let transcribeButton = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Transcribe" }
    )
    #expect(transcribeButton.accessibilityActivate())

    let transcriptionQueue = Container.shared.transcriptionQueue()
    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        transcriptionQueue.status(for: episode.id, hasTranscript: false).canPause
      },
      { @MainActor in "Play bar transcription action did not enqueue the episode" }
    )
  }
}
