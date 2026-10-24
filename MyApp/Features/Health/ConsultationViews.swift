import SwiftUI

/// The appointment area of the Saúde tab: "Iniciar Consulta" opens the quick-entry sheet (the
/// questions saved for it, and every measure to fill in), and the questions are kept in their own list.
struct ConsultationCard: View {
    @Environment(DataStore.self) private var store
    @Binding var showingConsultation: Bool

    var body: some View {
        Section {
            Button {
                showingConsultation = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "stethoscope")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Iniciar Consulta")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Perguntas, peso, bioimpedância e medidas num só sítio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ConsultationQuestionsView()
            } label: {
                LabeledContent {
                    let pending = store.pendingConsultationQuestions.count
                    Text(pending == 0 ? "—" : "\(pending) por fazer")
                } label: {
                    Label("Perguntas para a Consulta", systemImage: "questionmark.bubble")
                }
            }
        } header: {
            Text("Consulta")
        } footer: {
            Text("Escreve aqui as perguntas à medida que te surgem. Ao iniciar a consulta aparecem lá, e os valores que medires ficam registados no sítio certo.")
        }
    }
}

/// The questions saved for the next appointment (to ask) and the ones already answered, kept as a record.
struct ConsultationQuestionsView: View {
    @Environment(DataStore.self) private var store

    @State private var newQuestion = ""
    @State private var editing: ConsultationQuestion?
    @FocusState private var isAdding: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Nova pergunta", text: $newQuestion, axis: .vertical)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Adicionar", action: add)
                        .disabled(newQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Por fazer")
            } footer: {
                if store.pendingConsultationQuestions.isEmpty {
                    Text("Sem perguntas por agora.")
                }
            }

            if !store.pendingConsultationQuestions.isEmpty {
                Section {
                    ForEach(store.pendingConsultationQuestions) { question in
                        Button {
                            editing = question
                        } label: {
                            Text(question.text).foregroundStyle(.primary)
                        }
                    }
                    .onDelete { offsets in
                        let pending = store.pendingConsultationQuestions
                        store.deleteConsultationQuestions(withIDs: Set(offsets.map { pending[$0].id }))
                    }
                }
            }

            if !store.answeredConsultationQuestions.isEmpty {
                Section("Respondidas") {
                    ForEach(store.answeredConsultationQuestions) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.text)
                            if let answer = question.answer, !answer.isEmpty {
                                Text(answer).font(.callout).foregroundStyle(.secondary)
                            }
                            if let date = question.answeredAt {
                                Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let answered = store.answeredConsultationQuestions
                        store.deleteConsultationQuestions(withIDs: Set(offsets.map { answered[$0].id }))
                    }
                }
            }
        }
        .navigationTitle("Perguntas para a Consulta")
        .sheet(item: $editing) { question in
            EditQuestionView(question: question)
        }
    }

    private func add() {
        store.addConsultationQuestion(newQuestion)
        newQuestion = ""
    }
}

private struct EditQuestionView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let question: ConsultationQuestion
    @State private var text: String

    init(question: ConsultationQuestion) {
        self.question = question
        _text = State(initialValue: question.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Pergunta", text: $text, axis: .vertical)
                    .lineLimit(2...8)
            }
            .navigationTitle("Editar Pergunta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        var updated = question
                        updated.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                        store.updateConsultationQuestion(updated)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
