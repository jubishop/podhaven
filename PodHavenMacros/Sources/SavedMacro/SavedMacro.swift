// Copyright Justin Bishop, 2025

import Tagged

/// A macro that generates the required boilerplate for a Saved model.
///
/// Apply this macro to a struct that should conform to the Saved protocol:
///
/// ```swift
/// @Saved<UnsavedYourType>
/// struct YourType {
///   // Other properties and methods
/// }
/// ```
///
/// This will automatically generate:
/// - typealias ID = Tagged<Self, Int64>
/// - let id: ID
/// - let creationDate: Date
/// - var unsaved: UnsavedType
/// - init(id:from:) implementation
@attached(
  member,
  names: named(ID),
  named(id),
  named(unsaved),
  named(creationDate),
  named(init(id:creationDate:from:))
)
public macro Saved<T>() = #externalMacro(module: "SavedMacroPlugin", type: "SavedMacro")
