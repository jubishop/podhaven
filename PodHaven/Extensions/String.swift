import CryptoKit
import Foundation
import RegexBuilder

extension String {
  func hashTo(_ length: Int) -> String {
    guard length > 0 else { return "" }

    let data = self.data(using: .utf8)!
    let hash = SHA256.hash(data: data)
    let hashData = Data(hash)

    let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    let result = (0..<length)
      .map { i in
        let byte = hashData[i % hashData.count]
        let index = Int(byte) % chars.count
        return chars[index]
      }

    return String(result)
  }

  func trimmed() -> String {
    self.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func sha1() -> String {
    Insecure.SHA1.hash(data: Data(self.utf8)).compactMap { String(format: "%02x", $0) }.joined()
  }

  func isHTML() -> Bool {
    self.contains(
      Regex {
        ChoiceOf {
          Regex {
            "</"
          }
          Regex {
            "/>"
          }
        }
      }
    )
  }
}
