import SwiftUI
import UniformTypeIdentifiers
import WisentDesignSystem

/// Reusable first-use and Manage surface for Spis's product-owned corpus
/// adoption operation. The app selects a directory and sends its path to the
/// loopback API; validation and persistence remain in Spis core.
struct SpisCorpusAdoptionView: View {
    @Environment(AppModel.self) private var model
    var compact = false
    var onAdopted: () -> Void = {}

    @State private var choosingDirectory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact {
                Text("Use an existing corpus")
                    .font(.headline)
                Text("Choose an unpacked canonical Spis corpus. Its original references, provenance, screenshots, recordings, and evidence files stay in place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Choose Corpus…") { choosingDirectory = true }
                    .disabled(isRunning)
                if let root = model.root {
                    Text(root.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            switch model.runState {
            case let .running(operation):
                WisentProgressPanel(
                    title: operation,
                    detail: "Spis is validating every catalog and referenced evidence file before saving this location."
                )
            case let .finished(outcome) where outcome.operation == "Adopt corpus":
                if outcome.succeeded {
                    Label("Corpus accepted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if !outcome.output.isEmpty {
                        Text(outcome.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    Label(outcome.refusal ?? "Spis refused the corpus without a reason.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            default:
                Text("Accepted format: a directory with canonical example-catalogs.json, catalog sources.json and references.json, and every referenced record file. Archives are refused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $choosingDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if await model.adoptCorpus(at: url) {
                        onAdopted()
                    }
                }
            case let .failure(error):
                model.runState = .finished(SpisOutcome(
                    operation: "Adopt corpus",
                    status: 1,
                    output: "",
                    refusal: error.localizedDescription
                ))
            }
        }
    }

    private var isRunning: Bool {
        if case .running = model.runState { return true }
        return false
    }
}
