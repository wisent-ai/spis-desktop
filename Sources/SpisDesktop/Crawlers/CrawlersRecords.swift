import SwiftUI
import WisentDesignSystem

// What a crawl wrote and what it summed to: the record list and the counts
// beneath it.
//
// Split out of `CrawlersDiagnostics.swift`, which had grown past the
// three-hundred-line limit.

extension CrawlersView {
    @ViewBuilder
    func recordsDisclosureView(_ records: [CrawlOperation.CrawlCatalog.CrawlRecord]) -> some View {
        DisclosureGroup("Records (\(records.count))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(records, id: \.record) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(record.record)
                                .font(.caption)
                                .monospaced()
                                .textSelection(.enabled)
                            Spacer()
                            Text(statusLabel(record.state))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(stateColor(record.state))
                        }
                        
                        if record.states != nil || record.interactions != nil || record.media != nil {
                            HStack {
                                Text([
                                    record.states.map { "\($0) states" },
                                    record.interactions.map { "\($0) interactions" },
                                    record.media.map { "\($0) media" }
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        
                        if let gaps = record.gaps, !gaps.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("Gaps: \(gaps.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .lineLimit(nil)
                                    .textSelection(.enabled)
                            }
                        }
                        
                        if let err = record.error {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text(err)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .lineLimit(nil)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    @ViewBuilder
    func summaryView(_ counts: [String: Int]) -> some View {
        let catalogCounts = counts.filter { $0.key.hasPrefix("catalog_") }
        let recordCounts = counts.filter { $0.key.hasPrefix("record_") }
        
        if !catalogCounts.isEmpty {
            Text("Catalogs").fontWeight(.semibold).font(.caption)
            ForEach(catalogCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(countLabel(key))
                    Spacer()
                    Text("\(value)").fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
        
        if !catalogCounts.isEmpty && !recordCounts.isEmpty {
            Divider()
        }
        
        if !recordCounts.isEmpty {
            Text("Records").fontWeight(.semibold).font(.caption)
            ForEach(recordCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(countLabel(key))
                    Spacer()
                    Text("\(value)").fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
    }
    
}
