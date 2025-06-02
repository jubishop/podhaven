// Copyright Justin Bishop, 2025

import Foundation

enum That {
  static func itHolds(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () async throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if !(try await block()) {
        return false
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    return true
  }

  static func itHolds(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if !(try block()) {
        return false
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    return true
  }

  static func eventually(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if try block() {
        return true
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    return false
  }

  static func eventually(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () async throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if try await block() {
        return true
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    return false
  }

  static func never(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if try block() {
        return false
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    return true
  }

  static func never(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () async throws -> Bool
  ) async throws -> Bool {
    var attempts = 0
    while attempts < maxAttempts {
      if try await block() {
        return false
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    return true
  }
}
