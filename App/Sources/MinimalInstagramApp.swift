import AVFoundation
import SwiftUI

@main
struct MinimalInstagramApp: App {
    init() {
        configureAudioPlayback()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    private func configureAudioPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
}
