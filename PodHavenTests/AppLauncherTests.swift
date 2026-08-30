// Copyright Justin Bishop, 2026

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
}
