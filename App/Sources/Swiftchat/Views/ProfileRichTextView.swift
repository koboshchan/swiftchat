import AppKit
import SwiftUI

struct ProfileRichTextView: View {
    let source: String
    @State private var emojiImages: [String: NSImage] = [:]

    var body: some View {
        ProfileTextRepresentable(source: source, emojiImages: emojiImages)
            .task(id: source) {
                emojiImages = [:]
                for emoji in EmojiDescriptor.all(in: source) {
                    let fileExtension = emoji.isAnimated ? "gif" : "png"
                    guard let url = URL(string: "https://cdn.discordapp.com/emojis/\(emoji.id).\(fileExtension)?size=48&quality=lossless"),
                          let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false,
                          let image = NSImage(data: data) else { continue }
                    emojiImages[emoji.id] = image
                }
            }
    }
}

struct ProfileStatusTextView: View {
    let source: String
    let isExpanded: Bool
    var fontSize: CGFloat = 14
    var usesSecondaryColor = false
    @State private var emojiImages: [String: NSImage] = [:]

    var body: some View {
        ProfileStatusTextRepresentable(
            source: source,
            emojiImages: emojiImages,
            isExpanded: isExpanded,
            fontSize: fontSize,
            usesSecondaryColor: usesSecondaryColor
        )
        .task(id: source) {
            emojiImages = [:]
            for emoji in EmojiDescriptor.all(in: source) {
                let fileExtension = emoji.isAnimated ? "gif" : "png"
                guard let url = URL(string: "https://cdn.discordapp.com/emojis/\(emoji.id).\(fileExtension)?size=48&quality=lossless"),
                      let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false,
                      let image = NSImage(data: data) else { continue }
                emojiImages[emoji.id] = image
            }
        }
    }
}

private struct EmojiDescriptor: Hashable {
    let id: String
    let name: String
    let isAnimated: Bool

    static func all(in source: String) -> [EmojiDescriptor] {
        let expression = try? NSRegularExpression(pattern: #"<(a?):([A-Za-z0-9_~]+):([0-9]+)>"#)
        let sourceString = source as NSString
        let range = NSRange(location: 0, length: sourceString.length)
        return expression?.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges == 4 else { return nil }
            return EmojiDescriptor(
                id: sourceString.substring(with: match.range(at: 3)),
                name: sourceString.substring(with: match.range(at: 2)),
                isAnimated: match.range(at: 1).length > 0
            )
        } ?? []
    }
}

private struct ProfileStatusTextRepresentable: NSViewRepresentable {
    let source: String
    let emojiImages: [String: NSImage]
    let isExpanded: Bool
    let fontSize: CGFloat
    let usesSecondaryColor: Bool

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textContainer?.maximumNumberOfLines = isExpanded ? 0 : 1
        textView.textContainer?.lineBreakMode = isExpanded ? .byWordWrapping : .byTruncatingTail
        textView.textStorage?.setAttributedString(attributedText())
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: NSTextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? (isExpanded ? 188 : 143)
        textView.frame.size.width = width
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return CGSize(width: width, height: fontSize + 3)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        return CGSize(width: width, height: max(fontSize + 3, usedHeight))
    }

    private func attributedText() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let sourceString = source as NSString
        let expression = try? NSRegularExpression(pattern: #"<(a?):([A-Za-z0-9_~]+):([0-9]+)>"#)
        let matches = expression?.matches(
            in: source,
            range: NSRange(location: 0, length: sourceString.length)
        ) ?? []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output.append(styledText(sourceString.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                ))))
            }
            let name = sourceString.substring(with: match.range(at: 2))
            let id = sourceString.substring(with: match.range(at: 3))
            if let sourceImage = emojiImages[id], let image = sourceImage.copy() as? NSImage {
                image.size = NSSize(width: fontSize + 2, height: fontSize + 2)
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                output.append(NSAttributedString(attachment: attachment))
            } else {
                output.append(styledText(":\(name):"))
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < sourceString.length {
            output.append(styledText(sourceString.substring(from: cursor)))
        }
        return output
    }

    private func styledText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: usesSecondaryColor ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
        )
    }
}

private struct ProfileTextRepresentable: NSViewRepresentable {
    let source: String
    let emojiImages: [String: NSImage]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HoverLinkTextView {
        let textView = HoverLinkTextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: 0,
        ]
        return textView
    }

    func updateNSView(_ textView: HoverLinkTextView, context: Context) {
        textView.textStorage?.setAttributedString(attributedText())
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: HoverLinkTextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? 298
        textView.frame.size.width = width
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return CGSize(width: width, height: 20)
        }
        layoutManager.ensureLayout(for: textContainer)
        return CGSize(width: width, height: max(18, ceil(layoutManager.usedRect(for: textContainer).height)))
    }

    private func attributedText() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let sourceString = source as NSString
        let expression = try? NSRegularExpression(pattern: #"<(a?):([A-Za-z0-9_~]+):([0-9]+)>"#)
        let matches = expression?.matches(
            in: source,
            range: NSRange(location: 0, length: sourceString.length)
        ) ?? []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output.append(styledText(sourceString.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let name = sourceString.substring(with: match.range(at: 2))
            let id = sourceString.substring(with: match.range(at: 3))
            if let sourceImage = emojiImages[id], let image = sourceImage.copy() as? NSImage {
                image.size = NSSize(width: 18, height: 18)
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                output.append(NSAttributedString(attachment: attachment))
            } else {
                output.append(styledText(":\(name):"))
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < sourceString.length {
            output.append(styledText(sourceString.substring(from: cursor)))
        }
        styleLinks(in: output)
        return output
    }

    private func styledText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    private func styleLinks(in value: NSMutableAttributedString) {
        let expression = try? NSRegularExpression(pattern: #"https?://[^\s<>]+"#, options: .caseInsensitive)
        let fullString = value.string as NSString
        let matches = expression?.matches(
            in: value.string,
            range: NSRange(location: 0, length: fullString.length)
        ) ?? []
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}")
        for match in matches {
            var range = match.range
            while range.length > 0 {
                let last = fullString.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1))
                guard last.rangeOfCharacter(from: trailingPunctuation) != nil else { break }
                range.length -= 1
            }
            guard range.length > 0,
                  let url = URL(string: fullString.substring(with: range)) else { continue }
            value.addAttributes([.link: url, .foregroundColor: NSColor.systemBlue], range: range)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}

private final class HoverLinkTextView: NSTextView {
    private var tracking: NSTrackingArea?
    private var underlinedRange: NSRange?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let layoutManager, let textContainer, let textStorage else { return }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else {
            updateUnderline(nil)
            return
        }
        var linkRange = NSRange(location: 0, length: 0)
        if textStorage.attribute(.link, at: characterIndex, effectiveRange: &linkRange) != nil {
            updateUnderline(linkRange)
            NSCursor.pointingHand.set()
        } else {
            updateUnderline(nil)
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateUnderline(nil)
    }

    private func updateUnderline(_ range: NSRange?) {
        guard range != underlinedRange else { return }
        if let underlinedRange {
            layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: underlinedRange)
        }
        underlinedRange = range
        if let range {
            layoutManager?.addTemporaryAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                forCharacterRange: range
            )
        }
    }
}
