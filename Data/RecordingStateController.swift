import Foundation

final class RecordingStateController: @unchecked Sendable {
    private var pendingRecordingID: UUID? = nil
    private var recordingTimer: Timer? = nil
    private(set) var recordingDuration: TimeInterval = 0

    func prepareOutputURL() -> URL {
        let id = UUID()
        pendingRecordingID = id
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("\(id.uuidString).mov")
    }

    func begin(onDurationChange: @escaping @Sendable (TimeInterval) -> Void) {
        recordingTimer?.invalidate()
        recordingDuration = 0
        onDurationChange(recordingDuration)

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingDuration += 1
            onDurationChange(self.recordingDuration)
        }
    }

    func finish(onDurationChange: @escaping @Sendable (TimeInterval) -> Void) -> UUID? {
        let finishedRecordingID = pendingRecordingID
        pendingRecordingID = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        onDurationChange(recordingDuration)
        return finishedRecordingID
    }
}
