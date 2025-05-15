// Copyright Justin Bishop, 2025

import Tagged

/// A macro that generates the required boilerplate for a Saved model.
///
/// Apply this macro to a struct that should conform to the Saved protocol:
///
/// ```swift
/// @GRDBSaved<UnsavedYourType>
/// struct YourType {
///   // Other properties and methods
/// }
/// ```
///
/// This will automatically generate:
/// - typealias ID = Tagged<Self, Int64>
/// - var id: ID
/// - var unsaved: UnsavedType
/// - init(id:from:) implementation
@attached(member, names: named(ID), named(id), named(unsaved), named(init(id:from:)))
public macro GRDBSaved<T>() = #externalMacro(module: "GRDBSavedMacroPlugin", type: "GRDBSavedMacro")
