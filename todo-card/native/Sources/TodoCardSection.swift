import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit

/// The note's "Todo" section: a card per attached list.
struct TodoCardSection: View {
    @Binding var value: JSONValue?
    @Binding var noteBody: NoteBody
    @State private var store: TodoCardStore

    init(value: Binding<JSONValue?>, noteBody: Binding<NoteBody>, store: TodoCardStore) {
        _value = value
        _noteBody = noteBody
        _store = State(initialValue: store)
    }

    var body: some View {
        let data = TodoCardData(value)
        Group {
            if !data.lists.isEmpty {
                NucleusSection("Todo") {
                    ForEach(data.lists) { list in
                        TodoListCard(list: list, pending: data.pending + store.sending, store: store, value: $value, noteBody: $noteBody)
                    }
                }
                .task {
                    await store.refresh($value)
                    // Follows commands until Todo's view shows them; cheap when there are none.
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                        if store.isWaiting(value) { await store.tick($value) }
                    }
                }
            }
        }
        .onAppear { store.adopt(noteBody, $value) }
        .onChange(of: noteBody) { _, body in store.adopt(body, $value) }
    }
}

/// One list: header with progress, its open tasks, an add field, recently done, and a way into Todo.
struct TodoListCard: View {
    let list: AttachedList
    let pending: [PendingOp]
    let store: TodoCardStore
    @Binding var value: JSONValue?
    @Binding var noteBody: NoteBody
    @State private var newTitle = ""
    @State private var showDone = false
    @State private var showAll = false
    @FocusState private var adding: Bool

    private static let visibleOpen = 6

    private var tint: Color { NucleusTint(rawValue: list.tint)?.color ?? Nucleus.accent }
    private var rows: [TaskRow] { TodoCardLogic.rows(list, pending: pending) }

    var body: some View {
        let rows = rows
        let open = rows.filter { !$0.inDoneSection }
        let done = rows.filter(\.inDoneSection)
        VStack(alignment: .leading, spacing: 0) {
            header(rows)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if list.missing == true {
                missing
            } else {
                let shown = showAll ? open : Array(open.prefix(Self.visibleOpen))
                ForEach(shown) { row in taskRow(row) }
                if open.count > shown.count {
                    moreButton("Show \(open.count - shown.count) more") { showAll = true }
                }
                if open.isEmpty, rows.isEmpty, list.syncedAt == nil {
                    Text(store.failure == nil ? "Loading tasks…" : "Couldn't load this list.")
                        .font(.system(size: 14))
                        .foregroundStyle(Nucleus.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                addField
                if !done.isEmpty { doneGroup(done) }
            }

            footer
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
    }

    // MARK: Header

    private func header(_ rows: [TaskRow]) -> some View {
        let progress = TodoCardLogic.progress(list, rows: rows)
        let left = TodoCardLogic.openCount(list, rows: rows)
        return HStack(spacing: 12) {
            IconTile(list.icon, tint: NucleusTint(rawValue: list.tint) ?? .indigo, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: list.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
                Group {
                    if list.missing == true {
                        Text("Not in Todo")
                    } else if progress.total == 0 {
                        Text("No tasks")
                    } else if left == 0 {
                        Text("All done")
                    } else {
                        Text("\(left) left")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Nucleus.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if list.missing != true, progress.total > 0 {
                ProgressRing(done: progress.done, total: progress.total, tint: tint)
            }
            menu
        }
    }

    private var menu: some View {
        Menu {
            Button { openInTodo() } label: { Label("Open in Todo", systemImage: "arrow.up.forward.app") }
            Button { Task { await store.refresh($value) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Divider()
            Button(role: .destructive) {
                withAnimation(NucleusMotion.quick) { store.remove(list, value: $value, body: $noteBody) }
            } label: { Label("Remove from note", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Nucleus.glyph)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Nucleus.well))
        }
        .accessibilityLabel("More")
    }

    // MARK: Tasks

    private func taskRow(_ row: TaskRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                Task { await store.toggle(row, in: list, $value) }
            } label: {
                Checkbox(done: row.done, priority: row.priority, tint: tint)
                    .opacity(row.isNew ? 0.45 : 1)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NucleusPressStyle(scale: 0.85))
            .disabled(row.isNew)
            .padding(.leading, -11)
            .padding(.trailing, -11)
            .accessibilityLabel(row.done ? Text("Mark “\(row.title)” not done") : Text("Mark “\(row.title)” done"))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: row.title)
                        .font(.system(size: 16))
                        .foregroundStyle(row.done ? Nucleus.secondaryText : Nucleus.primaryText)
                        .strikethrough(row.done, color: Nucleus.secondaryText)
                        .lineLimit(2)
                    if row.flagged, !row.done {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0xF59E0B))
                            .accessibilityLabel("Flagged")
                    }
                    if row.pending { PendingDot(tint: tint) }
                }
                meta(row)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .animation(NucleusMotion.quick, value: row.done)
    }

    @ViewBuilder
    private func meta(_ row: TaskRow) -> some View {
        let due = row.done ? nil : TodoCardLogic.dueLabel(due: row.due, time: row.time, now: Date())
        if due != nil || row.isNew {
            HStack(spacing: 8) {
                if row.isNew {
                    Text("Adding to Todo…")
                } else {
                    if let due {
                        Label { Text(verbatim: due.text) } icon: { Image(systemName: "calendar") }
                            .foregroundStyle(due.overdue ? Nucleus.danger : Nucleus.secondaryText)
                    }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Nucleus.secondaryText)
            .labelStyle(TightLabel())
        }
    }

    private var addField: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.14)))
            TextField("Add task", text: $newTitle)
                .font(.system(size: 16))
                .focused($adding)
                .submitLabel(.done)
                .onSubmit(submit)
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(tint)
                }
                .buttonStyle(NucleusPressStyle())
                .accessibilityLabel("Add")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func submit() {
        let title = newTitle
        newTitle = ""
        Task { await store.add(title, to: list, $value) }
    }

    private func doneGroup(_ done: [TaskRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NucleusMotion.quick) { showDone.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: "\(done.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Nucleus.secondaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(showDone ? 0 : -90))
                    Spacer()
                }
                .foregroundStyle(Nucleus.secondaryText)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDone {
                ForEach(done) { row in taskRow(row) }
            }
        }
    }

    private func moreButton(_ title: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(NucleusMotion.quick, action)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .padding(.leading, 50)
                .frame(height: 32)
        }
        .buttonStyle(.plain)
    }

    private var missing: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Nucleus.danger)
            Text("This list isn't in Todo any more.")
                .foregroundStyle(Nucleus.secondaryText)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button { openInTodo() } label: {
                HStack(spacing: 5) {
                    Text("Open in Todo")
                    Image(systemName: "arrow.up.forward").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(tint.opacity(0.12)))
            }
            .buttonStyle(NucleusPressStyle())
            Spacer(minLength: 0)
            if let stamp = staleStamp {
                Button { Task { await store.refresh($value) } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.loading ? "arrow.triangle.2.circlepath" : "icloud.slash")
                        Text(stamp)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Refreshes the list")
            }
        }
    }

    /// "Updated 5 min. ago" once a refresh failed, so offline cards say how old they are.
    private var staleStamp: LocalizedStringKey? {
        guard store.failure != nil, list.missing != true else { return nil }
        guard let at = store.fetchedAt ?? Timestamp.date(list.syncedAt) else { return "Offline" }
        return "Updated \(at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
    }

    private func openInTodo() {
        let url = TodoCardLogic.url(listId: list.listId)
        guard UIApplication.shared.canOpenURL(url) else {
            store.host.show(String(localized: "Install Todo to open it."), icon: "arrow.down.app")
            return
        }
        UIApplication.shared.open(url)
    }
}

/// A round checkbox; the ring takes the priority color like Todo's.
struct Checkbox: View {
    let done: Bool
    let priority: Int
    let tint: Color

    var body: some View {
        ZStack {
            if done {
                Circle().fill(tint)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(ring, lineWidth: 1.75)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var ring: Color {
        switch priority {
        case 3: Nucleus.danger
        case 2: Color(hex: 0xF59E0B)
        case 1: Color(hex: 0x3B82F6)
        default: Nucleus.secondaryText.opacity(0.7)
        }
    }
}

/// Done out of all, as a ring with the count inside (a check when everything's done).
struct ProgressRing: View {
    let done: Int
    let total: Int
    let tint: Color

    var body: some View {
        let fraction = total == 0 ? 0 : CGFloat(done) / CGFloat(total)
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if done == total {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(tint)
            } else {
                Text(verbatim: "\(done)/\(total)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Nucleus.primaryText)
                    .minimumScaleFactor(0.6)
                    .padding(4)
            }
        }
        .frame(width: 38, height: 38)
        .animation(NucleusMotion.quick, value: fraction)
        .accessibilityElement()
        .accessibilityLabel(Text("\(done) of \(total) done"))
    }
}

/// A command on its way to Todo.
struct PendingDot: View {
    let tint: Color
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.3 : 0.9)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityLabel("Waiting for Todo")
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
