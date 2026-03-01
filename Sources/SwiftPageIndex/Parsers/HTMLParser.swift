import Foundation
import SwiftSoup

public struct HTMLParser: DocumentParser {
  public let documentType: DocumentType = .html

  public init() {}

  public func canParse(content: Data, mimeType: String?) -> Bool {
    if let mimeType, mimeType.contains("html") {
      return true
    }
    guard let text = String(data: content.prefix(1000), encoding: .utf8) else { return false }
    let patterns = ["<!doctype\\s+html", "<html", "<head", "<body"]
    return patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
  }

  public func parse(content: Data, sourceURL: String?) async throws -> ParsedDocument {
    let html = String(data: content, encoding: .utf8) ?? ""
    let doc = try SwiftSoup.parse(html)

    // Remove non-content elements
    for selector in ["script", "style", "nav", "footer", "header", "aside", "noscript", "iframe"] {
      try doc.select(selector).remove()
    }

    let title = try doc.select("title").first()?.text().trimmingCharacters(in: .whitespaces)
      ?? doc.select("h1").first()?.text().trimmingCharacters(in: .whitespaces)
      ?? "Untitled Document"

    let markdownContent = try htmlToMarkdown(doc)
    let sections = try extractHTMLSections(doc)

    return ParsedDocument(
      content: markdownContent,
      metadata: DocumentMetadata(
        title: title,
        wordCount: countWords(markdownContent),
        sourceUrl: sourceURL,
        documentType: .html,
      ),
      sections: sections,
    )
  }

  private func htmlToMarkdown(_ doc: Document) throws -> String {
    var lines: [String] = []
    let body = try doc.select("body").first() ?? doc

    let elements = try body.select("h1, h2, h3, h4, h5, h6, p, li, blockquote, pre, code, div")

    for element in elements {
      let tagName = element.tagName().lowercased()

      // Skip containers that have child headers
      if !tagName.hasPrefix("h"),
         try !element.select("h1, h2, h3, h4, h5, h6").isEmpty()
      {
        continue
      }

      var text = ""
      if tagName.hasPrefix("h"), let levelChar = tagName.last, let level = Int(String(levelChar)) {
        let hashes = String(repeating: "#", count: level)
        text = try "\(hashes) \(element.text().trimmingCharacters(in: .whitespaces))"
      } else if tagName == "li" {
        text = try "- \(element.text().trimmingCharacters(in: .whitespaces))"
      } else if tagName == "blockquote" {
        text = try "> \(element.text().trimmingCharacters(in: .whitespaces))"
      } else if tagName == "pre" || tagName == "code" {
        text = try "```\n\(element.text().trimmingCharacters(in: .whitespaces))\n```"
      } else if tagName == "p" || tagName == "div" {
        // Get direct text by getting own text nodes only
        let directText = try element.ownText().trimmingCharacters(in: .whitespaces)
        if !directText.isEmpty {
          text = directText
        }
      }

      if !text.trimmingCharacters(in: .whitespaces).isEmpty {
        lines.append(text)
      }
    }

    // Deduplicate
    var seen = Set<String>()
    var uniqueLines: [String] = []
    for line in lines {
      let normalized = line.trimmingCharacters(in: .whitespaces).lowercased()
      if !seen.contains(normalized), !line.trimmingCharacters(in: .whitespaces).isEmpty {
        seen.insert(normalized)
        uniqueLines.append(line)
      }
    }

    return uniqueLines.joined(separator: "\n\n")
  }

  private func extractHTMLSections(_ doc: Document) throws -> [DocumentSection] {
    var sections: [DocumentSection] = []
    let body = try doc.select("body").first() ?? doc
    let fullText = try body.text()
    var lineNumber = 0

    let headers = try body.select("h1, h2, h3, h4, h5, h6")

    for header in headers {
      let tagName = header.tagName().lowercased()
      guard tagName.hasPrefix("h"), let levelChar = tagName.last, let level = Int(String(levelChar)) else {
        continue
      }

      let title = try header.text().trimmingCharacters(in: .whitespaces)
      guard !title.isEmpty else { continue }

      lineNumber += 1

      // Collect content until next header
      var content = ""
      var sibling = try header.nextElementSibling()
      while let sib = sibling {
        let sibTag = sib.tagName().lowercased()
        if sibTag.hasPrefix("h"), sibTag.count == 2,
           let _ = Int(String(sibTag.last!))
        {
          break
        }
        let sibText = try sib.text().trimmingCharacters(in: .whitespaces)
        if !sibText.isEmpty {
          content += sibText + "\n"
        }
        sibling = try sib.nextElementSibling()
      }

      let startIndex = fullText.range(of: title)
        .map { fullText.distance(from: fullText.startIndex, to: $0.lowerBound) } ?? 0

      sections.append(DocumentSection(
        level: level,
        title: title,
        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
        startIndex: max(0, startIndex),
        endIndex: max(startIndex + 1, startIndex + title.count + content.count),
        lineNumber: lineNumber,
      ))
    }

    return sections
  }
}
