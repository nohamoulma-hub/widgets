import AppKit
import SwiftUI

// Lancement automatique à l'ouverture de session, avec un interrupteur.
// Analogie: c'est l'interrupteur du réveil. Activer, c'est poser une consigne
// "démarre cette app à chaque ouverture de session" auprès de macOS (un fichier dans
// ~/Library/LaunchAgents). Désactiver, c'est retirer cette consigne.
// Même fichier que celui de scripts/install_agents.sh: les deux se répondent.
@MainActor
public final class LaunchAtLogin: ObservableObject {
    public static let shared = LaunchAtLogin()

    @Published public private(set) var isEnabled: Bool

    private static let label = "com.noham.deskwidgets.app"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private init() {
        isEnabled = FileManager.default.fileExists(atPath: Self.plistURL.path)
    }

    // Bascule: activé devient désactivé, et inversement
    public func toggle() {
        setEnabled(!isEnabled)
    }

    // Écrit ou supprime la consigne. L'app en cours n'est pas touchée:
    // le changement s'applique à la prochaine ouverture de session.
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            writePlist()
        } else {
            try? FileManager.default.removeItem(at: Self.plistURL)
        }
        isEnabled = FileManager.default.fileExists(atPath: Self.plistURL.path)
    }

    // La consigne pointe vers le programme dans le .app. Hors d'un .app (swift run), rien n'est écrit.
    private func writePlist() {
        guard Bundle.main.bundlePath.hasSuffix(".app"), let executable = Bundle.main.executablePath else {
            NSLog("DeskKit: lancement automatique impossible hors d'une app .app")
            return
        }
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]
        do {
            let folder = Self.plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: Self.plistURL, options: .atomic)
        } catch {
            NSLog("DeskKit: écriture du lancement automatique impossible: %@", String(describing: error))
        }
    }
}
