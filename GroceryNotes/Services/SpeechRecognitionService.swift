import Foundation
import Speech
import AVFoundation

enum SpeechRecognitionError: Error {
    case notAuthorized
    case notAvailable
    case audioEngineError
    case recognitionFailed
    case alreadyRecording
}

actor SpeechRecognitionService {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var transcriptionContinuation: AsyncStream<String>.Continuation?
    private var currentTranscription = ""

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Request authorization for speech recognition and microphone access
    func requestAuthorization() async -> Bool {
        // Request speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechStatus else { return false }

        // Request microphone authorization
        let microphoneStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return microphoneStatus
    }

    /// Check if speech recognition is available
    func isAvailable() -> Bool {
        return speechRecognizer?.isAvailable ?? false
    }

    /// Start recording and return an AsyncStream of partial transcriptions
    func startRecording() async throws -> AsyncStream<String> {
        guard speechRecognizer != nil else {
            throw SpeechRecognitionError.notAvailable
        }

        guard !audioEngine.isRunning else {
            throw SpeechRecognitionError.alreadyRecording
        }

        // Check authorization status
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            throw SpeechRecognitionError.notAuthorized
        }

        // Reset state
        currentTranscription = ""

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create and configure the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.audioEngineError
        }

        recognitionRequest.shouldReportPartialResults = true

        // Get the audio input node
        let inputNode = audioEngine.inputNode

        // Create the recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task {
                await self?.handleRecognitionResult(result: result, error: error)
            }
        }

        // Configure the microphone input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start the audio engine
        audioEngine.prepare()
        try audioEngine.start()

        // Return AsyncStream for transcription updates
        return AsyncStream { continuation in
            Task {
                await self.setTranscriptionContinuation(continuation)
            }
        }
    }

    /// Stop recording and return the final transcription
    func stopRecording() async -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        transcriptionContinuation?.finish()
        transcriptionContinuation = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return currentTranscription
    }

    /// Cancel recording without returning transcription
    func cancelRecording() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        transcriptionContinuation?.finish()
        transcriptionContinuation = nil

        currentTranscription = ""

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private Helpers

    private func setTranscriptionContinuation(_ continuation: AsyncStream<String>.Continuation) {
        self.transcriptionContinuation = continuation
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("Speech recognition error: \(error.localizedDescription)")
            transcriptionContinuation?.finish()
            return
        }

        if let result = result {
            let transcription = result.bestTranscription.formattedString
            currentTranscription = transcription
            transcriptionContinuation?.yield(transcription)

            // If this is the final result, finish the stream
            if result.isFinal {
                transcriptionContinuation?.finish()
            }
        }
    }
}
