import UIKit
import AVFoundation


enum SWCameraCaptureSetupResult: Equatable {
    case none
    case noAccessToCamera
    case noAccessToMic
    case success
    case failed
}


final class SWAudioSessionManager: NSObject {
    
    enum Error: Swift.Error {
        case unnableToCreateCaptureDevice(mediaType: AVMediaType)
        case unnableToAddCaptureDeviceInput(mediaType: AVMediaType)
        case unnableToAddCaptureDataOutput(mediaType: AVMediaType)
        case exposureModeIsNotSupported(mode: AVCaptureDevice.ExposureMode)
        case capturePresetIsNotSupported(preset: AVCaptureSession.Preset)
        case captureSessionIsNotSetup
        case unnableToUpdateVideoOrientation
        case unnableToStartSession
        case unnableToStopSession
    }

    var numberOfChannelsCallback: ((UInt32) -> Void)?

    // MARK: - Private Properties
    
    private var setupResult = SWCameraCaptureSetupResult.none
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.swivl.device_audio_capture.session_queue")
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var audioDeviceInput: AVCaptureDeviceInput?
    
    // MARK: - Public Methods
    
    func requestAcessAndSetupAudio(completion: ((_ result: SWCameraCaptureSetupResult) -> Void)? = nil) {
        guard setupResult == .none else {
            DispatchQueue.main.async {
                // Repeated setup is not supported, return previous setup result
                completion?(self.setupResult)
            }
            return
        }
       
        requestAcess(for: .audio) { [weak self] audioGranted in
            if audioGranted {
                self?.sessionQueue.async { [weak self] in
                    guard let self = self else { return }
                    
                    do {
                        try self.setupCaptureSession()
                        DispatchQueue.main.async {
                            self.setupResult = .success
                            completion?(self.setupResult)
                        }
                    } catch _ {
                        DispatchQueue.main.async {
                            self.setupResult = .failed
                            completion?(self.setupResult)
                        }
                    }
                }
            } else {
                self?.setupResult = .noAccessToMic
                completion?(.noAccessToMic)
            }
        }
    }
    
    func startRunning(completion: ((_ error: Error?) -> Void)? = nil) {
        guard self.setupResult == .success else {
            DispatchQueue.main.async {
                completion?(Error.captureSessionIsNotSetup)
            }
            return
        }
        
        sessionQueue.async {
            guard self.session.isRunning == false else {
                DispatchQueue.main.async {
                    completion?(nil)
                }
                return
            }
            
            self.session.startRunning()
            let success = (self.session.isRunning == true)
            
            DispatchQueue.main.async {
                if success {
                    completion?(nil)
                } else{
                    completion?(Error.unnableToStartSession)
                }
            }
        }
    }
    
    func stopRunning(completion: ((_ error: Error?) -> Void)? = nil) {
        guard self.setupResult == .success else {
            DispatchQueue.main.async {
                completion?(Error.captureSessionIsNotSetup)
            }
            return
        }
        
        sessionQueue.async {
            guard self.session.isRunning == true else {
                DispatchQueue.main.async {
                    completion?(nil)
                }
                return
            }
            
            self.session.stopRunning()
            let success = (self.session.isRunning == false)
            
            DispatchQueue.main.async {
                if success {
                    completion?(nil)
                } else{
                    completion?(Error.unnableToStopSession)
                }
            }
        }
    }
    
    func refreshAudio(completion: ((_ error: Swift.Error?) -> Void)?) {
        guard self.setupResult == .success else {
            DispatchQueue.main.async {
                completion?(Error.captureSessionIsNotSetup)
            }
            return
        }

        sessionQueue.async {
            self.session.beginConfiguration()
            self.audioDeviceInput.flatMap { self.session.removeInput($0) }
            do {
                try self.setupAudioDeviceInput()
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    completion?(nil)
                }
            } catch let error {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    completion?(error)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func setupCaptureSession() throws {
        session.beginConfiguration()
        
        defer {
            session.commitConfiguration()
        }
        
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = false
        
        // Add outputs
        
        let audioBuffersQueue = DispatchQueue(label: "com.swivl.device_audio_capture.audio_buffers_queue")
        audioDataOutput.setSampleBufferDelegate(self, queue: audioBuffersQueue)
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        } else {
            throw Error.unnableToAddCaptureDataOutput(mediaType: .audio)
        }
        
        // Add inputs
        try setupAudioDeviceInput()
    }
    
    private func setupAudioDeviceInput() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw Error.unnableToCreateCaptureDevice(mediaType: .audio)
        }
        
        let input = try AVCaptureDeviceInput(device: device)
        
        if session.canAddInput(input) {
            session.addInput(input)
            self.audioDeviceInput = input
        } else {
            throw Error.unnableToAddCaptureDeviceInput(mediaType: .audio)
        }
    }

    private func requestAcess(for mediaType: AVMediaType, completionHandler: @escaping ((_ granted: Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            completionHandler(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                DispatchQueue.main.async {
                    completionHandler(granted)
                }
            }
        case .denied, .restricted:
            completionHandler(false)
        default:
            break
        }
    }

    
}


// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension SWAudioSessionManager: AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var audioBufferList = AudioBufferList()
        var blockBuffer : CMBlockBuffer?

        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer,
                                                                bufferListSizeNeededOut: nil,
                                                                bufferListOut: &audioBufferList,
                                                                bufferListSize: MemoryLayout<AudioBufferList>.size,
                                                                blockBufferAllocator: nil,
                                                                blockBufferMemoryAllocator: nil, flags: 0,
                                                                blockBufferOut: &blockBuffer)

        let buffers = UnsafeBufferPointer<AudioBuffer>(start: &audioBufferList.mBuffers, count: Int(audioBufferList.mNumberBuffers))

        let numberOfChannels = buffers[0].mNumberChannels

        DispatchQueue.main.async {
            print("Number of channels:", numberOfChannels)
            self.numberOfChannelsCallback?(numberOfChannels)
        }
    }
    
}
