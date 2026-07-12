import Foundation
import SwiftUI

public enum DiscordMarkdown {
    public static func attributed(_ source: String) -> AttributedString {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var output = AttributedString()

        for (index, rawLine) in lines.enumerated() {
            if index > 0 { output.append(AttributedString("\n")) }
            let (text, headingLevel) = heading(in: String(rawLine))
            var line = (try? AttributedString(
                markdown: text,
                options: .init(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )) ?? AttributedString(text)

            if let headingLevel {
                line.font = switch headingLevel {
                case 1: .title2.bold()
                case 2: .title3.bold()
                default: .headline
                }
            }
            styleInlineCode(in: &line)
            output.append(line)
        }
        return output
    }

    private static func heading(in line: String) -> (String, Int?) {
        if line.hasPrefix("### ") { return (String(line.dropFirst(4)), 3) }
        if line.hasPrefix("## ") { return (String(line.dropFirst(3)), 2) }
        if line.hasPrefix("# ") { return (String(line.dropFirst(2)), 1) }
        return (line, nil)
    }

    private static func styleInlineCode(in value: inout AttributedString) {
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true {
            value[run.range].font = .system(.body, design: .monospaced)
            value[run.range].backgroundColor = Color.secondary.opacity(0.16)
        }
    }
}
