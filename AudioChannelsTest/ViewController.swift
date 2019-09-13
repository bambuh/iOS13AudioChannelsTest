import UIKit
import AVFoundation


final class ViewController: UIViewController {

    @IBOutlet weak var audioSessionNOB: UILabel!
    @IBOutlet private weak var buffersNOB: UILabel!

    private let sessionManager = SWAudioSessionManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        sessionManager.numberOfChannelsCallback = { [weak self] numberOfChannels in
            self?.buffersNOB.text = "\(numberOfChannels)"
            self?.audioSessionNOB.text = "\(AVAudioSession.sharedInstance().inputNumberOfChannels)"
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(audioRouteChanged),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)

        if #available(iOS 10.0, *) {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
        } else {
            AVAudioSession.sharedInstance().perform(NSSelectorFromString("setCategory:error:"), with: AVAudioSession.Category.playAndRecord)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        sessionManager.requestAcessAndSetupAudio { [weak self] result in
            guard result == .success else { return }

            self?.sessionManager.startRunning(completion: { error in
                if let error = error {
                    print("Error", error)
                }
            })
        }
    }

    @objc private func audioRouteChanged(notification: Notification) {
        DispatchQueue.main.async {
            let prevRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let prevInput = prevRoute?.inputs.first
            let currentInput = AVAudioSession.sharedInstance().currentRoute.inputs.first

            if let currentInput = currentInput, currentInput.portType == .usbAudio {
                self.sessionManager.refreshAudio(completion: nil)
                return
            }

            if let prevInput = prevInput, prevInput.portType == .usbAudio {
                self.sessionManager.refreshAudio(completion: nil)
                return
            }
        }
    }



}
