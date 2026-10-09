import NotesPluginKit
import NucleusUI
import SwiftUI

/// "Save as template": names the note's copy and keeps it in the person's templates.
struct SaveTemplateSheet: View {
    let context: NoteActionContext
    var store: TemplateStore = .shared

    @State private var name: String

    init(context: NoteActionContext, store: TemplateStore = .shared) {
        self.context = context
        self.store = store
        _name = State(initialValue: context.note.displayTitle ?? "")
    }

    private var template: NoteTemplate { NoteTemplate.from(note: context.note, name: name) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NucleusSheetPage("Save as template", confirmTitle: "Save", canConfirm: canSave, onCancel: { context.dismiss() }, onConfirm: save) {
            form
        }
    }

    var form: some View {
        VStack(spacing: 0) {
            NucleusSection("Name", footer: Text("Type {{date}}, {{time}} or {{weekday}} in the note to have them filled in each time.")) {
                NucleusField("Template name", text: $name, prompt: "e.g. Standup")
            }
            NucleusSection("Preview", footer: Text("Templates are kept on this device only. Images and files aren't included.")) {
                TemplateCard(template: template)
                    .frame(maxWidth: 200)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func save() {
        store.add(template)
        Haptics.success()
        context.host.show(String(localized: "Saved as a template"), icon: "square.on.square")
        context.dismiss()
    }
}
