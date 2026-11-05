import Darwin
import Foundation
import SwiftData

enum FoundationSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ConfirmedSet.self] }

    // Sprint 1 stores one synthetic set. Its command ID and payload also serve
    // as the receipt, so confirming it and recording the receipt are one save.
    @Model
    final class ConfirmedSet {
        var commandID: UUID
        var reps: Int
        var confirmedAt: Date

        init(commandID: UUID, reps: Int, confirmedAt: Date) {
            self.commandID = commandID
            self.reps = reps
            self.confirmedAt = confirmedAt
        }
    }
}

enum FoundationStoreError: Error, Equatable, LocalizedError {
    case sharedStorageUnavailable
    case storageBusy
    case invalidReps
    case conflictingRetry
    case setAlreadyConfirmed
    case unexpectedRecordCount

    var errorDescription: String? {
        switch self {
        case .sharedStorageUnavailable: "Shared storage is unavailable. Open the app and try again."
        case .storageBusy: "Another action is saving. Try again."
        case .invalidReps: "Enter a rep count between 1 and 100."
        case .conflictingRetry: "This confirmation was already saved with different reps."
        case .setAlreadyConfirmed: "This test set has already been confirmed."
        case .unexpectedRecordCount: "The test store contains unexpected records."
        }
    }
}

struct FoundationStore: Sendable {
    let directory: URL
    var now: @Sendable () -> Date = { Date() }

    static func live() throws -> FoundationStore {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.christophervalle.weekform"
        ) else {
            throw FoundationStoreError.sharedStorageUnavailable
        }
        return FoundationStore(directory: group.appending(path: "FoundationSpike", directoryHint: .isDirectory))
    }

    func confirm(id: UUID, reps: Int) throws {
        guard (1...100).contains(reps) else { throw FoundationStoreError.invalidReps }
        try withStore { context, existing in
            if let existing {
                guard existing.commandID == id else { throw FoundationStoreError.setAlreadyConfirmed }
                guard existing.reps == reps else { throw FoundationStoreError.conflictingRetry }
                return
            }
            context.insert(FoundationSchema.ConfirmedSet(commandID: id, reps: reps, confirmedAt: now()))
            try context.save()
        }
    }

    func confirmedReps() throws -> Int? {
        try withStore { _, existing in existing?.reps }
    }

    // All app and intent accesses open the same permanent lock file. Fresh
    // contexts under the lock see commits made by the other process.
    private func withStore<T>(
        _ action: (ModelContext, FoundationSchema.ConfirmedSet?) throws -> T
    ) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appending(path: "store.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        // A suspended process may still hold its lock. Bound the wait and
        // preserve the store so the caller can safely retry after resuming.
        let deadline = ContinuousClock.now + .milliseconds(500)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            guard ContinuousClock.now < deadline else { throw FoundationStoreError.storageBusy }
            usleep(5_000)
        }
        let schema = Schema(versionedSchema: FoundationSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            url: directory.appending(path: "foundation.store"),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<FoundationSchema.ConfirmedSet>()
        descriptor.fetchLimit = 2
        let records = try context.fetch(descriptor)
        guard records.count <= 1 else { throw FoundationStoreError.unexpectedRecordCount }
        return try action(context, records.first)
    }
}
