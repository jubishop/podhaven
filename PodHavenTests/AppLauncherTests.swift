// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Sentry
import Testing

@testable import PodHaven

@Suite("of AppLauncher tests", .container)
struct AppLauncherTests {
  private final class FakeSentryScope: SentryScopeConfiguring {
    private(set) var attachments: [Sentry.Attachment] = []
    private(set) var tags: [String: String] = [:]
    private(set) var user: Sentry.User?

    func setTag(value: String, key: String) {
      tags[key] = value
    }

    func setUser(_ user: Sentry.User?) {
      self.user = user
    }

    func addAttachment(_ attachment: Sentry.Attachment) {
      attachments.append(attachment)
    }
  }

  @Test("initial Sentry scope includes file-backed recent log tails")
  func initialSentryScopeIncludesRecentLogTails() {
    let scope = FakeSentryScope()
    AppLauncher.configureInitialSentryScope(scope)

    #expect(scope.tags["git-commit-hash"] == AppInfo.gitCommitHash)
    #expect(scope.tags["log-session-id"] == FileLogHandler.sessionID)
    #expect(scope.user?.userId == AppInfo.deviceIdentifier)
    #expect(scope.attachments.count == 2)
    #expect(
      scope.attachments.map(\.filename) == [
        "recent-log.ndjson",
        "recent-widget-log.ndjson",
      ]
    )
    #expect(
      scope.attachments.map(\.path) == [
        AppInfo.recentLogFileURL.path,
        WidgetInfo.recentLogFileURL.path,
      ]
    )
    #expect(scope.attachments.allSatisfy { $0.contentType == "application/x-ndjson" })
    #expect(scope.attachments.allSatisfy { $0.data == nil })
  }

  @Test("Sentry does not capture failed requests automatically")
  func sentryDoesNotCaptureFailedRequestsAutomatically() {
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)

    #expect(!options.enableCaptureFailedRequests)
  }

  @Test(
    "empty recovered-hang scopes and ordinary scopes deliver recent tails once",
    arguments: [false, true],
    [false, true]
  )
  func outgoingRecentTails(initialScope: Bool, missingWidget: Bool) async throws {
    let files = [AppInfo.recentLogFileURL, WidgetInfo.recentLogFileURL]
    let content = Data(
      "{\"sessionID\":\"controlled-session\",\"message\":\"operation started\"}\n".utf8
    )
    for (index, file) in files.enumerated() where index == 0 || !missingWidget {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: file)
    }
    defer { for file in files { try? FileManager.default.removeItem(at: file) } }
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    let capture = try SentryEnvelopeCapture(options: options)
    let scope = Sentry.Scope()
    if initialScope { AppLauncher.configureInitialSentryScope(scope) }
    let event = Sentry.Event(level: .error)
    let exception = Exception(value: "controlled recovered hang", type: "App Hang Fully Blocked")
    exception.mechanism = Mechanism(type: "AppHang")
    event.exceptions = [exception]
    if initialScope {
      event.exceptions = nil
    }
    let eventID = capture.client.capture(event: event, scope: scope)
    #expect(eventID == event.eventId)
    let items = try await capture.items()
    let attachments = items.filter { $0.header["type"] as? String == "attachment" }
    let expected =
      missingWidget ? ["recent-log.ndjson"] : ["recent-log.ndjson", "recent-widget-log.ndjson"]
    #expect(
      attachments.compactMap { $0.header["filename"] as? String }.sorted() == expected.sorted()
    )
    #expect(
      attachments.allSatisfy { $0.header["content_type"] as? String == "application/x-ndjson" }
    )
    #expect(attachments.allSatisfy { $0.data == content })
    let outgoing = try #require(items.first { $0.header["type"] as? String == "event" })
    let json = try #require(JSONSerialization.jsonObject(with: outgoing.data) as? [String: Any])
    let contexts = try #require(json["contexts"] as? [String: Any])
    #expect(contexts["recent_log_files"] != nil)
    #expect((contexts["podcast_detail_performance"] != nil) == !initialScope)
    #expect(json["environment"] as? String == AppInfo.environment.rawValue)
    if initialScope {
      let tags = try #require(json["tags"] as? [String: String])
      #expect(tags["git-commit-hash"] == AppInfo.gitCommitHash)
      #expect(tags["log-session-id"] == FileLogHandler.sessionID)
      let user = try #require(json["user"] as? [String: Any])
      #expect(user["id"] as? String == AppInfo.deviceIdentifier)
    }
  }

  @Test("hint callback preserves filtering and existing attachment identity")
  func hintCallbackPreservesFilteringAndAttachments() throws {
    let options = Sentry.Options()
    AppLauncher.configureSentryOptions(options)
    #expect(options.beforeSend == nil)
    let callback = try #require(options.beforeSendWithHint)
    let hint = Hint()
    let tail = Attachment(path: AppInfo.recentLogFileURL.path, filename: "recent-log.ndjson")
    let full = Attachment(data: Data("full log".utf8), filename: "log.ndjson")
    let photo = Attachment(
      data: Data([1, 2, 3]),
      filename: "screenshot.jpg",
      contentType: "image/jpeg"
    )
    hint.attachments = [tail, full, photo]
    let event = Event(level: .error)
    #expect(callback(event, hint) === event)
    #expect(hint.attachments.count == 4)
    #expect(hint.attachments[0] === tail)
    #expect(hint.attachments[1] === full)
    #expect(hint.attachments[2] === photo)
    #expect(callback(event, hint) === event)
    #expect(hint.attachments.count == 4)
    let exception = Exception(value: "disk write", type: "MXDiskWriteException")
    exception.mechanism = Mechanism(type: "mx_disk_write_exception")
    event.exceptions = [exception]
    let filteredHint = Hint()
    #expect(callback(event, filteredHint) == nil)
    #expect(filteredHint.attachments.isEmpty)
  }

  @Test("outgoing feedback preserves full logs and photos alongside recent tails")
  func outgoingFeedbackAttachments() async throws {
    let files = [
      AppInfo.recentLogFileURL, WidgetInfo.recentLogFileURL, AppInfo.logFileURL,
      WidgetInfo.logFileURL,
    ]
    let content = Data("{\"message\":\"feedback fixture\"}\n".utf8)
    for file in files {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try content.write(to: file)
    }
    defer { for file in files { try? FileManager.default.removeItem(at: file) } }
    let options = Options()
    AppLauncher.configureSentryOptions(options)
    let capture = try SentryEnvelopeCapture(options: options)
    let scope = Scope()
    AppLauncher.configureInitialSentryScope(scope)
    let photo = Data([1, 2, 3])
    capture.client.capture(
      feedback: SentryFeedback(
        message: "controlled feedback",
        name: nil,
        email: nil,
        source: .custom,
        attachments: [
          Attachment(path: AppInfo.logFileURL.path, filename: "log.ndjson"),
          Attachment(path: WidgetInfo.logFileURL.path, filename: "widget-log.ndjson"),
          Attachment(data: photo, filename: "screenshot.jpg", contentType: "image/jpeg"),
        ]
      ),
      scope: scope
    )
    let items = try await capture.items()
    let attachments = items.filter { $0.header["type"] as? String == "attachment" }
    #expect(
      attachments.compactMap { $0.header["filename"] as? String }.sorted()
        == [
          "recent-log.ndjson", "recent-widget-log.ndjson", "log.ndjson", "widget-log.ndjson",
          "screenshot.jpg",
        ]
        .sorted()
    )
    #expect(
      attachments.first { $0.header["filename"] as? String == "screenshot.jpg" }?.data == photo
    )
  }

}
