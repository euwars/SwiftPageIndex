import Foundation

public struct TextParser: DocumentParser {
  public let documentType: DocumentType = .text

  public init() {}

  public func canParse(content: Data, mimeType: String?) -> Bool {
    if let mimeType, mimeType.contains("text/plain") {
      return true
    }
    // Check for binary content
    guard let text = String(data: content.prefix(1000), encoding: .utf8) else { return false }
    let binaryPattern = "[\\x00-\\x08\\x0E-\\x1F]"
    return text.range(of: binaryPattern, options: .regularExpression) == nil
  }

  public func parse(content: Data, sourceURL: String?) async throws -> ParsedDocument {
    let text = String(data: content, encoding: .utf8) ?? ""
    let sections = extractTextSections(text)
    let title = extractTitle(text)

    return ParsedDocument(
      content: text,
      metadata: DocumentMetadata(
        title: title,
        wordCount: countWords(text),
        sourceUrl: sourceURL,
        documentType: .text,
      ),
      sections: sections,
    )
  }

  private func extractTextSections(_ text: String) -> [DocumentSection] {
    var sections: [DocumentSection] = []
    let lines = text.components(separatedBy: "\n")
    var currentIndex = 0

    for lineNumber in 0 ..< lines.count {
      let line = lines[lineNumber]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // ALL CAPS headers
      if isAllCapsHeader(trimmed) {
        sections.append(DocumentSection(
          level: 1,
          title: titleCase(trimmed),
          content: "",
          startIndex: currentIndex,
          endIndex: currentIndex + line.count,
          lineNumber: lineNumber + 1,
        ))
      }

      // Underlined headers
      if lineNumber < lines.count - 1 {
        let nextLine = lines[lineNumber + 1].trimmingCharacters(in: .whitespaces)
        if nextLine.range(of: "^=+$", options: .regularExpression) != nil, !trimmed.isEmpty {
          sections.append(DocumentSection(
            level: 1,
            title: trimmed,
            content: "",
            startIndex: currentIndex,
            endIndex: currentIndex + line.count + nextLine.count + 1,
            lineNumber: lineNumber + 1,
          ))
        } else if nextLine.range(of: "^-+$", options: .regularExpression) != nil, !trimmed.isEmpty {
          sections.append(DocumentSection(
            level: 2,
            title: trimmed,
            content: "",
            startIndex: currentIndex,
            endIndex: currentIndex + line.count + nextLine.count + 1,
            lineNumber: lineNumber + 1,
          ))
        }
      }

      // Numbered sections
      if let match = trimmed.range(of: "^(\\d+\\.)+\\s*(.+)$", options: .regularExpression) {
        let matched = String(trimmed[match])
        let dotCount = matched.prefix(while: { $0.isNumber || $0 == "." }).count(where: { $0 == "." })
        let titlePart = trimmed.replacingOccurrences(of: "^(\\d+\\.)+\\s*", with: "", options: .regularExpression)
        sections.append(DocumentSection(
          level: min(dotCount, 6),
          title: titlePart.trimmingCharacters(in: .whitespaces),
          content: "",
          startIndex: currentIndex,
          endIndex: currentIndex + line.count,
          lineNumber: lineNumber + 1,
        ))
      }

      currentIndex += line.count + 1
    }

    let uniqueSections = deduplicateSections(sections)
    var result = uniqueSections
    fillSectionContent(&result, text: text)
    return result
  }

  private func isAllCapsHeader(_ text: String) -> Bool {
    text.count > 3 && text.count < 100
      && text == text.uppercased()
      && text.range(of: "^[A-Z\\s\\d]+$", options: .regularExpression) != nil
      && text.split(separator: " ").count <= 10
  }

  private func titleCase(_ text: String) -> String {
    text.lowercased().capitalized
  }

  private func deduplicateSections(_ sections: [DocumentSection]) -> [DocumentSection] {
    var seen: [Int: DocumentSection] = [:]
    for section in sections {
      if let existing = seen[section.startIndex] {
        if section.title.count > existing.title.count {
          seen[section.startIndex] = section
        }
      } else {
        seen[section.startIndex] = section
      }
    }
    return seen.values.sorted { $0.startIndex < $1.startIndex }
  }

  private func fillSectionContent(_ sections: inout [DocumentSection], text: String) {
    for i in 0 ..< sections.count {
      let nextStart = i + 1 < sections.count ? sections[i + 1].startIndex : text.count
      let contentStart = sections[i].endIndex + 1
      if contentStart < nextStart {
        let start = text.index(text.startIndex, offsetBy: min(contentStart, text.count))
        let end = text.index(text.startIndex, offsetBy: min(nextStart, text.count))
        sections[i].content = String(text[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      sections[i].endIndex = nextStart
    }
  }

  private func extractTitle(_ text: String) -> String {
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.count > 3, trimmed.count < 200 {
        return trimmed
      }
    }
    return "Untitled Document"
  }
}
