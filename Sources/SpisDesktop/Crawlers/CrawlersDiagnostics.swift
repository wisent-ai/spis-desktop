import SwiftUI
import WisentDesignSystem

// What one catalogue's crawl produced: its preflight checks, the records
// it wrote, and the counts it summed to.
//
// Split out of `CrawlersView.swift`, which had grown past the
// three-hundred-line limit.

extension CrawlersView {
    @ViewBuilder
    func catalogDetailView(_ cat: CrawlOperation.CrawlCatalog) -> some View {
        Section(cat.catalog) {
            HStack {
                Text("Status:")
                Spacer()
                Text(statusLabel(cat.state))
                    .foregroundColor(stateColor(cat.state))
            }
            
            if let pf = cat.preflight {
                preflightDisclosureView(pf)
            }
            
            if let records = cat.records, !records.isEmpty {
                recordsDisclosureView(records)
            }
            
            if let uri = cat.artifact_uri {
                HStack(alignment: .top, spacing: 8) {
                    Text("Artifact:").fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(uri)
                            .font(.caption2)
                            .monospaced()
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .foregroundColor(.blue)
                        Text("(service artifact reference)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let outputUri = cat.output_uri {
                HStack(alignment: .top, spacing: 8) {
                    Text("Output:").fontWeight(.semibold)
                    Text(outputUri)
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(nil)
                        .textSelection(.enabled)
                        .foregroundColor(.blue)
                }
            }
            
            if let err = cat.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption2)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    @ViewBuilder
    func preflightDisclosureView(_ pf: CrawlOperation.CrawlCatalog.PreflightDiagnostic) -> some View {
        DisclosureGroup("Preflight Diagnostics") {
            preflightDetailsView(pf)
        }
    }
    
    @ViewBuilder
    func preflightDetailsView(_ pf: CrawlOperation.CrawlCatalog.PreflightDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Overall Ready:").fontWeight(.semibold)
                Spacer()
                Text(pf.ready ?? false ? "✓ Yes" : "✗ No")
                    .foregroundColor(pf.ready ?? false ? .green : .red)
            }
            .font(.caption)
            
            if let schema = pf.schema {
                HStack {
                    Text("Schema:").font(.caption)
                    Spacer()
                    Text(schema).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let cat = pf.catalog {
                HStack {
                    Text("Catalog:").font(.caption)
                    Spacer()
                    Text(cat).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let eng = pf.engine {
                HStack {
                    Text("Engine:").font(.caption)
                    Spacer()
                    Text(eng).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let host = pf.host {
                HStack {
                    Text("Host:").font(.caption)
                    Spacer()
                    Text(host).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let noPrompts = pf.no_permission_prompts_requested {
                HStack {
                    Text("No Permission Prompts:").font(.caption)
                    Spacer()
                    Text(noPrompts ? "✓ Yes" : "✗ No").font(.caption).foregroundColor(noPrompts ? .green : .orange)
                }
            }
            
            if let checks = pf.checks, !checks.isEmpty {
                Divider()
                Text("Checks").fontWeight(.semibold).font(.caption)
                ForEach(Array(checks.enumerated()), id: \.offset) { idx, check in
                    checkDetailsView(idx, check)
                }
            }
            
            if let records = pf.records, !records.isEmpty {
                Divider()
                Text("Record Preflight Checks").fontWeight(.semibold).font(.caption)
                ForEach(records, id: \.record) { record in
                    recordPreflightDetailsView(record)
                }
            }
            
            if let weles = pf.weles {
                Divider()
                Text("Weles Info").fontWeight(.semibold).font(.caption)
                if let url = weles.admission_url {
                    Text("Admission: \(url)")
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
                if let ready = weles.admission_transport_ready {
                    HStack {
                        Text("Transport Ready:").font(.caption2)
                        Spacer()
                        Text(ready ? "✓ Yes" : "✗ No").foregroundColor(ready ? .green : .orange)
                    }
                }
                if let binding = weles.account_binding {
                    Text("Account: \(binding)")
                        .font(.caption2)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    @ViewBuilder
    func checkDetailsView(_ idx: Int, _ check: CrawlOperation.CrawlCatalog.PreflightDiagnostic.Check) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Check \(idx + 1):").fontWeight(.semibold)
                Spacer()
                Text(check.ready ?? false ? "✓ Ready" : "✗ Not Ready")
                    .foregroundColor(check.ready ?? false ? .green : .orange)
            }
            if let cmd = check.command {
                Text("Command: \(cmd.joined(separator: " "))")
                    .monospaced()
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }
            if let stdout = check.stdout {
                Text("stdout: \(stdout)").foregroundColor(.secondary).lineLimit(nil).textSelection(.enabled)
            }
            if let stderr = check.stderr {
                Text("stderr: \(stderr)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
            }
            if let error = check.error {
                Text("error: \(error)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
            }
        }
        .font(.caption2)
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    func recordPreflightDetailsView(_ rc: CrawlOperation.CrawlCatalog.PreflightDiagnostic.RecordPreflightCheck) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(rc.record ?? "unknown").font(.caption).fontWeight(.semibold).monospaced().textSelection(.enabled)
                    if let name = rc.name {
                        Text(name).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(rc.ready ?? false ? "✓ Ready" : "✗ Not Ready")
                    .font(.caption2)
                    .foregroundColor(rc.ready ?? false ? .green : .orange)
            }
            
            if let binding = rc.account_binding {
                Text("Account: \(binding)").font(.caption2).lineLimit(nil).textSelection(.enabled)
            }
            if let runtime = rc.required_runtime_product {
                Text("Runtime: \(runtime)").font(.caption2).lineLimit(nil).textSelection(.enabled)
            }
            if let diag = rc.diagnostic {
                Text("Diagnostic: \(diag)").font(.caption2).monospaced().lineLimit(nil).textSelection(.enabled)
            }
            
            if let checks = rc.checks, !checks.isEmpty {
                ForEach(Array(checks.enumerated()), id: \.offset) { idx, check in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text("Check \(idx + 1)").font(.caption2).fontWeight(.semibold)
                            Spacer()
                            Text(check.ready ?? false ? "✓" : "✗")
                                .foregroundColor(check.ready ?? false ? .green : .orange)
                        }
                        if let cmd = check.command {
                            Text("Command: \(cmd.joined(separator: " "))").monospaced().lineLimit(nil).textSelection(.enabled)
                        }
                        if let stdout = check.stdout {
                            Text("stdout: \(stdout)").foregroundColor(.secondary).lineLimit(nil).textSelection(.enabled)
                        }
                        if let stderr = check.stderr {
                            Text("stderr: \(stderr)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
                        }
                        if let error = check.error {
                            Text("error: \(error)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
                        }
                    }
                    .font(.caption2)
                    .padding(.vertical, 1)
                }
            }
        }
        .font(.caption2)
        .padding(.vertical, 2)
    }
    
}
