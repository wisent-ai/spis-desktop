import SwiftUI

struct ReferenceEditor: View {
    @Environment(ManageModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let slug: String
    let reference: ReferenceEntry

    @State private var sourceURL = ""
    @State private var category = ""
    @State private var selectionNote = ""
    @State private var owner = ""

    private var fields: [String: String] {
        [
            "sourceUrl": sourceURL,
            "category": category,
            "selectionNote": selectionNote,
            "owner": owner,
        ].filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Form {
            Text("Edit \(reference.name)").font(.headline)
            Text(
                "Only filled fields change. The record number, name and evidence remain unchanged."
            )
            .foregroundStyle(.secondary)
            TextField("Source URL", text: $sourceURL)
            TextField("Category", text: $category)
            TextField("Selection note", text: $selectionNote)
            TextField("Owner", text: $owner)
            HStack {
                Button("Cancel") { dismiss() }.disabled(model.running)
                Button("Save changes") {
                    let changes = fields
                    Task {
                        await model.editReference(
                            slug: slug, number: reference.number, fields: changes)
                        if model.output?.succeeded == true { dismiss() }
                    }
                }
                .disabled(fields.isEmpty || model.running)
            }
            if let result = model.output, result.operation == "Edit record", !result.succeeded {
                Text(result.refusal ?? result.output)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .interactiveDismissDisabled(model.running)
    }
}
