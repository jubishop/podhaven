// Copyright Justin Bishop, 2025

import Foundation

struct StackTracer {
  static func capture(limit: Int = 10, drop: Int = 1) -> [String] {
    let symbols = Thread.callStackSymbols
      .filter { line in
        let unwantedLibraries = ["libswift", "libsystem", "SwiftUI"]
        if unwantedLibraries.contains(where: { line.contains($0) }) {
          return false
        }
        if line.range(of: #"0x[0-9a-fA-F]+ [0-9A-F\-]+ \+"#, options: .regularExpression) != nil {
          return false
        }
        return true
      }

    let processed =
      symbols
      .dropFirst(drop)
      .prefix(limit)
      .enumerated()
      .map { (index, line) -> String in
        let components = line.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let mangledSymbol = components.first(where: { $0.hasPrefix("$s") }) else {
          return "    #\(index) \(line)"
        }
        let demangled = _stdlib_demangleName(mangledSymbol)
        let cleaned = _cleanStackSymbol(demangled)
        return "    #\(index) \(cleaned)"
      }

    return processed
  }

  // MARK: - Internal Helpers

  private static func _stdlib_demangleName(_ mangledName: String) -> String {
    guard let cString = mangledName.cString(using: .utf8) else { return mangledName }
    guard
      let demangledPtr = swift_demangle(
        cString,
        UInt(cString.count - 1),
        nil,
        nil,
        0
      )
    else {
      return mangledName
    }
    defer { free(demangledPtr) }
    return String(cString: demangledPtr)
  }

  private static func _cleanStackSymbol(_ symbol: String) -> String {
    var result = symbol
    result = _regexReplace(
      result,
      pattern: #"(\(\d+\) )?await resume partial function for "#,
      replacement: ""
    )
    result = _regexReplace(
      result,
      pattern: #"(\(\d+\) )?suspend resume partial function for "#,
      replacement: ""
    )
    result = _regexReplace(result, pattern: #"partial apply forwarder for "#, replacement: "")
    result = _regexReplace(
      result,
      pattern: #"closure(\s*\(\)\s*(async\s*)?(throws\s*)?->\s*\(\))?\s*in\s*"#,
      replacement: "closure in "
    )
    result = _regexReplace(
      result,
      pattern: #"closure in\s*closure in\s*"#,
      replacement: "closure in "
    )
    return result
  }

  private static func _regexReplace(_ text: String, pattern: String, replacement: String) -> String
  {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(
      in: text,
      options: [],
      range: range,
      withTemplate: replacement
    )
  }

}

@_silgen_name("swift_demangle")
private func swift_demangle(
  _ mangledName: UnsafePointer<CChar>,
  _ mangledNameLength: UInt,
  _ outputBuffer: UnsafeMutablePointer<CChar>?,
  _ outputBufferSize: UnsafeMutablePointer<UInt>?,
  _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
