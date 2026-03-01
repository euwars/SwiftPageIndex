#if canImport(PDFKit)
  import PDFKit
#endif
import Foundation
import SwiftPDF

public struct PDFParser: DocumentParser {
  public let documentType: DocumentType = .pdf
  private let llm: PageIndexLLM?

  public init(llm: PageIndexLLM? = nil) {
    self.llm = llm
  }

  public func canParse(content: Data, mimeType: String?) -> Bool {
    if let mimeType, mimeType.contains("pdf") {
      return true
    }
    if content.count >= 5 {
      let header = String(data: content.prefix(5), encoding: .utf8)
      return header == "%PDF-"
    }
    return false
  }

  public func parse(content: Data, sourceURL: String?) async throws -> ParsedDocument {
    var pageTexts: [String] = []
    var allSections: [DocumentSection] = []
    var pageCount = 0

    #if canImport(PDFKit)
      if let pdfDoc = PDFDocument(data: content) {
        pageCount = pdfDoc.pageCount
        for pageIndex in 0 ..< pageCount {
          guard let page = pdfDoc.page(at: pageIndex) else { continue }
          let text = page.string ?? ""
          pageTexts.append(text)
        }
      }
    #endif

    // If PDFKit unavailable or failed, try SwiftPDF for page count
    if pageTexts.isEmpty {
      let pdf = SwiftPDF.PDF()
      pageCount = try pdf.pageCount(in: content)
      // SwiftPDF only splits, doesn't extract text — pages will be empty strings
      for _ in 0 ..< pageCount {
        pageTexts.append("")
      }
    }

    let fullText = pageTexts.joined(separator: "\u{0C}")
    allSections = extractPDFSections(fullText)
    let title = extractTitleFromContent(pageTexts.first ?? fullText)

    return ParsedDocument(
      content: fullText,
      metadata: DocumentMetadata(
        title: title,
        pageCount: pageCount,
        wordCount: countWords(fullText),
        sourceUrl: sourceURL,
        documentType: .pdf,
      ),
      sections: allSections,
    )
  }

  private func extractPDFSections(_ text: String) -> [DocumentSection] {
    var sections: [DocumentSection] = []
    let lines = text.components(separatedBy: "\n")
    var currentIndex = 0
    var lineNumber = 0

    for line in lines {
      lineNumber += 1
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      let isAllCaps = trimmed.count > 3
        && trimmed == trimmed.uppercased()
        && trimmed.range(of: #"^[A-Z\s\d]+$"#, options: .regularExpression) != nil

      let numberedMatch = trimmed.range(
        of: #"^(\d+\.|\d+\.\d+|(?i)chapter\s+\d+|(?i)section\s+\d+)"#,
        options: .regularExpression,
      )

      if isAllCaps || numberedMatch != nil {
        var level = 1
        if trimmed.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil { level = 3 }
        else if trimmed.range(of: #"^\d+\.\d+"#, options: .regularExpression) != nil { level = 2 }

        sections.append(DocumentSection(
          level: level,
          title: cleanTitle(trimmed),
          content: "",
          startIndex: currentIndex,
          endIndex: currentIndex + line.count,
          lineNumber: lineNumber,
        ))
      }
      currentIndex += line.count + 1
    }

    fillSectionContent(&sections, text: text)
    return sections
  }

  private func cleanTitle(_ title: String) -> String {
    var result = title
    let patterns = [
      #"^\d+\.\d+\.\d+\s*"#,
      #"^\d+\.\d+\s*"#,
      #"^\d+\.\s*"#,
      #"(?i)^chapter\s+\d+\s*[:.\-]?\s*"#,
      #"(?i)^section\s+\d+\s*[:.\-]?\s*"#,
    ]
    for pattern in patterns {
      if let range = result.range(of: pattern, options: .regularExpression) {
        result = String(result[range.upperBound...])
      }
    }
    return result.trimmingCharacters(in: .whitespaces)
  }

  private func fillSectionContent(_ sections: inout [DocumentSection], text: String) {
    for i in 0 ..< sections.count {
      let nextStart = i + 1 < sections.count ? sections[i + 1].startIndex : text.count
      let contentStart = sections[i].endIndex + 1
      if contentStart < nextStart, contentStart < text.count {
        let start = text.index(text.startIndex, offsetBy: min(contentStart, text.count))
        let end = text.index(text.startIndex, offsetBy: min(nextStart, text.count))
        sections[i].content = String(text[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      sections[i].endIndex = nextStart
    }
  }

  private func extractTitleFromContent(_ text: String) -> String {
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.count > 3, trimmed.count < 200 {
        return trimmed
      }
    }
    return "Untitled Document"
  }
}
