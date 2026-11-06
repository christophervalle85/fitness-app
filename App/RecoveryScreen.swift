import SwiftUI
import UniformTypeIdentifiers

private struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RecoveryScreen: View {
    let planner: PlanningStore
    let training: TrainingStore
    let onRestore: () -> Void
    @State private var exported: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var filename = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var candidate: WorkoutBackup?
    @State private var hasPrevious = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button("Save JSON backup") { perform {
                    try export(WorkoutBackup(planner, training).encoded(), .json, "Weekform backup")
                } }
                Button("Export workout CSV") { perform {
                    try export(WorkoutCSV.data(WorkoutBackup(planner, training)), .commaSeparatedText, "Weekform workouts")
                } }
            } footer: { Text("Keep a backup outside this device to recover your routines and workouts if the device is lost.") }
            Section("Restore") {
                Button("Choose backup file") { importing = true }
                if hasPrevious {
                    Button("Review pre-restore copy") { perform {
                        guard let url = try RecoveryPaths.current().previous else { throw PlanningError("No previous copy is available.") }
                        candidate = try WorkoutBackup.read(url)
                    } }
                }
                if let candidate {
                    Text("\(candidate.plans.count) routines · \(candidate.sessions.count) workouts")
                    Text("Replacing your profile saves a recovery copy of your current data first.")
                    Button("Replace current profile", role: .destructive) { perform {
                        try RecoveryPaths.replace(with: candidate, planner: planner, training: training)
                        self.candidate = nil
                        onRestore()
                    } }
                    Button("Cancel replacement") { self.candidate = nil }
                }
            }
            if let message { Text(message).accessibilityLabel(message) }
        }
        .navigationTitle("Backup and export")
        .onAppear { perform { hasPrevious = try RecoveryPaths.current().previous != nil } }
        .fileExporter(isPresented: $exporting, document: exported, contentType: exportType, defaultFilename: filename) { result in
            perform { _ = try result.get(); message = "File saved." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            candidate = nil
            perform {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                candidate = try WorkoutBackup.read(url)
            }
        }
    }

    private func export(_ data: Data, _ type: UTType, _ name: String) {
        exported = ExportDocument(data: data); exportType = type; filename = name; exporting = true
    }
    private func perform(_ action: () throws -> Void) {
        message = nil
        do { try action() }
        catch let error as CocoaError where error.code == .userCancelled { }
        catch { message = error.localizedDescription }
    }
}
