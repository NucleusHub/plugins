import NotesPluginKit
import NucleusUI
import SwiftUI

/// "From a template": the built-in templates and the person's own in a grid of cards.
struct TemplatesSheet: View {
    let context: NewNoteContext
    var store: TemplateStore = .shared

    var body: some View {
        NucleusSheetPage("New from template", onCancel: { context.finish(nil) }) {
            TemplatesGrid(context: context, store: store)
        }
    }
}

struct TemplatesGrid: View {
    let context: NewNoteContext
    var store: TemplateStore = .shared

    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                header("Templates")
                TwoColumns(NoteTemplate.builtIn) { index, template in
                    cardButton(template).nucleusAppear(index)
                }
                .padding(.bottom, 28)

                HStack(alignment: .firstTextBaseline) {
                    header("Your templates")
                    Spacer()
                    if !store.templates.isEmpty {
                        Button(editing ? "Done" : "Edit") {
                            Haptics.tap()
                            withAnimation(NucleusMotion.quick) { editing.toggle() }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Nucleus.accent)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                }
                if store.templates.isEmpty {
                    EmptyYours()
                } else {
                    TwoColumns(store.templates) { _, template in
                        cardButton(template)
                            .contextMenu {
                                Button(role: .destructive) { delete(template) } label: {
                                    Label("Delete template", systemImage: "trash")
                                }
                            }
                    }
                }
                Text("Your templates are kept on this device only. Save any note as a template from its More menu; {{date}} and {{time}} in it are filled in when you use it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
        }
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Nucleus.secondaryText)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    private func cardButton(_ template: NoteTemplate) -> some View {
        Button {
            guard !editing else { return }
            Haptics.tap()
            context.finish(template.draft(folderID: context.folderID))
        } label: {
            TemplateCard(template: template, editing: editing && !template.isBuiltIn, onDelete: { delete(template) })
                .wiggle(editing && !template.isBuiltIn)
        }
        .buttonStyle(NucleusPressStyle(scale: 0.96))
        .accessibilityLabel(template.name)
        .accessibilityHint("Creates a note from this template")
    }

    private func delete(_ template: NoteTemplate) {
        Task {
            let choice = await context.host.confirm(title: "Delete “\(template.name)”?", message: "Notes made from it stay as they are.",
                                                    actions: ["Delete template"])
            guard choice == 0 else { return }
            Haptics.warning()
            withAnimation(NucleusMotion.quick) {
                store.delete(id: template.id)
                if store.templates.isEmpty { editing = false }
            }
        }
    }
}

/// A plain two-column grid; the lists are short, so nothing needs to be lazy.
private struct TwoColumns<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let cell: (Int, Item) -> Cell

    init(_ items: [Item], @ViewBuilder cell: @escaping (Int, Item) -> Cell) {
        self.items = items
        self.cell = cell
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { row in
                GridRow {
                    cell(row, items[row])
                    if row + 1 < items.count {
                        cell(row + 1, items[row + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

/// The dashed placeholder before the person has saved a template.
private struct EmptyYours: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Nucleus.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Nucleus.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("No templates of your own yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                Text("Open a note, tap More and choose Save as template.")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Nucleus.secondaryText.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
    }
}

private extension View {
    /// The home-screen jiggle while managing templates.
    func wiggle(_ on: Bool) -> some View { modifier(Wiggle(on: on)) }
}

private struct Wiggle: ViewModifier {
    let on: Bool
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on && !reduceMotion ? (phase ? 1.2 : -1.2) : 0))
            .animation(on && !reduceMotion ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: phase)
            .onChange(of: on, initial: true) { _, now in phase = now }
    }
}
