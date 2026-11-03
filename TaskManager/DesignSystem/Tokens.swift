import SwiftUI

/// Spacing scale. Use these instead of literals so layouts stay consistent.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radius scale.
enum Radius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 16
}

/// Layout constants that come from the Human Interface Guidelines.
enum Metrics {
    /// Minimum tappable size for any control.
    static let minHitTarget: CGFloat = 44
}

/// Semantic colours backed by the asset catalog (each has a light and a dark variant).
enum Palette {
    static let accent = Color(.accent)
    static let onAccent = Color(.onAccent)
    static let card = Color(.cardBackground)
    static let danger = Color(.danger)
    static let statusTodo = Color(.statusTodo)
    static let statusInProgress = Color(.statusInProgress)
    static let statusDone = Color(.statusDone)
    static let priorityLow = Color(.priorityLow)
    static let priorityMedium = Color(.priorityMedium)
    static let priorityHigh = Color(.priorityHigh)
}
