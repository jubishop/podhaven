// Copyright Justin Bishop, 2025

import Foundation

// MARK: - Saved Macro

@attached(member, names: named(ID), named(id), named(unsaved), named(init(id:from:)))
public macro Saved<T>() = #externalMacro(module: "SavedMacrosPlugin", type: "SavedMacro")
