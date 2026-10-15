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
  @DynamicInjected(\.opmlViewModel) private var opmlViewModel
  @DynamicInjected(\.podcastOPMLSession) private var podcastOPMLSession

  private var opmlSession: FakeDataFetchable { podcastOPMLSession as! FakeDataFetchable }

  @Test("a failed parse sends one event with the OPML file and decoding context")
  func failedParseSendsOneEvent() async throws {
    let captured = captureDiagnostics()
    let url = URL(string: "file:///PodcastAddict_OPML_export.opml")!
    let data = brokenOPML(validOutlines: 1)
    await opmlSession.respond(to: url, data: data)

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
    #expect(context.error.contains("Missing key: text"))
    #expect(context.error.contains("Coding path: body.outline[1]"))
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
    await opmlSession.respond(to: url, data: PreviewBundle.loadAsset(named: "empty", in: .OPML))

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
    await opmlSession.respond(to: url, data: data)

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

  @Test("repeated failures are rate limited")
  func repeatedFailuresAreRateLimited() async throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let captured = captureDiagnostics()
    let url = URL(string: "file:///broken.opml")!
    await opmlSession.respond(to: url, data: brokenOPML())

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

  private func brokenOPML(validOutlines: Int = 0, padding: Int = 0) -> Data {
    let outlines = (0..<validOutlines)
      .map { index in
        #"<outline type="rss" text="Show \#(index)" xmlUrl="https://example.com/\#(index).rss"/>"#
      }
      .joined(separator: "\n")
    return Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
      <head><title>Broken</title></head>
      <!-- \(String(repeating: "x", count: padding)) -->
      <body>
      \(outlines)
      <outline type="rss" xmlUrl="https://example.com/missing-text.rss"/>
      </body>
      </opml>
      """
      .utf8
    )
  }
}
