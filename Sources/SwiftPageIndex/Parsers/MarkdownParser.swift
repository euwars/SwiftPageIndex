import Foundation

public struct MarkdownParser: DocumentParser {
  public let documentType: DocumentType = .markdown

  public init() {}

  public func canParse(content: Data, mimeType: String?) -> Bool {
    if let mimeType, mimeType.contains("markdown") {
      return true
    }
    guard let text = String(data: content.prefix(2000), encoding: .utf8) else { return false }

    let patterns: [String] = [
      "(?m)^#{1,6}\\s+", // Headers
      "(?m)^\\s*[-*+]\\s+", // Unordered lists
      "(?m)^\\s*\\d+\\.\\s+", // Ordered lists
      "\\[.+\\]\\(.+\\)", // Links
      "```[\\s\\S]*?```", // Code blocks
      "\\*\\*.+\\*\\*", // Bold
    ]

    var matchCount = 0
    for pattern in patterns {
      if text.range(of: pattern, options: .regularExpression) != nil {
        matchCount += 1
      }
    }
    return matchCount >= 2
  }

  public func parse(content: Data, sourceURL: String?) async throws -> ParsedDocument {
    let text = String(data: content, encoding: .utf8) ?? ""
    let sections = extractMarkdownSections(text)
    let title = extractTitle(text, sections: sections)

    return ParsedDocument(
      content: text,
      metadata: DocumentMetadata(
        title: title,
        wordCount: countWords(text),
        sourceUrl: sourceURL,
        documentType: .markdown,
      ),
      sections: sections,
    )
  }

  private func extractMarkdownSections(_ text: String) -> [DocumentSection] {
    var sections: [DocumentSection] = []
    let lines = text.components(separatedBy: "\n")
    let headerRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$")
    var currentIndex = 0

    for lineNumber in 0 ..< lines.count {
      let line = lines[lineNumber]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // ATX headers
      let range = NSRange(trimmed.startIndex..., in: trimmed)
      if let match = headerRegex.firstMatch(in: trimmed, range: range) {
        let hashRange = Range(match.range(at: 1), in: trimmed)!
        let titleRange = Range(match.range(at: 2), in: trimmed)!
        let level = trimmed[hashRange].count
        let title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespaces)

        sections.append(DocumentSection(
          level: level,
          title: title,
          content: "",
          startIndex: currentIndex,
          endIndex: currentIndex + line.count,
          lineNumber: lineNumber + 1,
        ))
      }

      // Setext headers
      if lineNumber > 0 {
        if trimmed.range(of: "^=+$", options: .regularExpression) != nil || trimmed == "===" {
          let prevLine = lines[lineNumber - 1].trimmingCharacters(in: .whitespaces)
          if !prevLine.isEmpty, !prevLine.hasPrefix("#") {
            let prevStart = currentIndex - lines[lineNumber - 1].count - 1
            sections.append(DocumentSection(
              level: 1,
              title: prevLine,
              content: "",
              startIndex: prevStart,
              endIndex: currentIndex + line.count,
              lineNumber: lineNumber,
            ))
          }
        } else if trimmed.range(of: "^-+$", options: .regularExpression) != nil, trimmed.count >= 3 {
          let prevLine = lines[lineNumber - 1].trimmingCharacters(in: .whitespaces)
          if !prevLine.isEmpty, !prevLine.hasPrefix("#") {
            let prevStart = currentIndex - lines[lineNumber - 1].count - 1
            sections.append(DocumentSection(
              level: 2,
              title: prevLine,
              content: "",
              startIndex: prevStart,
              endIndex: currentIndex + line.count,
              lineNumber: lineNumber,
            ))
          }
        }
      }

      currentIndex += line.count + 1
    }

    sections.sort { $0.startIndex < $1.startIndex }
    fillSectionContent(&sections, text: text)
    return sections
  }

  private func fillSectionContent(_ sections: inout [DocumentSection], text: String) {
    for i in 0 ..< sections.count {
      let nextStart = i + 1 < sections.count ? sections[i + 1].startIndex : text.count
      let contentStart = sections[i].endIndex + 1
      if contentStart < nextStart {
        let start = text.index(text.startIndex, offsetBy: min(contentStart, text.count))
        let end = text.index(text.startIndex, offsetBy: min(nextStart, text.count))
        var content = String(text[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
        content = cleanContent(content)
        sections[i].content = content
      }
      sections[i].endIndex = nextStart
    }
  }

  private func cleanContent(_ content: String) -> String {
    var result = content
    // Remove markdown image syntax but keep alt text
    result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]+\\)", with: "[$1]", options: .regularExpression)
    // Simplify bold
    result = result.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
    result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
    // Remove excess newlines
    result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func extractTitle(_ text: String, sections: [DocumentSection]) -> String {
    // First H1
    if let h1 = sections.first(where: { $0.level == 1 }) {
      return h1.title
    }
    // YAML frontmatter title
    if let match = text.range(
      of: "^---\\n[\\s\\S]*?title:\\s*[\"']?([^\"'\\n]+)[\"']?\\n[\\s\\S]*?---",
      options: .regularExpression,
    ) {
      let fullMatch = String(text[match])
      if let titleMatch = fullMatch.range(of: "title:\\s*[\"']?([^\"'\\n]+)[\"']?", options: .regularExpression) {
        let titleLine = String(fullMatch[titleMatch])
        let parts = titleLine.components(separatedBy: ":")
        if parts.count > 1 {
          return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
      }
    }
    // First line
    let firstLine = text.components(separatedBy: "\n").first?
      .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces) ?? ""
    if !firstLine.isEmpty, firstLine.count < 200 {
      return firstLine
    }
    return "Untitled Document"
  }
}
