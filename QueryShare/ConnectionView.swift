import SwiftUI

struct RootView: View {
    @Bindable var model: ShareModel
    var body: some View {
        TabView {
            NavigationStack { ConnectionView(model: model) }
                .tabItem { Label("Connection", systemImage: "network") }
            NavigationStack {
                ScrollView {
                    Text(model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled).padding()
                }.navigationTitle("Logs")
                    .toolbar {
                        Button { model.refreshIndex() } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(!model.running).accessibilityLabel("Refresh container index")
                        ShareLink(item: model.logs.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
                        Button("Clear") { model.logs.removeAll() }
                    }
            }.tabItem { Label("Logs", systemImage: "terminal") }
        }.tint(.primary)
            .alert("Connection failed", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
struct ConnectionView: View {
    @Bindable var model: ShareModel
    @State private var reveal = false
    var body: some View {
        Form {
            Section {
                HStack {
                    Circle().fill(model.running ? Color.primary : Color.secondary).frame(width: 8, height: 8)
                    Text(model.status)
                    Spacer()
                    if model.busy { ProgressView() }
                }
                Button(model.running ? "Stop" : "Start", systemImage: model.running ? "stop.fill" : "play.fill") {
                    if model.running { model.stop() } else { model.start() }
                }.disabled(model.busy)
            }
            Section {
                HStack {
                    Text("Username")
                    TextField("mobile", text: $model.username).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }.disabled(model.running || model.busy)
                HStack {
                    Text("Port")
                    TextField("2222", text: $model.port).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }.disabled(model.running || model.busy)
                HStack {
                    Group {
                        if reveal { TextField("Password", text: $model.password) }
                        else { SecureField("Password", text: $model.password) }
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.running || model.busy)
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }.buttonStyle(.borderless).accessibilityLabel(reveal ? "Hide password" : "Show password")
                    Button { UIPasteboard.general.string = model.password } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).accessibilityLabel("Copy password")
                }
            }
            if model.running {
                Section {
                    ForEach(model.addresses, id: \.self) { ip in
                        HStack {
                            Text("sftp -P \(model.port) \(model.username)@\(ip)")
                                .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                            Spacer(minLength: 6)
                            Button { UIPasteboard.general.string = "sftp -P \(model.port) \(model.username)@\(ip)" } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless).accessibilityLabel("Copy connection command")
                        }
                    }
                    if model.addresses.isEmpty { Text("No network address found").foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("QueryShare")
    }
}
