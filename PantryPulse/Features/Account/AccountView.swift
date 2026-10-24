import SwiftUI

struct AccountView: View {
    @Environment(AccountSession.self) private var session
    @Environment(AppLock.self) private var lock
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmLogout = false
    @State private var passwordVisible = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, email, password }

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                Color.clear.frame(height: 0).id("account.top")
                if session.profile != nil {
                    EmptyView()
                } else {
                    accountHeader
                }
                if session.restoring {
                    ProgressView("Restoring account")
                } else if let profile = session.profile {
                    profileFields(profile)
                } else {
                    credentials
                }
                if let message = session.message {
                    Text(message).font(.callout).accessibilityIdentifier("account.message")
                }

            }
            .padding(PPSpacing.lg).frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: registering) { _, _ in scroll.scrollTo("account.top", anchor: .top) }
        }
        .toolbar(.hidden, for: .tabBar)
        .background(PPColors.background)
        .foregroundStyle(PPColors.text)
        .navigationTitle(session.profile == nil ? (registering ? "Create Account" : "Sign In") : "My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: session.profile) { _, profile in
            password = ""
            name = profile?.name ?? ""
        }
        .onAppear { name = session.profile?.name ?? "" }
        .onDisappear { password = "" }
        .confirmationDialog("Sign out of your account?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { session.signOut() }
                .accessibilityIdentifier("profile.confirmSignOut")
        } message: {
            Text("Your pantry stays on this device when you sign out.")
        }
    }

    private var accountHeader: some View {
        VStack(spacing: PPSpacing.sm) {
            Group {
                Image("AccountLeaf")
                    .resizable().scaledToFit().frame(width: 25, height: 25)
                    .frame(width: 64, height: 64)
                    .background(PPColors.primary, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.bottom, PPSpacing.sm)
                    .accessibilityHidden(true)
            }
            Text(registering ? "Create Account" : "Welcome back")
                .font(PPTypography.screenTitle)
            Text(registering ? "Start preventing food waste and tracking your kitchen." : "Sign in to your PantryPulse account.")
                .font(.subheadline).foregroundStyle(PPColors.secondaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.md)
    }

    private var credentials: some View {
        VStack(spacing: PPSpacing.lg) {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                if registering {
                    credentialField("Full name", symbol: "person") {
                        TextField("Your name", text: $name)
                            .textContentType(.name).focused($focusedField, equals: .name)
                            .submitLabel(.next).onSubmit { focusedField = .email }
                            .accessibilityIdentifier("account.name")
                    }
                }
                credentialField("Email address", symbol: "envelope") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next).onSubmit { focusedField = .password }
                        .accessibilityIdentifier("account.email")
                }
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    HStack {
                        Text(registering ? "CREATE PASSWORD" : "Password").font(.caption.weight(.semibold))
                        Spacer()
                        if !registering {
                            Button("Forgot?") {
                                focusedField = nil
                                Task { await session.resetPassword(email: email) }
                            }
                            .font(.caption.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityLabel("Forgot password?")
                            .accessibilityIdentifier("account.resetPassword")
                        }
                    }
                    HStack(spacing: PPSpacing.sm) {
                        Image(systemName: "lock").foregroundStyle(PPColors.secondaryText).accessibilityHidden(true)
                        Group {
                            if passwordVisible { TextField("Password", text: $password) }
                            else { SecureField("Password", text: $password) }
                        }
                        .textContentType(registering ? .newPassword : .password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go).onSubmit(submit)
                        .accessibilityIdentifier("account.password")
                        Button {
                            passwordVisible.toggle()
                            focusedField = .password
                        } label: {
                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(PPColors.secondaryText)
                        .accessibilityLabel(passwordVisible ? "Hide password" : "Show password")
                        .accessibilityIdentifier("account.passwordVisibility")
                    }
                    .padding(.leading, PPSpacing.md).padding(.trailing, PPSpacing.xs)
                    .padding(.vertical, PPSpacing.xs)
                    .background(PPColors.background, in: RoundedRectangle(cornerRadius: registering ? 28 : 16))
                }
                submitButton
            }
            .padding(PPSpacing.lg)
            .background(PPColors.surface, in: RoundedRectangle(cornerRadius: 24))
            .disabled(session.busy)
            Button {
                focusedField = nil
                registering.toggle()
                password = ""
                passwordVisible = false
                session.message = nil
            } label: {
                (Text(registering ? "Already have an account? " : "Don't have an account? ")
                    .foregroundStyle(PPColors.secondaryText)
                 + Text(registering ? "Sign In" : "Sign up").foregroundStyle(PPColors.actionText))
                    .font(.subheadline).multilineTextAlignment(.center)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("account.switchMode")
            .disabled(session.busy)
        }.tint(PPColors.actionText)
    }

    private var submitButton: some View {
        PrimaryButton(title: registering ? "Create Free Account" : "Sign In", systemImage: "arrow.right", isLoading: session.busy, action: submit)
            .accessibilityIdentifier("account.submit")
    }

    private func submit() {
        focusedField = nil
        Task { await session.submit(email: email, password: password, name: registering ? name : nil); password = "" }
    }

    private func credentialField<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            Text(registering ? title.uppercased() : title).font(.caption.weight(.semibold))
                .foregroundStyle(registering ? PPColors.secondaryText : PPColors.text)
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: symbol).foregroundStyle(PPColors.secondaryText).accessibilityHidden(true)
                content()
            }
            .padding(PPSpacing.md).frame(minHeight: 48)
            .background(PPColors.background, in: RoundedRectangle(cornerRadius: registering ? 28 : 16))
        }
    }

    private func profileFields(_ profile: AccountProfile) -> some View {
        VStack(spacing: PPSpacing.lg) {
            VStack(spacing: PPSpacing.sm) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 60)).foregroundStyle(PPColors.primary)
                    .accessibilityHidden(true)
                Text(profile.name.isEmpty ? "My Account" : profile.name).font(PPTypography.sectionTitle)
                    .accessibilityIdentifier("profile.displayName")
                Text(profile.email).font(.subheadline).foregroundStyle(PPColors.secondaryText)
                    .textSelection(.enabled).accessibilityIdentifier("profile.email")
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            .padding(PPSpacing.lg)
            .background(PPColors.surface, in: RoundedRectangle(cornerRadius: 24))

            profileCard("Personal information") {
                credentialField("Display name", symbol: "person") {
                    TextField("Your name", text: $name).textContentType(.name)
                        .focused($focusedField, equals: .name).submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .accessibilityIdentifier("profile.name")
                }
                Text("Email").font(.caption.weight(.semibold)).foregroundStyle(PPColors.secondaryText)
                Text(profile.email).font(.callout).textSelection(.enabled)
                PrimaryButton(title: "Save Changes", systemImage: "checkmark", isLoading: session.busy) {
                    focusedField = nil
                    Task { await session.updateName(name) }
                }
                .disabled(session.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("profile.save")
            }
            profileCard("Security") {
                Toggle(isOn: Binding(get: { lock.enabled }, set: { value in Task { await lock.setEnabled(value) } })) {
                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Label("Lock with Face ID", systemImage: "faceid").font(.headline)
                        Text(lock.faceIDAvailable ? "Require Face ID to unlock PantryPulse." : "Face ID is unavailable or not enrolled on this device.")
                            .font(.caption).foregroundStyle(PPColors.secondaryText)
                    }
                }
                .disabled(lock.evaluating || !lock.faceIDAvailable)
                .accessibilityIdentifier("profile.faceID")
                if lock.evaluating { ProgressView("Checking Face ID") }
                if let message = lock.message { Text(message).font(.callout) }
                Divider()
                Button { Task { await session.resetPassword(email: profile.email) } } label: {
                    Label("Send Password Reset Email", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.disabled(session.busy).accessibilityIdentifier("profile.resetPassword")
            }
            Button(role: .destructive) { confirmLogout = true } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .background(PPColors.surface, in: RoundedRectangle(cornerRadius: 20))
            }.disabled(session.busy).accessibilityIdentifier("profile.signOut")
        }.tint(PPColors.actionText)
    }

    private func profileCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(PPSpacing.lg)
        .background(PPColors.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AppLockOverlay: View {
    @Environment(AccountSession.self) private var session
    @Environment(AppLock.self) private var lock
    var body: some View {
        VStack(spacing: PPSpacing.lg) {
            Image(systemName: "lock.shield").font(.largeTitle)
            Text("PantryPulse is locked").font(PPTypography.screenTitle)
            Text("Unlock with Face ID.")
            PrimaryButton(title: "Unlock", isLoading: lock.evaluating) { Task { await lock.unlock() } }
            if let message = lock.message { Text(message).font(.callout) }
            Button("Sign Out and Use Account Password") {
                let uid = session.profile?.id
                session.signOut()
                if session.profile == nil, let uid { lock.recoverAfterSignOut(uid: uid) }
            }
            Text("Signing in again will let you set up Face ID again on this device.").font(.caption)
        }
        .multilineTextAlignment(.center).padding(PPSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PPColors.background.ignoresSafeArea())
    }
}
