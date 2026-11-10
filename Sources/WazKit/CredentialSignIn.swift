//
//  CredentialSignIn.swift
//  WazKit
//
//  Native sign-in shared by the apps: an email and password form, then "Who's watching?" with the
//  account's profiles (and a PIN field for protected ones). The app supplies the service calls —
//  how to log in and how to pick a profile — and what they store (a bearer token, session cookies)
//  is the app's business.
//

import SwiftUI

/// A profile of a signed-in account, as the picker shows it.
public struct SignInProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isPinProtected: Bool
    public let isKids: Bool

    public init(id: String, name: String, isPinProtected: Bool = false, isKids: Bool = false) {
        self.id = id
        self.name = name
        self.isPinProtected = isPinProtected
        self.isKids = isKids
    }
}

/// A service's sign-in calls. One instance lives for one run of the sheet, so `login` can keep
/// whatever `pick` needs (an account token) between the two.
@MainActor
public protocol CredentialSignIn: AnyObject {
    /// The service's name ("Disney+", "Hulu") for the sheet's heading.
    var name: String { get }
    /// Email and password → the account's profiles. Nothing is signed in until a profile is picked.
    func login(email: String, password: String) async throws -> [SignInProfile]
    /// Picks the profile (with its PIN, if protected) and stores the session.
    func pick(_ profile: SignInProfile, pin: String?) async throws
    /// The emailed one-time code → the account's profiles, after `login` threw `SignInCodeSent`.
    func verify(email: String, code: String) async throws -> [SignInProfile]
}

extension CredentialSignIn {
    /// Services that never send codes (their `login` never throws `SignInCodeSent`) need no `verify`.
    public func verify(email: String, code: String) async throws -> [SignInProfile] { throw CancellationError() }
}

/// `login` throws this when the service signs the account in with an emailed code instead of the
/// password, and has sent the code: the form asks for it and calls `verify`.
public struct SignInCodeSent: Error {
    public let email: String
    public init(email: String) { self.email = email }
}

public struct CredentialSignInView: View {
    /// State, not a plain property: the parent may rebuild the view between `login` and `pick`,
    /// and the service instance holds what `pick` needs.
    @State private var service: any CredentialSignIn
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    /// Set while the form asks for the code the service emailed to this address.
    @State private var codeSentTo: String?
    @State private var code = ""
    @State private var profiles: [SignInProfile]?
    @State private var pinFor: SignInProfile?
    @State private var pin = ""
    @State private var busy = false
    @State private var error: String?

    /// - Parameters:
    ///   - service: The service's sign-in calls; kept for the life of the sheet.
    ///   - onSignedIn: Called once, before the sheet dismisses itself.
    public init(service: any CredentialSignIn, onSignedIn: @escaping () -> Void) {
        _service = State(initialValue: service)
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text(profiles == nil ? "Sign in to \(service.name)" : "Who's watching?").font(.title2.bold())
            if let profiles {
                self.profiles(profiles)
            } else {
                credentials
            }
            if let error {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
        }
        .padding(30)
        #if os(macOS)
        .frame(width: 420)
        #else
        .frame(maxWidth: 420)
        #endif
        .disabled(busy)
    }

    private var credentials: some View {
        VStack(spacing: 12) {
            if let sentTo = codeSentTo {
                Text("\(service.name) emailed a code to \(sentTo).").multilineTextAlignment(.center)
                TextField("Code", text: $code)
                    .textContentType(.oneTimeCode)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit { Task { await verifyCode() } }
                Button("Continue") { Task { await verifyCode() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.isEmpty)
                Button("Use a Different Email") { codeSentTo = nil }
                    .buttonStyle(.borderless)
            } else {
                passwordFields
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var passwordFields: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit { Task { await signIn() } }
            Button("Sign In") { Task { await signIn() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || password.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func profiles(_ profiles: [SignInProfile]) -> some View {
        VStack(spacing: 12) {
            ForEach(profiles) { profile in
                Button {
                    if profile.isPinProtected { pinFor = profile; pin = "" } else { Task { await pick(profile, pin: nil) } }
                } label: {
                    HStack {
                        Image(systemName: profile.isKids ? "figure.child.circle.fill" : "person.circle.fill").font(.title)
                        Text(profile.name)
                        Spacer()
                        if profile.isPinProtected { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(pinFor?.id == profile.id ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8))
            }
            if let pinFor {
                HStack {
                    SecureField("PIN for \(pinFor.name)", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await pick(pinFor, pin: pin) } }
                    Button("Continue") { Task { await pick(pinFor, pin: pin) } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(pin.isEmpty)
                }
            }
        }
    }

    private func signIn() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        await signIn { [service, email, password] in
            try await service.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        }
    }

    private func verifyCode() async {
        guard !code.isEmpty else { return }
        await signIn { [service, email, code] in
            try await service.verify(email: email.trimmingCharacters(in: .whitespaces), code: code.trimmingCharacters(in: .whitespaces))
        }
    }

    private func signIn(_ call: @escaping () async throws -> [SignInProfile]) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let profiles = try await call()
            codeSentTo = nil
            self.profiles = profiles
            // One profile without a PIN needs no picking.
            if profiles.count == 1, let only = profiles.first, !only.isPinProtected {
                await pick(only, pin: nil)
            }
        } catch let sent as SignInCodeSent {
            codeSentTo = sent.email
            code = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pick(_ profile: SignInProfile, pin: String?) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await service.pick(profile, pin: pin)
            onSignedIn()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
