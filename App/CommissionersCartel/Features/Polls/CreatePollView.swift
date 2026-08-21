import SwiftUI
import CartelCore

/// Compose a poll.
///
/// Open to any member, not just the commissioner — settling arguments should
/// not need permission from the person the argument is usually about.
struct CreatePollView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let onCreated: () async -> Void

    @State private var question = ""
    /// Four boxes, because most polls are two to four options and an empty box
    /// is a clearer invitation than an "add option" button.
    @State private var options: [String] = ["", "", "", ""]
    @State private var hasClosingDate = false
    @State private var closesAt = Date().addingTimeInterval(60 * 60 * 24 * 3)
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var questionFocused: Bool

    private var filledOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filledOptions.count >= 2
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Who had the worst draft?", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($questionFocused)
                }

                Section {
                    ForEach(options.indices, id: \.self) { index in
                        TextField("Option \(index + 1)", text: $options[index])
                    }
                    if options.count < 8 {
                        Button("Add another option", systemImage: "plus") {
                            options.append("")
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Options")
                } footer: {
                    Text("At least two. Leave any you don't need blank.")
                }

                Section {
                    Toggle("Close voting at a set time", isOn: $hasClosingDate)
                    if hasClosingDate {
                        DatePicker("Closes", selection: $closesAt, in: Date()...)
                    }
                } footer: {
                    Text(hasClosingDate
                         ? "Results become visible to everyone when it closes."
                         : "Without a closing time the poll stays open, and results stay hidden until each person votes.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Color.loss)
                    }
                }
            }
            .navigationTitle("New poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Post") }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { questionFocused = true }
        }
    }

    private func save() async {
        guard canSave, let chat = environment.chat else { return }
        error = nil
        isSaving = true
        defer { isSaving = false }

        do {
            try await chat.createPoll(
                question: question,
                options: options,
                closesAt: hasClosingDate ? closesAt : nil
            )
            await onCreated()
            dismiss()
        } catch let failure as CartelError {
            error = failure.errorDescription ?? "Couldn't post that poll."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
