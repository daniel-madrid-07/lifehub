import SwiftUI

/// Tareas sueltas + notas rápidas.
struct TasksView: View {
    @State private var tasks: [TaskItem]?
    @State private var notes: [NoteItem] = []
    @State private var error: String?
    @State private var newTask = ""
    @State private var newNote = ""

    var pending: [TaskItem] { (tasks ?? []).filter { !$0.done } }
    var done: [TaskItem] { (tasks ?? []).filter(\.done) }

    var body: some View {
        Screen(title: "Tareas", refresh: { await load() }) {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if tasks == nil {
                SkeletonList()
            } else {
                HStack {
                    TextField("Nueva tarea…", text: $newTask)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                        .onSubmit { Task { await addTask() } }
                    Button {
                        Task { await addTask() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(Theme.dTitle)
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(newTask.isEmpty)
                }

                if pending.isEmpty && done.isEmpty {
                    EmptyState(text: "Nada pendiente. Disfruta.")
                }

                ForEach(pending) { task in
                    TaskRow(task: task) { await load() }
                }

                if !done.isEmpty {
                    SectionHeader(title: "Hechas")
                    ForEach(done) { task in
                        TaskRow(task: task) { await load() }
                    }
                }

                SectionHeader(title: "Notas rápidas")
                HStack {
                    TextField("Apuntar algo…", text: $newNote)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                        .onSubmit { Task { await addNote() } }
                    Button {
                        Task { await addNote() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(Theme.dTitle)
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(newNote.isEmpty)
                }
                ForEach(notes) { note in
                    HStack(alignment: .top) {
                        Text(note.text)
                            .font(Theme.dSubheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button {
                            Task {
                                _ = try? await API.shared.removeNote(note.id)
                                await load()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .card(padding: 13)
                }
            }
        }
        .task { await load() }
    }

    func addTask() async {
        let text = newTask.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        newTask = ""
        Haptics.light()
        _ = try? await API.shared.createTask(text: text, due: nil)
        await load()
    }

    func addNote() async {
        let text = newNote.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        newNote = ""
        Haptics.light()
        _ = try? await API.shared.createNote(text)
        await load()
    }

    func load() async {
        do {
            tasks = try await API.shared.tasks()
            notes = (try? await API.shared.notes()) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    let onChange: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    _ = try? await API.shared.updateTask(task.id, ["done": .bool(!task.done)])
                    Haptics.light()
                    await onChange()
                }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(Theme.dTitle2)
                    .foregroundStyle(task.done ? Theme.good : Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.text)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Theme.muted : Theme.ink)
                if let due = task.due {
                    Text("Para el \(Fmt.short(due))")
                        .font(Theme.dCaption)
                        .foregroundStyle(overdue(due) && !task.done ? Theme.bad : Theme.muted)
                }
            }
            Spacer()
        }
        .card(padding: 13)
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    _ = try? await API.shared.removeTask(task.id)
                    await onChange()
                }
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
    }

    func overdue(_ due: String) -> Bool {
        guard let d = Fmt.date(due) else { return false }
        return d < Calendar.current.startOfDay(for: .now)
    }
}
