// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of Episode Detail transcript views")
@MainActor struct EpisodeDetailTranscriptViewTests {
  @Test(
    "publisher transcript exposes its source and on-device replacement action",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func publisherTranscriptSourceAndReplacementAction() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let repo = Container.shared.repo()
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "Publisher words")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/accessibility.vtt")!,
      mimeType: "text/vtt",
      language: "en-US"
    )
    #expect(
      try await repo.storeTranscriptIfAbsent(
        podcastEpisode.id,
        transcript: transcript,
        publisherSource: source
      )
    )
    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    viewModel.selectTextTab(.transcript)
    let host = UIHostingController(rootView: EpisodeDetailView(viewModel: viewModel))
    host.loadViewIfNeeded()
    host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    host.beginAppearanceTransition(true, animated: false)
    host.endAppearanceTransition()
    defer {
      host.beginAppearanceTransition(false, animated: false)
      host.endAppearanceTransition()
    }
    host.view.layoutIfNeeded()

    let elements = accessibilityElements(in: host.view)
    #expect(
      elements.contains {
        $0.accessibilityLabel == "Transcript source"
          && $0.accessibilityValue == "Podcast feed"
      }
    )
    #expect(
      elements.contains {
        $0.accessibilityLabel == "Replace with On-Device Transcription"
      }
    )
  }

  @Test(
    "on-device transcript exposes its source without a replacement action",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func onDeviceTranscriptSourceWithoutReplacementAction() async throws {
    await TranscriptionHelpers.prepareAvailability()
    let repo = Container.shared.repo()
    let podcastEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "On-device words")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    try await repo.updateTranscript(podcastEpisode.id, transcript: transcript.jsonString())
    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    viewModel.selectTextTab(.transcript)
    let host = UIHostingController(rootView: EpisodeDetailView(viewModel: viewModel))
    host.loadViewIfNeeded()
    host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    host.beginAppearanceTransition(true, animated: false)
    host.endAppearanceTransition()
    defer {
      host.beginAppearanceTransition(false, animated: false)
      host.endAppearanceTransition()
    }
    host.view.layoutIfNeeded()

    let elements = accessibilityElements(in: host.view)
    #expect(
      elements.contains {
        $0.accessibilityLabel == "Transcript source"
          && $0.accessibilityValue == "On device"
      }
    )
    #expect(
      !elements.contains {
        $0.accessibilityLabel == "Replace with On-Device Transcription"
      }
    )
  }

  @Test(
    "unreadable transcript explains unavailable recovery without a dead action",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func unreadableTranscriptWithoutOnDeviceSupport() {
    let host = UIHostingController(
      rootView: TranscriptDecodeFailureView(canTranscribeAgain: false, transcribe: {})
    )
    host.loadViewIfNeeded()
    host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    host.beginAppearanceTransition(true, animated: false)
    host.endAppearanceTransition()
    defer {
      host.beginAppearanceTransition(false, animated: false)
      host.endAppearanceTransition()
    }
    host.view.layoutIfNeeded()

    let labels = Set(accessibilityElements(in: host.view).compactMap(\.accessibilityLabel))
    #expect(labels.contains("Transcript couldn't be read"))
    #expect(labels.contains("On-device transcription isn't available to replace it."))
    #expect(!labels.contains("Transcribe Again"))
  }

  private func accessibilityElements(in root: NSObject) -> [NSObject] {
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
}
