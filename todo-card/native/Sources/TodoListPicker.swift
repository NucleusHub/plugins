import NotesPluginKit
import NucleusUI
import SwiftUI

/// Todo's lists to attach one from, the Inbox first.
struct TodoListPicker: View {
    let host: any NotesHost
    /// Keys of the lists the note already has.
    let attached: Set<String>
    let onPick: (TodoList) -> Void
    let onCancel: () -> Void
    @State private var lists: [TodoList]?
    @State private var failure: LocalizedStringKey?
    @State private var query = ""

    var body: some View {
        NucleusSheetPage("Todo list", onCancel: onCancel) {
            searchField
            if let lists {
                let found = query.isEmpty ? lists : lists.filter { matches($0) }
                if lists.isEmpty {
                    empty("checklist", title: "No lists yet", message: "Make a list in Todo first.")
                } else if found.isEmpty {
                    empty("magnifyingglass", title: "No matches", message: "No Todo list matches that.")
                } else {
                    TodoListRows(lists: found, attached: attached, onPick: onPick)
                }
            } else if let failure {
                empty("exclamationmark.triangle", title: "Couldn't load Todo", message: failure)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
        .task { await load() }
    }

    private func matches(_ list: TodoList) -> Bool {
        list.name.localizedCaseInsensitiveContains(query) || list.tasks.contains { !$0.done && $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
            TextField("Search lists", text: $query).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nucleus.secondaryText) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .nucleusGlass(in: Capsule())
        .padding(.bottom, 22)
    }

    private func empty(_ icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        NucleusEmptyState(icon, title: title, message: message)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private func load() async {
        do {
            lists = TodoList.lists(try await host.crossApp.view(app: TodoCardLogic.app, name: TodoCardLogic.view))
        } catch CrossAppError.notSignedIn {
            failure = "Sign in with Nucleus ID to see your Todo lists."
        } catch CrossAppError.scopeDenied {
            failure = "Turn the plugin off and on again to reconnect Todo."
        } catch CrossAppError.http(404, _) {
            failure = "Open Todo while signed in so it shares your lists."
        } catch {
            failure = "Check your connection and try again."
        }
    }
}

/// The picker's lists as rows, each with its icon, tint and open count.
struct TodoListRows: View {
    let lists: [TodoList]
    let attached: Set<String>
    let onPick: (TodoList) -> Void

    var body: some View {
        NucleusSection(footer: Text("The list shows as a card in this note. Checking off tasks there checks them off in Todo.")) {
            ForEach(lists) { row($0) }
        }
    }

    private func row(_ list: TodoList) -> some View {
        let on = attached.contains(list.id)
        let open = list.openCount
        return Button {
            Haptics.success()
            onPick(list)
        } label: {
            NucleusRow(verbatim: list.name,
                       subtitle: open == 0 ? Text("No open tasks") : Text("\(open) open"),
                       icon: IconTile(list.icon, tint: NucleusTint(rawValue: list.tint) ?? .indigo)) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Nucleus.accent)
                        .accessibilityLabel("In this note")
                } else {
                    Chevron()
                }
            }
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

}
