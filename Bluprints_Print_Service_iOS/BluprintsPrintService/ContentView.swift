import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var ble: BLEPrinter
    @EnvironmentObject var inbox: JobInbox
    @State private var importing = false
    @State private var confirmSend = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Bluprints Print Service", systemImage: "printer.fill").font(.title2.bold()).foregroundColor(.blue)
                    Text("Print from Chrome using your Bluprints BLE printer.").foregroundColor(.secondary)
                    Text(ble.status).font(.headline).accessibilityIdentifier("connectionStatus")
                    HStack {
                        Button(ble.scanning ? "Stop scan" : "Scan printers") { if ble.scanning { ble.stopScan() } else { ble.scan() } }
                            .disabled(!ble.poweredOn || ble.busy || ble.connecting || ble.ready)
                        Spacer()
                        Button("Disconnect", role: .destructive) { ble.disconnect() }.disabled(!ble.ready && !ble.connecting)
                    }
                    ForEach(ble.devices) { item in
                        Button { ble.connect(item) } label: {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text("\(item.rssi) dBm · \(item.id.uuidString.prefix(8))").font(.caption).foregroundColor(.secondary)
                            }
                        }.disabled(ble.busy || ble.connecting || ble.ready)
                    }
                    Text("The scan lists all BLE devices. Select your printer; the app verifies service FFE1 before enabling printing.").font(.caption).foregroundColor(.secondary)
                } header: { Text("1 · Connect printer") }
                Section {
                    Text(inbox.message).font(.subheadline)
                    if let url = inbox.remoteURL {
                        Text(url.absoluteString).font(.caption).textSelection(.enabled)
                        if inbox.loading { ProgressView("Downloading…"); Button("Cancel download") { inbox.cancelDownload() } }
                        else { Button("Download job") { inbox.fetch() }.disabled(ble.busy) }
                    }
                    if let job = inbox.job {
                        LabeledContent("Job ID", value: job.id)
                        LabeledContent("Format", value: job.format.uppercased())
                        LabeledContent("Size", value: "\(job.bytes.count) bytes")
                        if ble.sentIDs.contains(job.id) { Label("This job ID was sent before. Sending again may create a duplicate.", systemImage: "exclamationmark.triangle").foregroundColor(.orange) }
                        DisclosureGroup("Preview first 256 bytes") {
                            Text(job.bytes.prefix(256).map { String(format: "%02X", $0) }.joined(separator: " ")).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Button { confirmSend = true } label: { Label("Send to printer", systemImage: "paperplane.fill").font(.headline) }
                            .disabled(!ble.ready || ble.busy || inbox.loading)
                    }
                    if ble.busy {
                        ProgressView(value: ble.progress)
                        Button("Cancel transfer", role: .destructive) { ble.disconnect() }
                    }
                    Text("Keep this app open until the transfer finishes. BLE completion does not confirm paper output. No automatic retry is performed.").font(.caption).foregroundColor(.secondary)
                } header: { Text("2 · Review & print") }
                Section {
                    Button("Load ESC/POS receipt test") { inbox.load(.receipt()) }.disabled(ble.busy || inbox.loading)
                    Button("Load TSPL label test (50 × 30 mm)") { inbox.load(.label()) }.disabled(ble.busy || inbox.loading)
                    Button("Import BIN / PRN / TXT / JSON") { importing = true }.disabled(ble.busy || inbox.loading)
                    Text("Raw files are sent unchanged. Select the correct command language for your printer. The TSPL test assumes 203 dpi and a 2 mm label gap.").font(.caption).foregroundColor(.secondary)
                } header: { Text("Test & import") }
                Section {
                    Stepper("Chunk: \(ble.chunkBytes) bytes", value: $ble.chunkBytes, in: 1...512).disabled(ble.busy)
                    Stepper("Gap: \(ble.delayMS) ms", value: $ble.delayMS, in: 0...1000, step: 5).disabled(ble.busy)
                    Text("Default: 20 bytes / 30 ms. Chunk size is also capped by iOS's negotiated write limit. Writes with response are preferred when supported.").font(.caption).foregroundColor(.secondary)
                    Button("Read printer characteristic") { ble.readOnce() }.disabled(!ble.canRead || ble.busy)
                } header: { Text("BLE settings") }
                Section {
                    Text("Service FFE1 · Read FFE2 · Write FFE3\nBase UUID: 0000xxxx-0000-1000-8000-00805f9b34fb").font(.caption.monospaced())
                    ForEach(Array(ble.logs.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()).textSelection(.enabled) }
                    Button("Clear log") { ble.logs.removeAll() }
                } header: { Text("Diagnostics") }
            }
            .navigationTitle("Bluprints")
            .alert("Send this job?", isPresented: $confirmSend) {
                Button("Cancel", role: .cancel) { }
                Button("Send") { if let job = inbox.job { ble.send(job) } }
            } message: { Text("Send \(inbox.job?.bytes.count ?? 0) bytes to \(ble.selectedName)? Verify the printer and command language. Reprints can produce duplicate output.") }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                guard !ble.busy, !inbox.loading else { inbox.message = "Wait for the current operation before importing."; return }
                switch result { case .success(let urls): if let url = urls.first { inbox.importFile(url) }; case .failure(let error): inbox.message = error.localizedDescription }
            }
        }
    }
}
