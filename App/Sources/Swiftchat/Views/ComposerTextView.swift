import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    let text: String
    let placeholder: String
    let sendWithReturn: Bool
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void
    @Binding var selection: NSRange?
    @Binding var isFocused: Bool

    private let maximumHeight: CGFloat = 150
    private let font = NSFont.systemFont(ofSize: 15)

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = ComposerNSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.font = font
        textView.textColor = .labelColor
        textView.typingAttributes = textAttributes
        textView.setAccessibilityLabel(placeholder)
        textView.onReturn = { [weak coordinator = context.coordinator] event in
            coordinator?.handleReturn(event) ?? false
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        context.coordinator.parent = self

        textView.onReturn = { [weak coordinator = context.coordinator] event in
            coordinator?.handleReturn(event) ?? false
        }
        textView.setAccessibilityLabel(placeholder)

        if textView.string != text {
            textView.string = text
            textView.font = font
            textView.textColor = .labelColor
            textView.typingAttributes = textAttributes

            if selection == nil {
                textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
            }
        }

        if let selection,
           selection.location != NSNotFound,
           NSMaxRange(selection) <= textView.string.utf16.count,
           textView.selectedRange() != selection
        {
            textView.setSelectedRange(selection)
        }

        context.coordinator.applyFocus(to: textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView scrollView: NSScrollView,
        context: Context
    ) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return nil
        }

        let proposedWidth = proposal.width ?? scrollView.bounds.width
        guard proposedWidth > 0 else { return nil }

        layoutManager.ensureLayout(for: textContainer)

        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let contentHeight = ceil(max(lineHeight, layoutManager.usedRect(for: textContainer).height))

        return CGSize(width: proposedWidth, height: min(contentHeight, maximumHeight))
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        private var appliedFocus = false

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            appliedFocus = true
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            appliedFocus = false
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.onTextChange(textView.string)
            }
            updateSelection(from: textView)
            textView.invalidateIntrinsicContentSize()
            textView.enclosingScrollView?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateSelection(from: textView)
        }

        func applyFocus(to textView: NSTextView) {
            guard parent.isFocused != appliedFocus else { return }
            appliedFocus = parent.isFocused

            if parent.isFocused {
                Task { @MainActor [weak textView] in
                    guard let textView, parent.isFocused else { return }
                    textView.window?.makeFirstResponder(textView)
                }
            } else if textView.window?.firstResponder === textView {
                textView.window?.makeFirstResponder(nil)
            }
        }

        func handleReturn(_ event: NSEvent) -> Bool {
            let action = ComposerReturnAction.decide(
                sendWithReturn: parent.sendWithReturn,
                shift: event.modifierFlags.contains(.shift),
                command: event.modifierFlags.contains(.command),
                hasMarkedText: (event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true
            )

            switch action {
            case .send:
                parent.onSubmit()
                return true
            case .newline, .inputMethod:
                return false
            }
        }

        private func updateSelection(from textView: NSTextView) {
            let newSelection = textView.selectedRange()
            if parent.selection != newSelection {
                parent.selection = newSelection
            }
        }
    }
}

private final class ComposerNSTextView: NSTextView {
    var onReturn: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, onReturn?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
