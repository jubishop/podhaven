// Copyright Justin Bishop, 2025

import Foundation

// MARK: - BackgroundURLSessionCompletionCenter

/// Stores and invokes the completion handlers that iOS provides when delivering
/// background URLSession events to the app. AppDelegate will save the handler,
/// and the URLSession delegate calls `complete(for:)` when it's finished.
final class BackgroundURLSessionCompletionCenter {
  static let shared = BackgroundURLSessionCompletionCenter()

  private let lock = NSLock()
  private var completions: [String: () -> Void] = [:]

  private init() {}

  func store(identifier: String?, completion: @escaping () -> Void) {
    guard let id = identifier else { return }
    lock.lock()
    defer { lock.unlock() }
    completions[id] = completion
  }

  func complete(for identifier: String?) {
    guard let id = identifier else { return }
    let completion: (() -> Void)? = {
      lock.lock()
      defer { lock.unlock() }
      return completions.removeValue(forKey: id)
    }()
    completion?()
  }
}
