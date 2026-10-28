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
