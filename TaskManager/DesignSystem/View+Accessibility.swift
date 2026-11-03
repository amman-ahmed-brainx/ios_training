import SwiftUI

extension View {
    /// Sets an accessibility identifier only when one is given, so untagged reusable components
    /// don't all share an empty identifier in UI-test queries.
    @ViewBuilder
    func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
