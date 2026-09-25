import SwiftUI
import AtherKit

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showLogin = false
    @AppStorage("hideWidgetTip") private var hideWidgetTip = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let status = model.snapshot.status {
                        StatusHero(status: status)
                        DetailsCard(status: status, snapshot: model.snapshot)
                    } else if model.isRefreshing {
                        ProgressView("Fetching status…")
                            .padding(.vertical, 80)
                    } else {
                        ContentUnavailableView(
                            "No status yet",
                            systemImage: "bolt.slash",
                            description: Text("Pull down to refresh.")
                        )
                    }

                    if let error = model.snapshot.lastError {
                        ErrorCard(message: error, needsSignIn: model.snapshot.needsSignIn) {
                            showLogin = true
                        }
                    }
                    if !model.store.isShared {
                        AppGroupWarningCard()
                    }
                    if !hideWidgetTip {
                        WidgetTipCard { hideWidgetTip = true }
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .refreshable { await model.refresh() }
            .navigationTitle(model.settings.scooterName ?? (model.settings.source == .demo ? "Demo" : "Ather Charge"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showLogin) {
                NavigationStack { LoginView() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct StatusHero: View {
    var status: ChargeStatus

    var body: some View {
        VStack(spacing: 14) {
            BatteryRing(soc: status.soc, color: status.levelColor, lineWidth: 18) {
                VStack(spacing: 2) {
                    Image(systemName: status.state == .charging ? "bolt.fill" : "scooter")
                        .font(.title2)
                        .foregroundStyle(status.levelColor)
                    Text(status.socText)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    if let range = status.rangeKm {
                        Text("\(Int(range.rounded())) km")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 230, height: 230)
            .padding(.top, 8)

            Label(status.stateTitle, systemImage: status.stateSymbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(status.levelColor)

            if let target = status.countdownTarget(from: Date()) {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Full in")
                        Text(timerInterval: Date()...target, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.headline)
                    Text("\(status.fullAtIsEstimate ? "Estimated around" : "At") \(target.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DetailsCard: View {
    var status: ChargeStatus
    var snapshot: StatusSnapshot

    var body: some View {
        VStack(spacing: 0) {
            row("Status", systemImage: status.stateSymbol) {
                VStack(alignment: .trailing) {
                    Text(status.stateTitle)
                    Text(status.sourceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let rate = status.chargeRatePerHour {
                Divider()
                row("Charge rate", systemImage: "speedometer") {
                    Text("\(Int(rate.rounded()))% per hour")
                }
            }
            if let range = status.rangeKm {
                Divider()
                row("Range", systemImage: "road.lanes") {
                    Text("\(Int(range.rounded())) km")
                }
            }
            if let front = status.frontTyrePsi, let rear = status.rearTyrePsi {
                Divider()
                row("Tyres", systemImage: "circle.circle") {
                    Text("Front \(front.formatted(.number.precision(.fractionLength(0...1)))) · Rear \(rear.formatted(.number.precision(.fractionLength(0...1)))) psi")
                }
            }
            Divider()
            row("Scooter reading", systemImage: "clock") {
                if status.reportedAt != nil {
                    Text(status.asOf, format: .relative(presentation: .named))
                } else {
                    Text("Time not reported")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            row("Last checked", systemImage: "arrow.clockwise") {
                Text(snapshot.lastAttemptAt ?? status.fetchedAt, format: .relative(presentation: .named))
            }
        }
        .font(.subheadline)
        .padding(.horizontal)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func row<Value: View>(_ title: String, systemImage: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
            value()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }
}

private struct ErrorCard: View {
    var message: String
    var needsSignIn: Bool
    var signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(needsSignIn ? "Sign in needed" : "Couldn't update", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.medium)
            Text(message)
                .font(.subheadline)
            if needsSignIn {
                Button("Sign in again", action: signIn)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.medium.opacity(0.12)))
    }
}

private struct AppGroupWarningCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Widget can't see this app's data", systemImage: "square.stack.3d.up.slash")
                .font(.headline)
                .foregroundStyle(Theme.low)
            Text("The app and widget share data through an App Group, and this install doesn't have one. Reinstall with AltStore, or in Sideloadly keep app extensions enabled and don't change the bundle ID. See the README for details.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.low.opacity(0.12)))
    }
}

private struct WidgetTipCard: View {
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Add the widget", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            Text("Home Screen: touch and hold an empty spot, tap Edit → Add Widget, and search for “Ather Charge”.\nLock Screen: touch and hold the Lock Screen, tap Customize → Lock Screen, then tap the widget area.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }
}
