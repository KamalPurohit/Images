import SwiftUI
import UIKit
import WidgetKit
import AtherKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var overrides = FieldOverrides()
    @State private var showLogin = false
    @State private var confirmSignOut = false
    @State private var scooters: [Scooter] = []
    @State private var showScooterPicker = false
    @State private var loadingScooters = false
    @State private var scooterError: String?

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                if model.settings.source == .ather {
                    fieldMappingSection
                }
                widgetSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { overrides = model.settings.overrides }
            .sheet(isPresented: $showLogin) {
                NavigationStack { LoginView() }
            }
            .confirmationDialog("Choose scooter", isPresented: $showScooterPicker, titleVisibility: .visible) {
                ForEach(scooters) { scooter in
                    Button(scooter.displayName) {
                        Task {
                            await model.finishSignIn(token: model.settings.token ?? "", phone: nil, scooter: scooter)
                        }
                    }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    model.signOut()
                    dismiss()
                }
            } message: {
                Text("Removes your Ather login and saved status from this phone.")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var accountSection: some View {
        Section("Account") {
            if model.settings.source == .demo {
                LabeledContent("Mode", value: "Demo")
                Button("Sign in with Ather") { showLogin = true }
            } else {
                if let phone = model.settings.phone {
                    LabeledContent("Mobile", value: masked(phone))
                }
                LabeledContent("Scooter", value: model.settings.scooterName ?? model.settings.scooterId.map { "…\($0.suffix(6))" } ?? "—")
                if let token = model.settings.token, let expiry = JWT.expiry(token) {
                    LabeledContent("Login expires") {
                        Text(expiry, format: .dateTime.day().month().year())
                            .foregroundStyle(expiry < Date() ? Theme.low : .secondary)
                    }
                }
                Button {
                    Task { await loadScooters() }
                } label: {
                    HStack {
                        Text("Change scooter")
                        if loadingScooters {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(loadingScooters)
                if let scooterError {
                    Text(scooterError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Sign in again") { showLogin = true }
            }
            Button("Sign out", role: .destructive) { confirmSignOut = true }
        }
    }

    @ViewBuilder private var fieldMappingSection: some View {
        Section {
            pathField("Battery %", text: $overrides.socPath, detected: model.snapshot.detected?.soc)
            pathField("Charging", text: $overrides.chargingPath, detected: model.snapshot.detected?.charging)
            pathField("Range", text: $overrides.rangePath, detected: model.snapshot.detected?.range)
            pathField("Time to full", text: $overrides.timeToFullPath, detected: model.snapshot.detected?.timeToFull)
            Picker("Time to full unit", selection: $overrides.timeToFullUnit) {
                Text("Auto").tag(TimeUnit.auto)
                Text("Seconds").tag(TimeUnit.seconds)
                Text("Minutes").tag(TimeUnit.minutes)
                Text("Hours").tag(TimeUnit.hours)
            }
            Button("Save and refresh") {
                Task { await model.updateOverrides(overrides) }
            }
            .disabled(overrides == model.settings.overrides)
            NavigationLink("Raw telemetry") {
                RawTelemetryView()
            }
        } header: {
            Text("Field mapping")
        } footer: {
            Text("Ather doesn't document its telemetry, so the app looks for fields by name. Grey text shows what was found. If a value is wrong, open Raw telemetry, tap the right field to copy its path, and paste it here.")
        }
    }

    @ViewBuilder private var widgetSection: some View {
        Section {
            LabeledContent("Shared storage") {
                Text(model.store.groupIdentifier ?? "Unavailable")
                    .font(.caption.monospaced())
                    .foregroundStyle(model.store.isShared ? Color.secondary : Theme.low)
                    .multilineTextAlignment(.trailing)
            }
            Button("Reload widgets") {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } header: {
            Text("Widget")
        } footer: {
            Text("The widget checks Ather about every 15 minutes while charging and every 30 minutes otherwise. iOS decides the exact timing. Tap ↻ on the medium widget to update it right away.")
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Unofficial app, not affiliated with Ather Energy. It uses the private service behind the Ather app, as documented by the community ather-bot project. It may stop working if Ather changes that service.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("ather-bot on GitHub", destination: URL(string: "https://github.com/paritosh-08/ather-bot")!)
        } header: {
            Text("About")
        }
    }

    // MARK: Helpers

    private func pathField(_ title: String, text: Binding<String>, detected: String?) -> some View {
        LabeledContent(title) {
            TextField(detected ?? "auto", text: text)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func masked(_ phone: String) -> String {
        guard phone.count > 4 else { return phone }
        return String(repeating: "•", count: phone.count - 4) + phone.suffix(4)
    }

    private func loadScooters() async {
        loadingScooters = true
        scooterError = nil
        do {
            scooters = try await model.scootersForCurrentLogin()
            showScooterPicker = true
        } catch {
            scooterError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loadingScooters = false
    }
}

struct RawTelemetryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var raw: Data?
    @State private var search = ""
    @State private var copied: String?

    private struct Field: Identifiable {
        var id: String { path }
        var path: String
        var value: String
    }

    private var fields: [Field] {
        guard let raw, let json = try? JSONValue.decode(raw) else { return [] }
        let all = TelemetryParser.reportedRoot(of: json).leaves().map { Field(path: $0.path, value: $0.value.displayText) }
        guard !search.isEmpty else { return all }
        return all.filter { $0.path.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search) }
    }

    private var prettyJSON: String {
        guard let raw else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: raw),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(decoding: raw, as: UTF8.self)
    }

    var body: some View {
        List {
            if raw == nil {
                ContentUnavailableView(
                    "No telemetry yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Refresh once while signed in to Ather.")
                )
            } else {
                Section {
                    Button("Copy full JSON") {
                        UIPasteboard.general.string = prettyJSON
                        copied = "JSON"
                    }
                    ShareLink(item: prettyJSON, preview: SharePreview("Ather telemetry"))
                } footer: {
                    Text("This can include your scooter's location. Remove it before sharing with anyone.")
                }
                Section("Fields · tap to copy path") {
                    ForEach(fields) { field in
                        Button {
                            UIPasteboard.general.string = field.path
                            copied = field.path
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                Text(field.value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search fields, e.g. charg")
        .navigationTitle("Raw telemetry")
        .onAppear { raw = model.rawTelemetry() }
        .overlay(alignment: .bottom) {
            if let copied {
                Text("Copied \(copied)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.thinMaterial))
                    .padding(.bottom, 12)
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        self.copied = nil
                    }
                    .id(copied)
            }
        }
    }
}
