// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

// Each test process keeps its files under one root that it removes when it
// exits. A process that dies first leaves its root locked by nobody, so the
// next test process removes it.
enum TestFiles {
  private static let rootPrefix = "PodHavenTests-"
  private static let lockName = "owner.lock"

  static func uniqueURL() -> URL {
    root.appendingPathComponent(UUID().uuidString)
  }

  private static let root: URL = {
    removeAbandonedRoots()
    let root = URL.temporaryDirectory.appendingPathComponent(rootPrefix + UUID().uuidString)
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    } catch {
      Assert.fatal("Failed to create test files root \(root.path): \(error)")
    }
    let lock = open(
      root.appendingPathComponent(lockName).path,
      O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK,
      0o600
    )
    guard lock >= 0
    else { Assert.fatal("Failed to lock test files root \(root.path): errno \(errno)") }
    atexit { try? FileManager.default.removeItem(at: TestFiles.root) }
    return root
  }()

  private static func removeAbandonedRoots() {
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: URL.temporaryDirectory,
        includingPropertiesForKeys: nil
      )
    } catch {
      Assert.fatal("Failed to list \(URL.temporaryDirectory.path): \(error)")
    }
    for entry in entries where entry.lastPathComponent.hasPrefix(rootPrefix) {
      let lock = open(
        entry.appendingPathComponent(lockName).path,
        O_RDWR | O_EXLOCK | O_NONBLOCK
      )
      guard lock >= 0 else { continue }
      defer { close(lock) }
      try? FileManager.default.removeItem(at: entry)
    }
  }
}
