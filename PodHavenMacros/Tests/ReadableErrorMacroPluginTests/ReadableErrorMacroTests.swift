// Copyright Justin Bishop, 2025

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
import XCTest

@testable import ReadableErrorMacro
@testable import ReadableErrorMacroPlugin

struct ReadableErrorMacroTests {
  @Test
  func testReadableErrorMacroExpansion() throws {
    // Test with various enum case types
    let inputSource = """
      @ReadableError
      enum TestError: ReadableError {
        case invalidData(Data, Error)
        case failure(caught: Error)
        case noError
      }
      """

    let expected = """
      enum TestError: ReadableError {
        case invalidData(Data, Error)
        case failure(caught: Error)
        case noError
        var caughtError: Error? {
          switch self {
            case .invalidData(_, let error): return error
            case .failure(let error): return error
            default: return nil
          }
        }
      }
      """

    assertMacroExpansion(
      inputSource,
      expandedSource: expected,
      macros: ["ReadableError": ReadableErrorMacro.self],
      indentationWidth: .spaces(2)
    )
  }

  @Test
  func testReadableErrorWithNoErrorCases() throws {
    // Test with no Error cases
    let inputSource = """
      @ReadableError
      enum NoErrorEnum: ReadableError {
        case first(String)
        case second(Int)
      }
      """

    let expected = """
      enum NoErrorEnum: ReadableError {
        case first(String)
        case second(Int)
        var caughtError: Error? { nil }
      }
      """

    assertMacroExpansion(
      inputSource,
      expandedSource: expected,
      macros: ["ReadableError": ReadableErrorMacro.self],
      indentationWidth: .spaces(2)
    )
  }
  
  @Test
  func testReadableErrorWithAllErrorCases() throws {
    // Test enum where all cases have Error parameters - no default needed
    let inputSource = """
      @ReadableError
      enum AllErrorsEnum: ReadableError {
        case first(Error)
        case second(caught: Error)
      }
      """

    let expected = """
      enum AllErrorsEnum: ReadableError {
        case first(Error)
        case second(caught: Error)
        var caughtError: Error? {
          switch self {
            case .first(let error): return error
            case .second(let error): return error
          }
        }
      }
      """

    assertMacroExpansion(
      inputSource,
      expandedSource: expected,
      macros: ["ReadableError": ReadableErrorMacro.self],
      indentationWidth: .spaces(2)
    )
  }
  
  @Test
  func testReadableErrorWithLabeledErrorParameter() throws {
    // Test with Error parameter that has a label and is not in first position
    let inputSource = """
      @ReadableError
      enum PositionalErrorEnum: ReadableError {
        case invalidData(data: Data, error: Error)
        case requestFailure(url: URL, statusCode: Int, error: Error)
      }
      """

    let expected = """
      enum PositionalErrorEnum: ReadableError {
        case invalidData(data: Data, error: Error)
        case requestFailure(url: URL, statusCode: Int, error: Error)
        var caughtError: Error? {
          switch self {
            case .invalidData(_, let error): return error
            case .requestFailure(_, _, let error): return error
          }
        }
      }
      """

    assertMacroExpansion(
      inputSource,
      expandedSource: expected,
      macros: ["ReadableError": ReadableErrorMacro.self],
      indentationWidth: .spaces(2)
    )
  }
  
  @Test
  func testReadableErrorThrowsOnMultipleErrorParameters() throws {
    // Setup test input with multiple Error parameters in a single case
    let inputSource = """
      @ReadableError
      enum TestError: ReadableError {
        case multipleErrors(Error, Error)
      }
      """

    // Should throw a diagnostic, not expand properly
    assertMacroExpansion(
      inputSource,
      expandedSource: inputSource,  // Source should remain unchanged
      diagnostics: [
        DiagnosticSpec(
          message: "@ReadableError found multiple error parameters in case 'multipleErrors'. Only one error parameter is allowed per case.",
          line: 3,
          column: 9
        )
      ],
      macros: ["ReadableError": ReadableErrorMacro.self],
      indentationWidth: .spaces(2)
    )
  }
}
