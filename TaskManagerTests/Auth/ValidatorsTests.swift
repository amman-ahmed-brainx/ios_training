import Testing
@testable import TaskManager

struct ValidatorsTests {
    @Test(arguments: ["ada@example.com", "  ada.lovelace+tasks@mail.example.co.uk ", "a@b.io"])
    func validEmailsPass(_ email: String) {
        #expect(Validators.email(email) == nil)
    }

    @Test(arguments: ["ada", "ada@", "@example.com", "ada@example", "ada@example.c", "ada @example.com", "a@@b.com"])
    func invalidEmailsFail(_ email: String) {
        #expect(Validators.email(email) == .invalidEmail)
    }

    @Test func blankEmailIsRequired() {
        #expect(Validators.email("   ") == .required)
    }

    @Test func shortPasswordIsRejected() {
        #expect(Validators.newPassword("abc123") == .passwordTooShort(minimum: 8))
    }

    @Test(arguments: ["abcdefgh", "12345678"])
    func passwordNeedsLetterAndDigit(_ password: String) {
        #expect(Validators.newPassword(password) == .passwordNeedsLetterAndDigit)
    }

    @Test func strongPasswordIsAccepted() {
        #expect(Validators.newPassword("Password1") == nil)
    }

    @Test func confirmationMustMatch() {
        #expect(Validators.confirmation("Password2", matches: "Password1") == .passwordsDoNotMatch)
        #expect(Validators.confirmation("Password1", matches: "Password1") == nil)
        #expect(Validators.confirmation("", matches: "Password1") == .required)
    }

    @Test func everyErrorHasAMessage() {
        let errors: [ValidationError] = [
            .required, .invalidEmail, .passwordTooShort(minimum: 8), .passwordNeedsLetterAndDigit, .passwordsDoNotMatch
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
        }
    }
}

struct InlineValidationTests {
    enum Field: Hashable, Sendable { case email, password }

    @Test func errorsStayHiddenUntilTheUserInteracts() {
        let validation = InlineValidation<Field>()
        #expect(validation.message(for: .email, .invalidEmail) == nil)
    }

    @Test func leavingAFieldRevealsOnlyThatField() {
        var validation = InlineValidation<Field>()
        validation.didEndEditing(.email)
        #expect(validation.message(for: .email, .invalidEmail) == ValidationError.invalidEmail.message)
        #expect(validation.message(for: .password, .required) == nil)
    }

    @Test func submittingRevealsEveryField() {
        var validation = InlineValidation<Field>()
        validation.didAttemptSubmit()
        #expect(validation.message(for: .password, .required) == ValidationError.required.message)
        #expect(validation.message(for: .email, nil) == nil)
    }
}
