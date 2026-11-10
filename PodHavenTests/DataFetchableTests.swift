// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of DataFetchable byte limit tests", .container)
struct DataFetchableTests {
  private let session = FakeDataFetchable()

  @Test("validatedData returns a body exactly at its byte limit")
  func bodyAtLimit() async throws {
    let url = URL.valid()
    let body = Self.body(count: 100_000)
    await session.respond(to: url, data: body)

    #expect(try await session.validatedData(from: url, byteLimit: body.count) == body)
  }

  @Test("validatedData refuses a body that grows past its byte limit")
  func bodyPastLimit() async throws {
    let url = URL.valid()
    let body = Self.body(count: 100_001)
    await session.respond(to: url, data: body)

    await #expect(throws: ResponseTooLargeError.self) {
      try await session.validatedData(from: url, byteLimit: 100_000)
    }
  }

  @Test("validatedData refuses a declared length over its byte limit")
  func declaredLengthPastLimit() async throws {
    let url = URL.valid()
    await session.respond(to: url) { url in
      (Data("small".utf8), URL.response(url, headerFields: ["Content-Length": "100001"]))
    }

    await #expect(throws: ResponseTooLargeError.self) {
      try await session.validatedData(from: url, byteLimit: 100_000)
    }
  }

  @Test("validatedData reports an HTTP failure status ahead of an oversized body")
  func failureStatus() async throws {
    let url = URL.valid()
    await session.respond(to: url) { url in
      (Self.body(count: 100_001), URL.response(url, statusCode: 503))
    }

    let error = await #expect(throws: HTTPStatusError.self) {
      try await session.validatedData(from: url, byteLimit: 100_000)
    }
    #expect(error?.statusCode == 503)
  }

  @Test("URLSession streams a local file up to its byte limit")
  func urlSessionFileLimit() async throws {
    let fileURL = TestFiles.uniqueURL()
    let body = Self.body(count: 300_000)
    try body.write(to: fileURL)
    let session = URLSession(configuration: .ephemeral)
    defer { session.finishTasksAndInvalidate() }

    #expect(try await session.validatedData(from: fileURL, byteLimit: body.count) == body)
    await #expect(throws: ResponseTooLargeError.self) {
      try await session.validatedData(from: fileURL, byteLimit: body.count - 1)
    }
  }

  private static func body(count: Int) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
  }
}
