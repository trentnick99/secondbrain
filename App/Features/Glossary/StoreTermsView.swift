import SwiftUI
import SecondBrainCore

/// Searchable reference of store terms, acronyms and slang. Works offline; nothing is sent anywhere.
struct StoreTermsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    var showsDoneButton = true

    init(initialQuery: String? = nil, showsDoneButton: Bool = true) {
        _query = State(initialValue: initialQuery ?? "")
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Store Terms")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search, e.g. FTPR or remix")
                .navigationDestination(for: GlossaryTerm.Category.self) { CategoryTermsView(category: $0) }
                .toolbar {
                    if showsDoneButton {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            browseList
        } else {
            let results = StoreGlossary.search(trimmed)
            if results.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else {
                List {
                    Section("\(results.count) found") {
                        ForEach(results.prefix(150)) { TermRow(entry: $0, showsCategory: true) }
                    }
                }
                .accessibilityIdentifier("storeTermsResults")
            }
        }
    }

    private var browseList: some View {
        List {
            Section {
                ForEach(GlossaryTerm.Category.allCases) { category in
                    NavigationLink(value: category) {
                        HStack {
                            Label(category.title, systemImage: category.systemImage)
                            Spacer()
                            Text("\(StoreGlossary.terms.filter { $0.category == category }.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text(StoreGlossary.disclaimer)
            }
            Section {
                ForEach(StoreGlossary.termsWithSeveralMeanings, id: \.self) { term in
                    Button { query = term } label: {
                        HStack {
                            Text(term).foregroundStyle(.primary)
                            Spacer()
                            Text("\(StoreGlossary.lookup(term).count) meanings").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Same word, different meanings")
            } footer: {
                Text("Quick Capture reads “MOD” in capitals as Manager on Duty and lowercase “mod” as a modular.")
            }
        }
        .accessibilityIdentifier("storeTermsBrowse")
    }
}

/// All the terms in one category, searchable within it.
private struct CategoryTermsView: View {
    let category: GlossaryTerm.Category
    @State private var query = ""

    var body: some View {
        let results = StoreGlossary.search(query, in: category)
        List {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            ForEach(results) { TermRow(entry: $0, showsCategory: false) }
        }
        .searchable(text: $query, prompt: "Search \(category.title.lowercased())")
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One term: name, plain-language meaning, how settled it is, and any other meanings.
struct TermRow: View {
    let entry: GlossaryTerm
    var showsCategory = false

    var body: some View {
        let others = StoreGlossary.lookup(entry.term).filter { $0.id != entry.id }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.displayTerm).font(.headline)
                if let label = entry.usage.label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.stroke))
                        .foregroundStyle(.secondary)
                }
            }
            Text(entry.meaning).font(.subheadline).foregroundStyle(.secondary)
            if !others.isEmpty {
                Text("Also: " + others.map(\.meaning).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
            if showsCategory {
                Label(entry.category.title, systemImage: entry.category.systemImage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// Explains the acronyms in a task's title and details, e.g. FTPR, O/N, WOSH.
struct TermsMentionedSection: View {
    let text: String

    var body: some View {
        let terms = StoreGlossary.acronymsMentioned(in: text, limit: 4)
        if !terms.isEmpty {
            Section("Terms") {
                ForEach(terms) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayTerm).font(.subheadline.weight(.semibold))
                        Text(entry.meaning).font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A soft, non-blocking note when text looks like it holds details that belong in an approved system.
struct SensitiveContentNotice: View {
    let text: String

    var body: some View {
        if let notice = SensitiveContent.check(text) {
            Label {
                Text(notice.message)
            } icon: {
                Image(systemName: "hand.raised.fill")
            }
            .font(.footnote)
            .foregroundStyle(Theme.warning)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("sensitiveNotice")
            .transition(.opacity)
        }
    }
}
