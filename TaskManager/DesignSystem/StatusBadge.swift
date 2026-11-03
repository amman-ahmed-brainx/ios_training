import SwiftUI

/// Capsule showing a task's status. Icon plus text, never colour alone.
struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xxs)
            .background(status.tint.opacity(0.12), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Status: \(status.title)"))
    }
}

/// Priority indicator; icon plus text, never colour alone.
struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Label(priority.title, systemImage: priority.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(priority.tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Priority: \(priority.title)"))
    }
}

extension TaskStatus {
    var tint: Color {
        switch self {
        case .todo: Palette.statusTodo
        case .inProgress: Palette.statusInProgress
        case .done: Palette.statusDone
        }
    }
}

extension TaskPriority {
    var tint: Color {
        switch self {
        case .low: Palette.priorityLow
        case .medium: Palette.priorityMedium
        case .high: Palette.priorityHigh
        }
    }
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: Spacing.medium) {
        ForEach(TaskStatus.allCases, id: \.self) { StatusBadge(status: $0) }
        ForEach(TaskPriority.allCases, id: \.self) { PriorityBadge(priority: $0) }
    }
    .padding()
}

#Preview("Badges, dark AX5") {
    VStack(alignment: .leading, spacing: Spacing.medium) {
        ForEach(TaskStatus.allCases, id: \.self) { StatusBadge(status: $0) }
    }
    .padding()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
