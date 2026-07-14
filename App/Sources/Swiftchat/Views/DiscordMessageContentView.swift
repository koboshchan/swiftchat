import MessageRendering
import SwiftUI

struct DiscordMessageContentView: View {
    let content: String

    private let presentation: LinkedImagePresentation

    init(content: String) {
        self.content = content
        presentation = LinkedImagePresentation(content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !presentation.visibleText.isEmpty {
                CustomEmojiRichText(content: presentation.visibleText, emojiSize: 22)
            }
            ForEach(presentation.images) { image in
                LinkedMessageImage(image: image)
            }
        }
    }
}

struct CustomEmojiRichText: View {
    let content: String
    let emojiSize: CGFloat

    private let segments: [DiscordMessageSegment]

    init(content: String, emojiSize: CGFloat) {
        self.content = content
        self.emojiSize = emojiSize
        segments = DiscordMessageSegment.parse(content)
    }

    var body: some View {
        EmojiWrappingLayout(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(segments) { segment in
                DiscordMessageSegmentView(segment: segment, emojiSize: emojiSize)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CustomEmojiGlyph: View {
    let token: String
    let size: CGFloat

    var body: some View {
        if let emoji = ParsedCustomEmoji(token: token), let url = emoji.imageURL {
            AnimatedRemoteImage(url: url)
                .frame(width: size, height: size)
                .help(":\(emoji.name):")
                .accessibilityLabel(emoji.name)
        } else {
            Text(token)
        }
    }
}

private struct DiscordMessageSegmentView: View {
    let segment: DiscordMessageSegment
    let emojiSize: CGFloat

    var body: some View {
        ZStack {
            switch segment.content {
            case let .text(value):
                MessageBodyView(content: value)
            case let .customEmoji(token):
                CustomEmojiGlyph(token: token, size: emojiSize)
            }
        }
    }
}

private struct LinkedMessageImage: View {
    let image: LinkedImageReference

    var body: some View {
        Link(destination: image.url) {
            AnimatedRemoteImage(url: image.url)
                .frame(width: image.isEmoji ? 48 : 360, height: image.isEmoji ? 48 : 220)
                .background(image.isEmoji ? Color.clear : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: image.isEmoji ? 7 : 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(image.label)
    }
}

struct ParsedCustomEmoji {
    let name: String
    let id: String
    let isAnimated: Bool

    init?(token: String) {
        let pattern = #"^<(a?):([A-Za-z0-9_]+):([0-9]+)>$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = regex.firstMatch(in: token, range: fullRange),
              let animationRange = Range(match.range(at: 1), in: token),
              let nameRange = Range(match.range(at: 2), in: token),
              let idRange = Range(match.range(at: 3), in: token) else { return nil }
        isAnimated = token[animationRange] == "a"
        name = String(token[nameRange])
        id = String(token[idRange])
    }

    var imageURL: URL? {
        URL(string: "https://cdn.discordapp.com/emojis/\(id).webp?size=96&animated=\(isAnimated ? "true" : "false")")
    }
}

private struct DiscordMessageSegment: Identifiable {
    enum Content {
        case text(String)
        case customEmoji(String)
    }

    let id: Int
    let content: Content

    static func parse(_ source: String) -> [DiscordMessageSegment] {
        let regex = try! NSRegularExpression(pattern: #"<a?:[A-Za-z0-9_]+:[0-9]+>"#)
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: sourceRange)
        guard !matches.isEmpty else { return [.init(id: 0, content: .text(source))] }

        var result: [DiscordMessageSegment] = []
        var cursor = source.startIndex
        for match in matches {
            guard let range = Range(match.range, in: source) else { continue }
            if cursor < range.lowerBound {
                result.append(.init(id: result.count, content: .text(String(source[cursor..<range.lowerBound]))))
            }
            result.append(.init(id: result.count, content: .customEmoji(String(source[range]))))
            cursor = range.upperBound
        }
        if cursor < source.endIndex {
            result.append(.init(id: result.count, content: .text(String(source[cursor...]))))
        }
        return result
    }
}

private struct LinkedImagePresentation {
    let visibleText: String
    let images: [LinkedImageReference]

    init(content: String) {
        let regex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\((https://[^\s)]+)\)"#)
        let sourceRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let references = regex.matches(in: content, range: sourceRange).compactMap { match -> (NSRange, LinkedImageReference)? in
            guard
                let fullRange = Range(match.range(at: 0), in: content),
                let labelRange = Range(match.range(at: 1), in: content),
                let urlRange = Range(match.range(at: 2), in: content),
                let url = URL(string: String(content[urlRange])),
                LinkedImageReference.isSupported(url)
            else { return nil }
            return (match.range(at: 0), LinkedImageReference(
                id: "\(match.range(at: 0).location):\(content[fullRange])",
                label: String(content[labelRange]),
                url: url
            ))
        }
        images = references.map(\.1)
        if references.count == 1,
           let range = Range(references[0].0, in: content),
           content.trimmingCharacters(in: .whitespacesAndNewlines) == String(content[range]) {
            visibleText = ""
        } else {
            visibleText = content
        }
    }
}

private struct LinkedImageReference: Identifiable {
    let id: String
    let label: String
    let url: URL

    var isEmoji: Bool { url.host == "cdn.discordapp.com" && url.path.hasPrefix("/emojis/") }

    static func isSupported(_ url: URL) -> Bool {
        let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "avif"])
        return imageExtensions.contains(url.pathExtension.lowercased())
            || (url.host == "cdn.discordapp.com" && url.path.hasPrefix("/emojis/"))
    }
}

private struct EmojiWrappingLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.positions.enumerated() where subviews.indices.contains(index) {
            let size = result.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        let maximumWidth = proposal.width ?? 640
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize(width: max(1, maximumWidth - x), height: nil))
            if x > 0, size.width > maximumWidth - x {
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
                size = subview.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil))
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, min(maximumWidth, x - horizontalSpacing))
        }
        return (CGSize(width: proposal.width ?? usedWidth, height: y + lineHeight), positions, sizes)
    }
}
