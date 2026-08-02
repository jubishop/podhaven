// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of Episode Detail transcript views", .container)
@MainActor struct EpisodeDetailTranscriptViewTests {
  @DynamicInjected(\.appDB) private var appDB

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

  @Test(
    "unreadable publisher replacement omits the empty canonical divider",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI rendering differs outside the My Mac destination"
    )
  )
  func unreadablePublisherReplacementOmitsCanonicalDivider() async throws {
    let repo = Container.shared.repo()
    let podcastEpisode = try await Create.podcastEpisode()
    let onDeviceEpisode = try await Create.podcastEpisode()
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 1, text: "Publisher words")],
      locale: "en-US",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let source = PublisherTranscriptReference(
      url: URL(string: "https://example.com/unreadable-layout.vtt")!,
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
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET transcript = 'not-json' WHERE id = ?",
        arguments: [podcastEpisode.id]
      )
    }
    #expect(
      try await repo.updateTranscript(
        onDeviceEpisode.id,
        transcript: "not-json"
      )
    )
    let queue = Container.shared.transcriptionQueue()
    try await queue.enqueueReplacement(podcastEpisode.id)
    try await queue.enqueue(onDeviceEpisode.id)

    let loaded = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    let loadedOnDevice = try #require(
      try await repo.podcastEpisode(onDeviceEpisode.id)
    )
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
    let onDeviceViewModel = EpisodeDetailViewModel(
      episode: DisplayedEpisode(loadedOnDevice)
    )
    #expect(viewModel.transcriptDisplay == .decodeFailed)
    #expect(onDeviceViewModel.transcriptDisplay == .decodeFailed)
    #expect(viewModel.transcriptionStatus == .queued(position: 1, total: 2))
    #expect(
      onDeviceViewModel.transcriptionStatus == .queued(position: 2, total: 2)
    )

    let publisherHeight = fittingHeight(for: viewModel)
    let onDeviceHeight = fittingHeight(for: onDeviceViewModel)
    #expect(abs(publisherHeight - onDeviceHeight) < 0.5)
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

  private func fittingHeight(for viewModel: EpisodeDetailViewModel) -> CGFloat {
    let host = UIHostingController(
      rootView: EpisodeDetailTranscriptView(viewModel: viewModel)
    )
    return
      host.sizeThatFits(
        in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
      )
      .height
  }
}
