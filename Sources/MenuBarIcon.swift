import SwiftUI

/// The glyph shown in the menu bar. The user picks one; `ClaudetteApp` renders
/// it (varying by session state for SF Symbol icons) and persists the choice.
enum MenuBarIcon: String, CaseIterable, Identifiable {
    case robot
    case ant
    case sparkles
    case brain
    case bolt
    case terminal

    var id: String { rawValue }

    /// Human-readable name for the picker.
    var label: String {
        switch self {
        case .robot:    return "Robot"
        case .ant:      return "Ant"
        case .sparkles: return "Sparkles"
        case .brain:    return "Brain"
        case .bolt:     return "Bolt"
        case .terminal: return "Terminal"
        }
    }

    /// Emoji-based icons render as text (no SF Symbol exists for them).
    /// `nil` means the icon is drawn from `symbol(needsInput:working:)`.
    var emoji: String? {
        switch self {
        case .robot: return "🤖"
        default:     return nil
        }
    }

    /// SF Symbol name reflecting the most urgent session state.
    /// Returns `nil` for emoji-based icons.
    func symbol(needsInput: Bool, working: Bool) -> String? {
        switch self {
        case .robot:
            return nil
        case .ant:
            if needsInput { return "exclamationmark.bubble.fill" }
            return working ? "ant.fill" : "ant"
        case .sparkles:
            return "sparkles"
        case .brain:
            return working ? "brain.head.profile.fill" : "brain.head.profile"
        case .bolt:
            if needsInput { return "bolt.trianglebadge.exclamationmark.fill" }
            return working ? "bolt.fill" : "bolt"
        case .terminal:
            return working ? "terminal.fill" : "terminal"
        }
    }

    /// SF Symbol used to preview the icon inside the picker (state-independent).
    /// Emoji-based icons preview via `emoji` instead.
    var previewSymbol: String? {
        switch self {
        case .robot:    return nil
        case .ant:      return "ant.fill"
        case .sparkles: return "sparkles"
        case .brain:    return "brain.head.profile"
        case .bolt:     return "bolt.fill"
        case .terminal: return "terminal.fill"
        }
    }
}
