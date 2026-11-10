import SwiftUI

struct SettingsView: View {
    @Environment(APIClient.self) private var api
    @State private var server = ""
    @State private var token = ""
    @State private var result: String?
    @State private var testing = false
    var body: some View {
        Form {
            SwiftUI.Section("Connection") {
                TextField("Server URL", text: $server)
                    #if os(iOS)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                SecureField("Token", text: $token)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                Text("The token is stored in Keychain.").font(.caption).foregroundStyle(.secondary)
                Button("Save") { save() }
                Button("Test connection") { Task { await test() } }.disabled(testing)
                if testing { ProgressView() }
                if let result { Text(result).textSelection(.enabled) }
            }
        }.formStyle(.grouped).navigationTitle("Settings")
        .onAppear { server = api.server; token = api.token }
    }
    @discardableResult private func save() -> Bool {
        do { try api.save(server: server, token: token); result = "Saved"; return true }
        catch { result = error.localizedDescription; return false }
    }
    private func test() async {
        guard save() else { return }
        testing = true
        do {
            let stats: Stats = try await api.request("stats")
            api.unauthorized = false
            result = "\(stats.scenes) scenes · \(stats.sources) sources"
        } catch { result = error.localizedDescription }
        testing = false
    }
}
