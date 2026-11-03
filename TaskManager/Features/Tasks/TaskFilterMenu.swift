import SwiftUI

/// Toolbar menu for the list's filters and sort order.
struct TaskFilterMenu: View {
    @Binding var query: TaskQuery

    var body: some View {
        Menu {
            Picker("Sort By", selection: $query.sort) {
                ForEach(TaskQuery.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Show", selection: $query.ownership) {
                ForEach(TaskQuery.Ownership.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Status", selection: $query.status) {
                Text("Any Status").tag(TaskStatus?.none)
                ForEach(TaskStatus.allCases, id: \.self) { Text($0.title).tag(TaskStatus?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Priority", selection: $query.priority) {
                Text("Any Priority").tag(TaskPriority?.none)
                ForEach(TaskPriority.allCases, id: \.self) { Text($0.title).tag(TaskPriority?.some($0)) }
            }
            .pickerStyle(.menu)
            Picker("Due", selection: $query.due) {
                ForEach(TaskQuery.DueFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            if query.hasActiveFilters {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    query = TaskQuery(searchText: query.searchText, sort: query.sort)
                }
            }
        } label: {
            Label(
                "Filter and Sort",
                systemImage: query.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityValue(query.hasActiveFilters ? Text("Filters on") : Text("No filters"))
        .accessibilityIdentifier("taskList.filter")
    }
}
