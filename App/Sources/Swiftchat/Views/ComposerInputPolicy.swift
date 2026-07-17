enum ComposerReturnAction: Equatable {
    case send
    case newline
    case inputMethod

    static func decide(
        sendWithReturn: Bool,
        shift: Bool,
        command: Bool,
        hasMarkedText: Bool
    ) -> Self {
        if hasMarkedText { return .inputMethod }
        if shift { return .newline }
        if sendWithReturn || command { return .send }
        return .newline
    }
}
