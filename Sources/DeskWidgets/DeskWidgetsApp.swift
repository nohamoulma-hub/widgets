import AppKit
import DeskKit
import ProjectsWidget

// Point d'entrée de l'app. Elle n'a ni icône dans le Dock ni fenêtre classique:
// elle ne fait qu'afficher les widgets sur le bureau.
@main
struct DeskWidgetsMain {
    @MainActor
    static func main() {
        // Mode vérification: lit projects.json et affiche le résultat, sans rien ouvrir
        if CommandLine.arguments.contains("--check") {
            exit(ProjectsDeskWidget.check() ? 0 : 1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Une seule copie à la fois: si une autre, plus ancienne, tourne déjà, celle-ci se retire
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != getpid() }
            if others.contains(where: { $0.processIdentifier < getpid() }) { exit(0) }
        }

        WallpaperPalette.shared.start()

        // Pour ajouter un widget: créer sa fiche et son hôte ici, à côté de celui-ci
        let projects = WidgetHost(descriptor: ProjectsDeskWidget.makeDescriptor())
        projects.show()
        // Option de test: déplie le widget une seconde après le démarrage, comme le ferait un clic
        if CommandLine.arguments.contains("--expanded") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                projects.expand()
            }
        }

        withExtendedLifetime(projects) {
            app.run()
        }
    }
}
