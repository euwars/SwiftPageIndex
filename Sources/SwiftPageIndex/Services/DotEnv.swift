import Foundation

enum DotEnv {
  /// Loads key=value pairs from a `.env` file into `ProcessInfo` environment.
  /// Skips comments (#) and blank lines. Does not override existing env vars.
  static func load(path: String = ".env") {
    let url = URL(fileURLWithPath: path)
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }

    for line in contents.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

      guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
      let key = String(trimmed[trimmed.startIndex ..< equalsIndex])
        .trimmingCharacters(in: .whitespaces)
      var value = String(trimmed[trimmed.index(after: equalsIndex)...])
        .trimmingCharacters(in: .whitespaces)

      // Strip surrounding quotes
      if (value.hasPrefix("\"") && value.hasSuffix("\""))
        || (value.hasPrefix("'") && value.hasSuffix("'"))
      {
        value = String(value.dropFirst().dropLast())
      }

      // Only set if not already in environment
      if ProcessInfo.processInfo.environment[key] == nil {
        setenv(key, value, 0)
      }
    }
  }
}
