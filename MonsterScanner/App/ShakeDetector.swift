import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when the player shakes the phone.
    static let deviceDidShake = Notification.Name("MonsterScanner.deviceDidShake")
}

/// SwiftUI has no shake gesture; the window's motion event is the simplest
/// hook. Needs no motion permission.
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension View {
    /// Runs `action` when the phone is shaken.
    func onShake(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in action() }
    }
}
