import SwiftUI
import Charts

// Récords personales (PR) por ejercicio, guardados en el dispositivo. Se
// siembran los de Press banca; puedes añadir más (y otros ejercicios) a mano.
struct PRRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: String   // yyyy-MM-dd
    var weight: Double
}

enum PRStore {
    static let key = "pr_records"

    static func load() -> [String: [PRRecord]] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let m = try? JSONDecoder().decode([String: [PRRecord]].self, from: d) else { return [:] }
        return m
    }
    static func save(_ m: [String: [PRRecord]]) {
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: key) }
    }
    static func seedIfNeeded() {
        var m = load()
        if m["Press banca"] == nil {
            m["Press banca"] = seedPressBanca
            save(m)
        }
    }
    static let seedPressBanca: [PRRecord] = [
        .init(date: "2022-10-16", weight: 45),
        .init(date: "2022-12-11", weight: 50),
        .init(date: "2022-12-07", weight: 52.5),
        .init(date: "2023-03-03", weight: 55),
        .init(date: "2023-06-03", weight: 60),
        .init(date: "2023-10-14", weight: 70),
        .init(date: "2024-09-27", weight: 75),
        .init(date: "2024-11-19", weight: 80),
        .init(date: "2025-01-17", weight: 82.5),
        .init(date: "2025-02-24", weight: 87.5),
        .init(date: "2025-03-06", weight: 90),
        .init(date: "2025-10-01", weight: 92.5),
        .init(date: "2025-10-29", weight: 97.5),
        .init(date: "2025-11-26", weight: 100),
    ]
}

struct PRView: View {
    @State private var records: [String: [PRRecord]] = [:]
    @State private var selected = "Press banca"
    @State private var addingPR = false
    @State private var addingExercise = false
    @State private var newExercise = ""
    @State private var showHistory = false
    @State private var confirmDelete: PRRecord?

    var exercises: [String] { records.keys.sorted() }
    var list: [PRRecord] { (records[selected] ?? []).sorted { $0.date < $1.date } }
    var best: Double { list.map(\.weight).max() ?? 0 }

    var body: some View {
        Screen(title: "Récords") {
            // Selector de ejercicio (por ahora solo Press banca; puedes añadir).
            Menu {
                ForEach(exercises, id: \.self) { name in
                    Button(name) { selected = name; Haptics.selection() }
                }
                Divider()
                Button { addingExercise = true } label: { Label("Nuevo ejercicio", systemImage: "plus") }
            } label: {
                HStack {
                    Text(selected).font(Theme.dHeadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(Theme.dCaption).foregroundStyle(Theme.muted)
                }
                .card()
            }

            if list.isEmpty {
                EmptyState(text: "Sin récords todavía. Añade el primero.")
            } else {
                HStack(spacing: 10) {
                    StatTile(icon: "trophy", value: "\(best.clean) kg", label: "récord actual")
                    StatTile(icon: "number", value: "\(list.count)", label: "marcas registradas")
                }

                if list.count > 1 {
                    let vals = list.map(\.weight)
                    let lo = vals.min() ?? 0, hi = vals.max() ?? 1
                    let pad = max((hi - lo) * 0.15, 1)
                    SectionHeader(title: "Progresión")
                    Chart(list) { r in
                        LineMark(x: .value("Fecha", Fmt.date(r.date) ?? .now),
                                 y: .value("kg", r.weight))
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Fecha", Fmt.date(r.date) ?? .now),
                                  y: .value("kg", r.weight))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: (lo - pad)...(hi + pad))
                    .frame(height: 200)
                    .clipped()
                    .card()
                }

                // Historial plegado (discreto): se despliega solo si lo pides.
                Button {
                    Haptics.light(); withAnimation { showHistory.toggle() }
                } label: {
                    HStack {
                        Text("Historial · \(list.count) marcas")
                            .font(Theme.dFootnote)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)

                if showHistory {
                    ForEach(list.reversed()) { r in
                        HStack {
                            Text("\(r.weight.clean) kg")
                                .font(Theme.dSubheadline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(Fmt.short(r.date))
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                            Button {
                                Haptics.rigid(); confirmDelete = r
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .light)).foregroundStyle(Theme.muted)
                            }
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                }
            }

            HButton(haptic: Haptics.medium) { addingPR = true } label: {
                Label("Añadir récord", systemImage: "plus")
                    .font(Theme.dHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .actionGlass()
        }
        .task { PRStore.seedIfNeeded(); records = PRStore.load() }
        .sheet(isPresented: $addingPR) {
            AddPRSheet { date, weight in
                var m = records
                m[selected, default: []].append(PRRecord(date: date, weight: weight))
                records = m; PRStore.save(m)
            }
        }
        .confirmationDialog("¿Borrar este récord?",
                            isPresented: Binding(get: { confirmDelete != nil },
                                                 set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { r in
            Button("Borrar \(r.weight.clean) kg", role: .destructive) { remove(r); confirmDelete = nil }
            Button("Cancelar", role: .cancel) { confirmDelete = nil }
        }
        .alert("Nuevo ejercicio", isPresented: $addingExercise) {
            TextField("Nombre", text: $newExercise)
            Button("Crear") {
                let n = newExercise.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                var m = records; if m[n] == nil { m[n] = [] }
                records = m; PRStore.save(m); selected = n; newExercise = ""
            }
            Button("Cancelar", role: .cancel) { newExercise = "" }
        }
    }

    func remove(_ r: PRRecord) {
        var m = records
        m[selected]?.removeAll { $0.id == r.id }
        records = m; PRStore.save(m); Haptics.warning()
    }
}

/// Hoja para añadir un récord: fecha + peso.
struct AddPRSheet: View {
    let onAdd: (String, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var weight = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Peso (kg)", text: $weight).keyboardType(.decimalPad)
            }
            .navigationTitle("Nuevo récord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let w = Double(weight.replacingOccurrences(of: ",", with: ".")) else { return }
                        let iso = date.formatted(.iso8601.year().month().day()).prefix(10)
                        Haptics.success()
                        onAdd(String(iso), w)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
