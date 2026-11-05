import Darwin
import Foundation
import SwiftData
import Testing
@testable import Weekform

struct FoundationStoreTests {
    private func withStore(_ test: (FoundationStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(FoundationStore(directory: directory, now: { Date(timeIntervalSince1970: 123) }))
    }

    @Test func reopenAndRetryPreserveOneReceiptAndItsTime() throws {
        try withStore { store in
            let id = UUID()
            #expect(try store.confirmedReps() == nil)
            try store.confirm(id: id, reps: 12)
            let reopened = FoundationStore(directory: store.directory)
            try reopened.confirm(id: id, reps: 12)
            #expect(try reopened.confirmedReps() == 12)
            let schema = Schema(versionedSchema: FoundationSchema.self)
            let config = ModelConfiguration(schema: schema, url: store.directory.appending(path: "foundation.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let rows = try ModelContext(container).fetch(FetchDescriptor<FoundationSchema.ConfirmedSet>())
            #expect(rows.count == 1)
            #expect(rows.first?.confirmedAt == Date(timeIntervalSince1970: 123))
        }
    }

    @Test func rejectsMalformedAndConflictingCommands() throws {
        try withStore { store in
            let id = UUID()
            for invalid in [0, 101] {
                #expect(throws: FoundationStoreError.invalidReps) { try store.confirm(id: id, reps: invalid) }
            }
            #expect(try store.confirmedReps() == nil)
            try store.confirm(id: id, reps: 1)
            #expect(throws: FoundationStoreError.conflictingRetry) { try store.confirm(id: id, reps: 2) }
            #expect(throws: FoundationStoreError.setAlreadyConfirmed) { try store.confirm(id: UUID(), reps: 1) }
            #expect(try store.confirmedReps() == 1)
        }
    }

    @Test func concurrentConfirmationsFromIndependentStoresAgree() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    try FoundationStore(directory: directory).confirm(id: id, reps: 100)
                }
            }
            try await group.waitForAll()
        }
        #expect(try FoundationStore(directory: directory).confirmedReps() == 100)
    }

    @Test func busyStoreAllowsRetryAfterLockRelease() throws {
        try withStore { store in
            let id = UUID()
            try store.confirm(id: id, reps: 12)
            let fd = open(store.directory.appending(path: "store.lock").path, O_RDWR)
            try #require(fd >= 0)
            defer { close(fd) }
            try #require(flock(fd, LOCK_EX | LOCK_NB) == 0)
            #expect(throws: FoundationStoreError.storageBusy) { try store.confirm(id: id, reps: 12) }
            try #require(flock(fd, LOCK_UN) == 0)
            try store.confirm(id: id, reps: 12)
            #expect(try store.confirmedReps() == 12)
        }
    }

    @Test func unavailableDirectoryFailsWithoutReplacingIt() throws {
        try withStore { store in
            let marker = Data("occupied".utf8)
            try marker.write(to: store.directory)
            #expect(throws: (any Error).self) { try store.confirm(id: UUID(), reps: 12) }
            #expect(try Data(contentsOf: store.directory) == marker)
        }
    }
}
