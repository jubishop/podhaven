// Copyright Justin Bishop, 2025

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ReadableErrorMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax] = [],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Ensure we're operating on an enum
    guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
      throw MacroError.notAnEnum
    }

    // Extract all the enum cases
    let cases = enumDecl.memberBlock.members.compactMap { member -> EnumCaseDeclSyntax? in
      if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
        return caseDecl
      }
      return nil
    }

    // Generate case handling for caughtError implementation
    var caseStatements: [String] = []
    var hasNonErrorCase = false

    for caseDecl in cases {
      for element in caseDecl.elements {
        let caseName = element.name.text
        
        if let parameterClause = element.parameterClause {
          let parameters = parameterClause.parameters

          // Check if any parameter is of type Error
          var errorIndices: [Int] = []

          for (index, param) in parameters.enumerated() {
            if param.type.description.hasSuffix("Error") {
              errorIndices.append(index)
            }
          }
          
          // Throw an error if more than one associated error value is found
          if errorIndices.count > 1 {
            throw MacroError.multipleErrorParameters(caseName: caseName)
          }
          
          let errorIndex = errorIndices.first

          if let errorIndex {
            // Create parameter bindings based on the errorIndex
            let paramBindings = (0..<parameters.count)
              .map { i in
                i == errorIndex ? "let error" : "_"
              }
              .joined(separator: ", ")

            caseStatements.append("case .\(caseName)(\(paramBindings)): return error")
          } else {
            // Case with parameters but none are Error type
            hasNonErrorCase = true
          }
        } else {
          // Case without any parameters
          hasNonErrorCase = true
        }
      }
    }

    // If no cases with Error were found, just return default case
    if caseStatements.isEmpty {
      return [
        DeclSyntax(
          """
          var caughtError: Error? { nil }
          """
        )
      ]
    }

    // Only add default case if there are cases without error parameters
    if hasNonErrorCase {
      caseStatements.append("default: return nil")
    }

    // Build the implementation
    let implementation = caseStatements.joined(separator: "\n    ")

    return [
      DeclSyntax(
        """
        var caughtError: Error? {
          switch self {
            \(raw: implementation)
          }
        }
        """
      )
    ]
  }
}

enum MacroError: Error, CustomStringConvertible {
  case notAnEnum
  case multipleErrorParameters(caseName: String)

  var description: String {
    switch self {
    case .notAnEnum:
      return "@ReadableError can only be applied to enums"
    case .multipleErrorParameters(let caseName):
      return "@ReadableError found multiple error parameters in case '\(caseName)'. Only one error parameter is allowed per case."
    }
  }
}

@main
struct ReadableErrorMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    ReadableErrorMacro.self
  ]
}
