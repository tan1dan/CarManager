import Foundation

/// Shared ViewModel state. Lives in Application (not Presentation) so ViewModels and their
/// tests share it without Presentation types leaking down. Carries no SwiftUI types.
public enum ViewState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(ErrorPresentation)

    public var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
    public var isLoading: Bool { if case .loading = self { return true }; return false }
    public var error: ErrorPresentation? {
        if case .failed(let e) = self { return e }
        return nil
    }
}

extension ViewState: Equatable where Value: Equatable {}

/// Progress state for the scan / processing flows.
public enum ProcessingState<Value: Sendable>: Sendable {
    case idle
    case processing
    case success(Value)
    case failed(ErrorPresentation)
}

extension ProcessingState: Equatable where Value: Equatable {}

public struct ErrorPresentation: Sendable, Equatable, Identifiable {
    public enum Style: Sendable, Equatable {
        case inline, alert, toast, fullScreen
        case fieldLevel(FieldID)
    }

    public enum RecoveryAction: Sendable, Equatable, Hashable {
        case retry
        case openSettings
        case upgrade(PaywallContext)
        case signIn
        case dismiss
        case contactSupport
    }

    public let id: UUID
    public let titleKey: String
    public let messageKey: String
    public let arguments: [String]
    public let style: Style
    public let actions: [RecoveryAction]

    public init(
        id: UUID = UUID(), titleKey: String, messageKey: String, arguments: [String] = [],
        style: Style = .alert, actions: [RecoveryAction] = [.dismiss]
    ) {
        self.id = id; self.titleKey = titleKey; self.messageKey = messageKey
        self.arguments = arguments; self.style = style; self.actions = actions
    }
}
