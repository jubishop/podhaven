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
    guard let genericArgument = node.attributeName.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments.first?.argument else {
      throw MacroError.noGenericParameter
    }
    
    let unsavedType = genericArgument.trimmed.description
    
    return [
      """
      // MARK: - Saved
      
      typealias ID = Tagged<Self, Int64>
      var id: ID
      var unsaved: \(raw: unsavedType)
      
      init(id: ID, from unsaved: \(raw: unsavedType)) {
        self.id = id
        self.unsaved = unsaved
      }
      """
    ]
  }
}

enum MacroError: Error {
  case noGenericParameter
}

@main
struct SavedMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    SavedMacro.self,
  ]
}
