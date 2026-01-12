// Copyright Justin Bishop, 2025

import Foundation

/// A macro that generates the implementation of caughtError for ReadableError protocol
/// conformance.
///
/// For example:
/// ```swift
/// @ReadableError
/// enum ParseError: ReadableError {
///   case invalidData(Data, Error)
///   case failure(caught: Error)
///   case somethingElse
/// }
/// ```
///
/// Will generate:
/// ```swift
/// var caughtError: Error? {
///   switch self {
///   case .invalidData(_, let error): return error
///   case .failure(let error): return error
///   default: return nil
///   }
/// }
/// ```
@attached(member, names: named(caughtError))
public macro ReadableError() =
  #externalMacro(module: "ReadableErrorMacroPlugin", type: "ReadableErrorMacro")
