import SwiftUI

/// One task in the list: title, status, priority, due date and sync state.
/// Read by VoiceOver as a single element.
struct TaskRow: View {
    let task: TaskItem
    let isOverdue: Bool
    let isShared: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? Palette.secondaryText : Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Spacer(minLength: 0)
                if task.syncState.isPending {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityHidden(true)
                }
            }

            // Wraps onto several lines at large text sizes instead of truncating.
            let metaLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Spacing.small))
            metaLayout {
                StatusBadge(status: task.status)
                PriorityBadge(priority: task.priority)
                if let dueDate = task.dueDate {
                    Label {
                        Text(dueDate, format: .dateTime.day().month(.abbreviated).hour().minute())
                    } icon: {
                        Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Palette.danger : Palette.secondaryText)
                }
                if isShared {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(task.title))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        var parts = [task.status.title, String(localized: "\(task.priority.title) priority")]
        if let dueDate = task.dueDate {
            let formatted = dueDate.formatted(date: .abbreviated, time: .shortened)
            parts.append(isOverdue ? String(localized: "Overdue, was due \(formatted)") : String(localized: "Due \(formatted)"))
        }
        if isShared { parts.append(String(localized: "Shared with you")) }
        if task.syncState.isPending { parts.append(String(localized: "Waiting to sync")) }
        return Text(parts.joined(separator: ", "))
    }
}

#if DEBUG
#Preview("Rows") {
    List {
        TaskRow(task: .preview(title: "Write the quarterly report", status: .inProgress, priority: .high), isOverdue: true, isShared: false)
        TaskRow(task: .preview(title: "Buy milk", status: .done, priority: .low), isOverdue: false, isShared: true)
        TaskRow(task: .preview(title: "Plan team offsite", dueDate: nil), isOverdue: false, isShared: false)
    }
}

#Preview("Rows, dark AX5") {
    List {
        TaskRow(task: .preview(title: "Write the quarterly report", status: .inProgress, priority: .high), isOverdue: true, isShared: true)
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
#endif
