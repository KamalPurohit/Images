import SwiftUI
import AtherKit

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var startingDemo = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                BatteryRing(soc: 72, color: Theme.charging, lineWidth: 14) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.charging)
                }
                .frame(width: 150, height: 150)
                VStack(spacing: 8) {
                    Text("Ather Charge")
                        .font(.largeTitle.bold())
                    Text("Your scooter's battery and charging status on the Home Screen and Lock Screen.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 12) {
                    NavigationLink {
                        LoginView()
                    } label: {
                        Text("Sign in with your Ather account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        startingDemo = true
                        Task { await model.startDemo() }
                    } label: {
                        Text("Try demo mode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(startingDemo)
                }
                Text("Unofficial app, not made by Ather Energy. It uses the same private service as the Ather app, which may change without notice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }
}

struct LoginView: View {
    private enum Step {
        case phone, otp, token, pickScooter
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var otp = ""
    @State private var pastedToken = ""
    @State private var token = ""
    @State private var signedInWithToken = false
    @State private var scooters: [Scooter] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            switch step {
            case .phone: phoneSection
            case .otp: otpSection
            case .token: tokenSection
            case .pickScooter: scooterSection
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(step == .pickScooter ? "Choose scooter" : "Sign in")
        .disabled(busy)
        .onAppear {
            if phone.isEmpty, let saved = model.settings.phone { phone = saved }
        }
    }

    // MARK: Steps

    @ViewBuilder private var phoneSection: some View {
        Section {
            TextField("10-digit mobile number", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        } header: {
            Text("Mobile number")
        } footer: {
            Text("Use the number registered with Ather. Ather will send you an OTP, just like signing in to the Ather app.")
        }
        Section {
            actionButton("Send OTP") {
                try await model.requestOTP(phone: phone)
                otp = ""
                step = .otp
            }
            .disabled(phone.filter(\.isNumber).count < 10)
        }
        Section {
            Button("Paste a login token instead") {
                error = nil
                step = .token
            }
        } footer: {
            Text("If OTP sign-in doesn't work, you can paste a token captured from the Ather app.")
        }
    }

    @ViewBuilder private var otpSection: some View {
        Section {
            TextField("OTP", text: $otp)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
        } header: {
            Text("OTP sent to \(phone)")
        }
        Section {
            actionButton("Verify") {
                let result = try await model.verifyOTP(phone: phone, otp: otp)
                await received(token: result.token, scooters: result.scooters, viaToken: false)
            }
            .disabled(otp.filter(\.isNumber).count < 4)
            actionButton("Resend OTP") {
                try await model.requestOTP(phone: phone)
            }
            Button("Change number") {
                error = nil
                step = .phone
            }
        }
    }

    @ViewBuilder private var tokenSection: some View {
        Section {
            TextField("eyJhbGciOi…", text: $pastedToken, axis: .vertical)
                .lineLimit(3...8)
                .font(.caption.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Login token")
        } footer: {
            Text("The `Authorization: Bearer …` value the Ather app sends to cerberus.ather.io. It stays on this phone.")
        }
        Section {
            actionButton("Continue") {
                let result = try await model.scooters(forPastedToken: pastedToken)
                await received(token: result.token, scooters: result.scooters, viaToken: true)
            }
            .disabled(pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Use OTP instead") {
                error = nil
                step = .phone
            }
        }
    }

    @ViewBuilder private var scooterSection: some View {
        Section("Your scooters") {
            ForEach(scooters) { scooter in
                Button {
                    Task { await finish(with: scooter) }
                } label: {
                    HStack {
                        Image(systemName: "scooter")
                        VStack(alignment: .leading) {
                            Text(scooter.displayName)
                            Text(scooter.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func actionButton(_ title: String, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                busy = true
                error = nil
                do {
                    try await action()
                } catch {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                busy = false
            }
        } label: {
            HStack {
                Text(title)
                if busy {
                    Spacer()
                    ProgressView()
                }
            }
        }
    }

    private func received(token: String, scooters: [Scooter], viaToken: Bool) async {
        self.token = token
        signedInWithToken = viaToken
        self.scooters = scooters
        if scooters.count == 1 {
            await finish(with: scooters[0])
        } else {
            step = .pickScooter
        }
    }

    private func finish(with scooter: Scooter) async {
        busy = true
        await model.finishSignIn(token: token, phone: signedInWithToken ? nil : phone, scooter: scooter)
        busy = false
        dismiss()
    }
}
