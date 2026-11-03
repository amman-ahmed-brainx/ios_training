/// Decides when a form shows a field's error: after the user leaves the field or tries to submit,
/// never while they are typing into a fresh form.
struct InlineValidation<Field: Hashable & Sendable>: Sendable {
    private var touched: Set<Field> = []
    private(set) var hasAttemptedSubmit = false

    mutating func didEndEditing(_ field: Field) {
        touched.insert(field)
    }

    mutating func didAttemptSubmit() {
        hasAttemptedSubmit = true
    }

    /// The message to show for `field`, or `nil` if it is valid or not yet due.
    func message(for field: Field, _ error: ValidationError?) -> String? {
        guard hasAttemptedSubmit || touched.contains(field) else { return nil }
        return error?.message
    }
}
