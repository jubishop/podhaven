// Copyright Justin Bishop, 2025

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct SavedMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax] = [],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Extract the generic type parameter
    guard let identifierType = node.attributeName.as(IdentifierTypeSyntax.self),
          let genericClause = identifierType.genericArgumentClause,
          let firstArgument = genericClause.arguments.first?.argument
    else {
      throw MacroError.noGenericParameter
    }
    
    let unsavedType = firstArgument.trimmed.description
    
    // Use 2-space indentation as per project guidelines
    return [
      DeclSyntax("// MARK: - Saved"),
      DeclSyntax(""),
      DeclSyntax("typealias ID = Tagged<Self, Int64>"),
      DeclSyntax("var id: ID"),
      DeclSyntax("var unsaved: \(raw: unsavedType)"),
      DeclSyntax("""
      init(id: ID, from unsaved: \(raw: unsavedType)) {
        self.id = id
        self.unsaved = unsaved
      }
      """)
    ]
  }
}

enum MacroError: Error, CustomStringConvertible {
  case noGenericParameter
  
  var description: String {
    switch self {
    case .noGenericParameter:
      return "@Saved requires a generic parameter specifying the unsaved type"
    }
  }
}

@main
struct SavedMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    SavedMacro.self,
  ]
}
