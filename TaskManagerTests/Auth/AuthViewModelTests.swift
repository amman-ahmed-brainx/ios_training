import Testing
@testable import TaskManager

@MainActor
struct LoginViewModelTests {
    private let auth = MockAuthService()

    @Test func errorsStayHiddenBeforeInteraction() {
        let model = LoginViewModel(auth: auth)
        #expect(model.emailError == nil)
        #expect(model.passwordError == nil)
    }

    @Test func invalidFormShowsErrorsAndDoesNotCallAuth() async {
        let model = LoginViewModel(auth: auth)
        model.email = "not-an-email"

        await model.submit()

        #expect(model.emailError == ValidationError.invalidEmail.message)
        #expect(model.passwordError == ValidationError.required.message)
        #expect(await auth.signInCalls.isEmpty)
    }

    @Test func leavingTheEmailFieldValidatesItInline() {
        let model = LoginViewModel(auth: auth)
        model.email = "ada@"
        model.didEndEditing(.email)
        #expect(model.emailError == ValidationError.invalidEmail.message)
        #expect(model.passwordError == nil)
    }

    @Test func validFormSignsInWithTrimmedEmail() async {
        let model = LoginViewModel(auth: auth)
        model.email = "  ada@example.com "
        model.password = "Password1"

        await model.submit()

        #expect(await auth.signInCalls == [.init(email: "ada@example.com", password: "Password1")])
        #expect(model.errorMessage == nil)
        #expect(!model.isSubmitting)
    }

    @Test func failureShowsMessageAndStopsLoading() async {
        await auth.failSignIn(with: .wrongCredentials)
        let model = LoginViewModel(auth: auth)
        model.email = "ada@example.com"
        model.password = "wrong"

        await model.submit()

        #expect(model.errorMessage == AuthError.wrongCredentials.errorDescription)
        #expect(!model.isSubmitting)
    }

    @Test func resubmittingClearsThePreviousError() async {
        await auth.failSignIn(with: .network)
        let model = LoginViewModel(auth: auth)
        model.email = "ada@example.com"
        model.password = "Password1"
        await model.submit()
        #expect(model.errorMessage != nil)

        model.email = "bad"
        await model.submit()

        #expect(model.errorMessage == nil)
    }
}

@MainActor
struct SignUpViewModelTests {
    private let auth = MockAuthService()

    private func filledModel() -> SignUpViewModel {
        let model = SignUpViewModel(auth: auth)
        model.displayName = "  Ada Lovelace "
        model.email = "ada@example.com"
        model.password = "Password1"
        model.confirmPassword = "Password1"
        return model
    }

    @Test func mismatchedPasswordsBlockSubmit() async {
        let model = filledModel()
        model.confirmPassword = "Password2"

        await model.submit()

        #expect(model.confirmPasswordError == ValidationError.passwordsDoNotMatch.message)
        #expect(await auth.signUpCalls.isEmpty)
    }

    @Test func weakPasswordShowsTheStrengthRule() async {
        let model = filledModel()
        model.password = "password"
        model.confirmPassword = "password"

        await model.submit()

        #expect(model.passwordError == ValidationError.passwordNeedsLetterAndDigit.message)
        #expect(await auth.signUpCalls.isEmpty)
    }

    @Test func missingNameIsRequired() async {
        let model = filledModel()
        model.displayName = "   "

        await model.submit()

        #expect(model.nameError == ValidationError.required.message)
    }

    @Test func validFormSignsUpWithTrimmedValues() async {
        let model = filledModel()

        await model.submit()

        #expect(await auth.signUpCalls == [.init(email: "ada@example.com", password: "Password1", displayName: "Ada Lovelace")])
        #expect(!model.isSubmitting)
    }

    @Test func existingAccountShowsMessage() async {
        await auth.failSignUp(with: .emailAlreadyInUse)
        let model = filledModel()

        await model.submit()

        #expect(model.errorMessage == AuthError.emailAlreadyInUse.errorDescription)
    }
}

@MainActor
struct ForgotPasswordViewModelTests {
    private let auth = MockAuthService()

    @Test func prefillsTheEmailFromLogin() {
        let model = ForgotPasswordViewModel(auth: auth, email: "ada@example.com")
        #expect(model.email == "ada@example.com")
        #expect(model.status == .idle)
    }

    @Test func invalidEmailIsNotSent() async {
        let model = ForgotPasswordViewModel(auth: auth, email: "ada")

        await model.submit()

        #expect(model.emailError == ValidationError.invalidEmail.message)
        #expect(model.status == .idle)
        #expect(await auth.resetCalls.isEmpty)
    }

    @Test func sendsTheResetEmail() async {
        let model = ForgotPasswordViewModel(auth: auth, email: " ada@example.com ")

        await model.submit()

        #expect(await auth.resetCalls == ["ada@example.com"])
        #expect(model.status == .sent)
    }

    @Test func unknownAccountLooksLikeSuccess() async {
        // Firebase reports userNotFound (mapped to wrongCredentials) when enumeration protection is off.
        await auth.failReset(with: .wrongCredentials)
        let model = ForgotPasswordViewModel(auth: auth, email: "nobody@example.com")

        await model.submit()

        #expect(model.status == .sent)
    }

    @Test func failureIsShown() async {
        await auth.failReset(with: .network)
        let model = ForgotPasswordViewModel(auth: auth, email: "ada@example.com")

        await model.submit()

        #expect(model.status == .failed(AuthError.network.errorDescription ?? ""))
    }
}
