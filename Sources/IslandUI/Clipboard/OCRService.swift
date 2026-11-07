import Vision
import CoreGraphics
import os

/// Reads text out of an image with Apple's on-device Vision framework. Nothing leaves the Mac.
///
/// It tries each recognition level in order. Some setups cannot run the accurate model (it fails with a
/// Neural Engine error after a long wait), so a level that fails is remembered for the rest of the run
/// and the next level is used instead.
struct OCRService {
    private static let failedLevels = OSAllocatedUnfairLock(initialState: Set<Int>())

    let attempts: [VNRequestTextRecognitionLevel]
    /// Text the user is waiting for should not queue behind background work.
    let priority: DispatchQoS.QoSClass

    init(attempts: [VNRequestTextRecognitionLevel] = [.accurate, .fast], priority: DispatchQoS.QoSClass = .userInitiated) {
        self.attempts = attempts
        self.priority = priority
    }

    func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: priority).async {
                continuation.resume(returning: recognizeSynchronously(image))
            }
        }
    }

    private func recognizeSynchronously(_ image: CGImage) -> String {
        for level in attempts where !Self.failedLevels.withLock({ $0.contains(level.rawValue) }) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = level == .accurate
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                Self.failedLevels.withLock { _ = $0.insert(level.rawValue) }
                continue
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }
        return ""
    }
}
