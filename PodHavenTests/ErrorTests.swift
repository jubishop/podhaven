// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of error tests")
struct ErrorTests {
  @Test("typeName() looks good for NSURLError errors")
  func testTypeNameLooksGoodForNSURLErrorErrors() async throws {
    await #expect {
      _ = try await URLSession.shared.data(
        for: URLRequest(url: URL(string: "https://127.0.0.1")!, timeoutInterval: 0.0001)
      )
    } throws: { error in
      #expect(
        ErrorKit.message(for: error) == "[NSURLErrorDomain: -1001] The request timed out."
      )
      // loggableMessage now includes underlying errors from NSUnderlyingErrorKey
      let loggable = String(describing: ErrorKit.loggableMessage(for: error))
      #expect(loggable.hasPrefix("[NSURLError.Error]\n[NSURLErrorDomain: -1001]"))
      guard let urlError = error as? URLError, urlError.code == .timedOut
      else { return false }
      return true
    }

    let cancellationSemaphor = AsyncSemaphore(value: 0)
    let task = Task {
      async let expect = await #expect {
        _ = try await URLSession.shared.data(
          for: URLRequest(url: URL(string: "https://artisanalsoftware.com")!)
        )
      } throws: { error in
        #expect(ErrorKit.message(for: error) == "[NSURLErrorDomain: -999] cancelled")
        // loggableMessage now includes underlying errors from NSUnderlyingErrorKey
        let loggable = String(describing: ErrorKit.loggableMessage(for: error))
        #expect(loggable.hasPrefix("[NSURLError.Error]\n[NSURLErrorDomain: -999]"))
        guard let urlError = error as? URLError, urlError.code == .cancelled
        else { return false }
        return true
      }
      cancellationSemaphor.signal()
      return await expect
    }
    await cancellationSemaphor.wait()
    task.cancel()
  }

  @Test("loggableMessage includes single underlying error")
  func testLoggableMessageIncludesSingleUnderlyingError() {
    let underlying = NSError(
      domain: "TestDomain",
      code: 42,
      userInfo: [NSLocalizedDescriptionKey: "Underlying failure"]
    )
    let error = NSError(
      domain: "TopDomain",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Top level error",
        NSUnderlyingErrorKey: underlying,
      ]
    )

    #expect(
      ErrorKit.loggableMessage(for: error) == """
        [NSError.Error]
        [TopDomain: 1] Top level error
        Underlying: NSError.Error ->
          [TestDomain: 42] Underlying failure
        """
    )
  }

  @Test("loggableMessage includes nested underlying errors")
  func testLoggableMessageIncludesNestedUnderlyingErrors() {
    let deepest = NSError(
      domain: "DeepDomain",
      code: 3,
      userInfo: [NSLocalizedDescriptionKey: "Deepest error"]
    )
    let middle = NSError(
      domain: "MiddleDomain",
      code: 2,
      userInfo: [
        NSLocalizedDescriptionKey: "Middle error",
        NSUnderlyingErrorKey: deepest,
      ]
    )
    let top = NSError(
      domain: "TopDomain",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Top error",
        NSUnderlyingErrorKey: middle,
      ]
    )

    #expect(
      ErrorKit.loggableMessage(for: top) == """
        [NSError.Error]
        [TopDomain: 1] Top error
        Underlying: NSError.Error ->
          [MiddleDomain: 2] Middle error
          Underlying: NSError.Error ->
            [DeepDomain: 3] Deepest error
        """
    )
  }

  @Test("loggableMessage with NSError with underlying")
  func testLoggableMessageWithNSErrorWithUnderlying() {
    let underlying = NSError(
      domain: "SystemDomain",
      code: 99,
      userInfo: [NSLocalizedDescriptionKey: "System failure"]
    )
    let errorWithUnderlying = NSError(
      domain: "MiddleDomain",
      code: 50,
      userInfo: [
        NSLocalizedDescriptionKey: "Middle failure",
        NSUnderlyingErrorKey: underlying,
      ]
    )

    // Direct NSError with underlying shows the chain
    #expect(
      ErrorKit.loggableMessage(for: errorWithUnderlying) == """
        [NSError.Error]
        [MiddleDomain: 50] Middle failure
        Underlying: NSError.Error ->
          [SystemDomain: 99] System failure
        """
    )
  }

  @Test(
    "loggableMessage includes DecodingError context",
    arguments: [
      (
        DecodingError.keyNotFound(
          TestCodingKey("text"),
          DecodingError.Context(
            codingPath: [TestCodingKey("body"), TestCodingKey("outline"), TestCodingKey(3)],
            debugDescription: "No value associated with key text."
          )
        ),
        """
        [DecodingError.keyNotFound]
        Missing key: text
        Coding path: body.outline[3]
        Debug description: No value associated with key text.
        """
      ),
      (
        DecodingError.typeMismatch(
          String.self,
          DecodingError.Context(
            codingPath: [TestCodingKey("head"), TestCodingKey("title")],
            debugDescription: "Expected to decode String but found a dictionary instead."
          )
        ),
        """
        [DecodingError.typeMismatch]
        Type mismatch: expected String
        Coding path: head.title
        Debug description: Expected to decode String but found a dictionary instead.
        """
      ),
      (
        DecodingError.valueNotFound(
          Int.self,
          DecodingError.Context(
            codingPath: [TestCodingKey(0), TestCodingKey("count")],
            debugDescription: "Expected Int value but found null instead."
          )
        ),
        """
        [DecodingError.valueNotFound]
        Value not found: expected Int
        Coding path: [0].count
        Debug description: Expected Int value but found null instead.
        """
      ),
      (
        DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: [],
            debugDescription: "The given data was not valid XML."
          )
        ),
        """
        [DecodingError.dataCorrupted]
        Data corrupted
        Coding path: (root)
        Debug description: The given data was not valid XML.
        """
      ),
    ]
  )
  func testLoggableMessageIncludesDecodingErrorContext(error: DecodingError, expected: String) {
    var lines = expected.components(separatedBy: "\n")
    lines.insert(ErrorKit.message(for: error), at: 1)
    #expect(
      String(describing: ErrorKit.loggableMessage(for: error)) == lines.joined(separator: "\n")
    )
  }

  @Test("loggableMessage includes DecodingError context of underlying errors")
  func testLoggableMessageIncludesUnderlyingDecodingErrorContext() {
    let decodingError = DecodingError.keyNotFound(
      TestCodingKey("text"),
      DecodingError.Context(
        codingPath: [TestCodingKey("body"), TestCodingKey("outline"), TestCodingKey(1)],
        debugDescription: "No value associated with key text."
      )
    )
    let error = NSError(
      domain: "TopDomain",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Top level error",
        NSUnderlyingErrorKey: decodingError,
      ]
    )

    #expect(
      String(describing: ErrorKit.loggableMessage(for: error)) == """
        [NSError.Error]
        [TopDomain: 1] Top level error
        Underlying: DecodingError.keyNotFound ->
          \(ErrorKit.message(for: decodingError))
          Missing key: text
          Coding path: body.outline[1]
          Debug description: No value associated with key text.
        """
    )
  }
}

private struct TestCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init(_ intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }

  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { self.init(intValue) }
}
