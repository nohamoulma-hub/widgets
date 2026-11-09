import Foundation
import SwiftUI
import DeskKit

// Point d'entrée du widget Projets: prépare la lecture des données et la fiche d'affichage.
@MainActor
public enum ProjectsDeskWidget {
    private static let collectorLabel = "com.noham.deskwidgets.collector"

    public static func makeDescriptor() -> DeskWidgetDescriptor {
        let store = FeedStore<ProjectsFeed>(url: DeskPaths.feed(named: "projects.json"))
        store.start()
        return DeskWidgetDescriptor(
            id: "projects",
            compactSize: CGSize(width: 320, height: 216),
            detailSize: CGSize(width: 420, height: 600),
            refresh: { refreshNow(store: store) },
            makeRoot: { host in AnyView(ProjectsRoot(store: store, host: host)) }
        )
    }

    // Relance le collecteur s'il est installé comme tâche de fond, puis relit le fichier
    private static func refreshNow(store: FeedStore<ProjectsFeed>) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(collectorLabel)"]
        try? process.run()
        store.reload()
    }

    // Lecture du fichier sans ouvrir de fenêtre: `DeskWidgets --check` dans le Terminal
    public static func check() -> Bool {
        let url = DeskPaths.feed(named: "projects.json")
        do {
            let data = try Data(contentsOf: url)
            let feed = try DeskJSON.makeDecoder().decode(ProjectsFeed.self, from: data)
            print("OK: \(feed.projects.count) projets lus dans \(url.path)")
            for project in feed.projects {
                print("  \(project.status.label)  \(DeskFormat.percent(project.progress))  \(project.name)")
            }
            return true
        } catch {
            print("ERREUR: \(error)")
            return false
        }
    }
}
