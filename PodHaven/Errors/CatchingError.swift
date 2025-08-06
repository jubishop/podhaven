// Copyright Justin Bishop, 2025

import Foundation

protocol CatchingError: Error, Sendable {
  static func caught(_ error: Error) -> Self
}

extension CatchingError {
  static func checkTaskCancellation() throws(Self) {
    try self.catch { try Task.checkCancellation() }
  }

  static func `catch`<ReturnType>(_ operation: () throws -> ReturnType) throws(Self)
    -> ReturnType
  {
    do {
      return try operation()
    } catch let error as Self {
      throw error
    } catch {
      throw caught(error)
    }
  }

  static func `catch`<ReturnType>(_ operation: @Sendable () async throws -> ReturnType)
    async throws(Self) -> ReturnType
  {
    do {
      return try await operation()
    } catch let error as Self {
      throw error
    } catch {
      throw caught(error)
    }
  }

  static func mapError<ReturnType>(
    _ operation: @Sendable () async throws -> ReturnType,
    _ transform: @Sendable (Error) -> Self
  ) async throws(Self) -> ReturnType {
    do {
      return try await operation()
    } catch {
      throw transform(error)
    }
  }

  static func mapError<ReturnType>(
    _ operation: @Sendable () throws -> ReturnType,
    transform: @Sendable (Error) -> Self
  ) async throws(Self) -> ReturnType {
    do {
      return try operation()
    } catch {
      throw transform(error)
    }
  }
}
