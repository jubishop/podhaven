// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Sentry
import Testing

@testable import PodHaven

@Suite("of OPML import diagnostics", .container)
@MainActor struct OPMLImportDiagnosticsTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fileManager) private var fileManager
  @DynamicInjected(\.opmlViewModel) private var opmlViewModel

  private var fakeFileManager: FakeFileManager { fileManager as! FakeFileManager }

  @Test("a failed parse sends one event with the OPML file and decoding context")
  func failedParseSendsOneEvent() async throws {
    let captured = captureDiagnostics()
    let url = URL(string: "file:///PodcastAddict_OPML_export.opml")!
    let data = brokenOPML()
    try await fakeFileManager.writeData(data, to: url)

    await opmlViewModel.importOPMLFromURL(url: url)

    #expect(captured().count == 1)
    let event = try #require(captured().first)
    #expect(event.message == "OPML import parse failure")
    #expect(event.level == .error)
    let context = try JSONDecoder().decode(ImportContext.self, from: event.context)
    #expect(context.fileName == "PodcastAddict_OPML_export.opml")
    #expect(context.bytes == data.count)
    #expect(context.attachedBytes == data.count)
    #expect(!context.truncated)
    #expect(context.error.contains("[DecodingError.keyNotFound]"))
    #expect(context.error.contains("Missing key: body"))
    #expect(context.error.contains("Coding path: body"))
    #expect(event.attachments.count == 1)
    let attachment = try #require(event.attachments.first)
    #expect(attachment.data == data)
    #expect(attachment.contentType == "text/x-opml")
    #expect(alert.config?.title == "Error")
    #expect(opmlViewModel.opmlFile == nil)
  }

  @Test("a successful import sends no event")
  func successfulImportSendsNoEvent() async throws {
    let captured = captureDiagnostics()
    let url = URL(string: "file:///empty.opml")!
    try await fakeFileManager.writeData(
      PreviewBundle.loadAsset(named: "empty", in: .OPML),
      to: url
    )

    await opmlViewModel.importOPMLFromURL(url: url)

    #expect(opmlViewModel.opmlFile != nil)
    #expect(alert.config == nil)
    #expect(captured().isEmpty)
  }

  @Test("an oversized file attaches only the size cap and records the original size")
  func oversizedFileIsTruncated() async throws {
    let captured = captureDiagnostics()
    let url = URL(string: "file:///large.opml")!
    let data = brokenOPML(padding: OPMLImportDiagnostics.maximumAttachmentBytes)
    #expect(data.count > OPMLImportDiagnostics.maximumAttachmentBytes)
    try await fakeFileManager.writeData(data, to: url)

    await opmlViewModel.importOPMLFromURL(url: url)

    #expect(captured().count == 1)
    let event = try #require(captured().first)
    let context = try JSONDecoder().decode(ImportContext.self, from: event.context)
    #expect(context.bytes == data.count)
    #expect(context.attachedBytes == OPMLImportDiagnostics.maximumAttachmentBytes)
    #expect(context.truncated)
    #expect(event.attachments.count == 1)
    let attachment = try #require(event.attachments.first)
    #expect(attachment.data == data.prefix(OPMLImportDiagnostics.maximumAttachmentBytes))
  }

  @Test("a local file over the size limit is refused with an alert that names the file")
  func fileOverSizeLimitIsRefused() async throws {
    let captured = captureDiagnostics()
    let url = URL(filePath: "/private/var/mobile/Containers/Shared/AppGroup/Subscriptions.opml")
    try await fakeFileManager.writeData(
      brokenOPML(padding: ShareExtensionContract.opmlByteLimit),
      to: url
    )

    await opmlViewModel.importOPMLFromURL(url: url)
    let answered = try await answerAlert("Ok")

    #expect(answered.title == "Error")
    #expect(
      answered.message
        == "“Subscriptions.opml” is larger than 4 MB, the largest OPML file PodHaven can import."
    )
    #expect(captured().isEmpty)
    #expect(opmlViewModel.opmlFile == nil)
  }

  @Test("repeated failures are rate limited")
  func repeatedFailuresAreRateLimited() async throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let captured = captureDiagnostics()
    let url = URL(string: "file:///broken.opml")!
    try await fakeFileManager.writeData(brokenOPML(), to: url)

    await opmlViewModel.importOPMLFromURL(url: url)
    await opmlViewModel.importOPMLFromURL(url: url)
    #expect(captured().count == 1)

    clock.advance(by: OPMLImportDiagnostics.minimumCaptureInterval)
    await opmlViewModel.importOPMLFromURL(url: url)
    #expect(captured().count == 2)
  }

  // MARK: - Helpers

  private struct CapturedEvent: Sendable {
    struct Attachment: Sendable {
      let data: Data?
      let contentType: String?
    }

    let message: String?
    let level: SentryLevel
    let context: Data
    let attachments: [Attachment]
  }

  private struct ImportContext: Decodable {
    let fileName: String
    let bytes: Int
    let attachedBytes: Int
    let truncated: Bool
    let error: String
  }

  private func captureDiagnostics() -> ThreadSafe<[CapturedEvent]> {
    let captured = ThreadSafe<[CapturedEvent]>([])
    Container.shared.opmlDiagnosticCapture.context(.test) {
      { event, attachments in
        do {
          let context = try JSONSerialization.data(
            withJSONObject: event.context?["opml_import"] ?? [:]
          )
          captured {
            $0.append(
              CapturedEvent(
                message: event.message?.formatted,
                level: event.level,
                context: context,
                attachments: attachments.map {
                  CapturedEvent.Attachment(data: $0.data, contentType: $0.contentType)
                }
              )
            )
          }
        } catch {
          Issue.record(error)
        }
      }
    }
    return captured
  }

  private func brokenOPML(padding: Int = 0) -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
      <head><title>Broken</title></head>
      <!-- \(String(repeating: "x", count: padding)) -->
      </opml>
      """
      .utf8
    )
  }
}
