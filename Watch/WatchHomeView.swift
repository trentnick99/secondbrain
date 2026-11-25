import SwiftUI

struct WatchHomeView: View {
    private let store = WatchStore.shared
    @State private var note = ""
    @State private var confirming: WatchItem?
    @State private var sentNote = false

    var body: some View {
        NavigationStack {
            List {
                if !store.shiftLabel.isEmpty || store.total > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            if let end = store.shiftEnd, end > Date() {
                                Text(timerInterval: Date()...end, countsDown: true)
                                    .font(.title3.monospacedDigit().weight(.semibold))
                            }
                            Text([store.shiftLabel, store.total > 0 ? "\(store.done) of \(store.total) done" : ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Top three") {
                    if store.items.isEmpty {
                        Text(store.updated == nil ? "Open Second Brain on your iPhone to sync." : "Nothing open. Nice work.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.items) { item in
                        Button { confirming = item } label: {
                            Label(item.title, systemImage: item.safety ? "shield.lefthalf.filled" : "circle")
                                .font(.footnote)
                        }
                    }
                }

                Section {
                    TextField("Quick note", text: $note)
                        .onSubmit {
                            store.addNote(note)
                            note = ""
                            sentNote = true
                        }
                    if sentNote {
                        Text("Sent to Notes on your iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Saved exactly as you say it.")
                }
            }
            .navigationTitle("Second Brain")
            .alert("Mark done?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { item in
                Button("Done") { store.complete(item) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text(item.title)
            }
        }
    }
}
