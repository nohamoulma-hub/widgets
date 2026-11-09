import AppKit
import SwiftUI
import DeskKit

// Vue racine: affiche le résumé, ou le détail quand le widget est déplié.
struct ProjectsRoot: View {
    @ObservedObject var store: FeedStore<ProjectsFeed>
    @ObservedObject var host: WidgetHostState

    var body: some View {
        ZStack {
            if host.expanded {
                DetailView(store: store, host: host)
            } else {
                CompactView(store: store, host: host)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: host.expanded)
    }
}

// Message affiché tant que le collecteur n'a rien écrit
struct EmptyNotice: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pas encore de données")
                .font(.system(size: 13, weight: .semibold))
            if let message = message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("python3 collector/collect_projects.py")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// Vue résumé: tout se lit d'un coup d'oeil, un clic ouvre le détail.
struct CompactView: View {
    @ObservedObject var store: FeedStore<ProjectsFeed>
    @ObservedObject var host: WidgetHostState
    private let visibleRows = 4

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let feed = store.feed {
                    rows(for: feed)
                } else {
                    EmptyNotice(message: store.problem)
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { host.toggle() }
    }

    // "3 actifs" en gros, "sur 8 projets" en petit
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PROJETS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(headline)
                        .font(DeskTheme.number(26))
                    if let total = store.feed?.summary.total {
                        Text("sur \(total)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    private var headline: String {
        guard let summary = store.feed?.summary else { return "-" }
        return "\(summary.active) \(summary.active > 1 ? "actifs" : "actif")"
    }

    // Les projets les plus récents, une ligne chacun
    @ViewBuilder
    private func rows(for feed: ProjectsFeed) -> some View {
        if feed.projects.isEmpty {
            Text("Aucun projet trouvé")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 9) {
                ForEach(feed.projects.prefix(visibleRows)) { project in
                    CompactRow(project: project)
                }
            }
            if feed.projects.count > visibleRows {
                Text("+ \(feed.projects.count - visibleRows) autres")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Une ligne du résumé: pastille, nom, barre, pourcentage
struct CompactRow: View {
    @ObservedObject private var palette = WallpaperPalette.shared
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: project.status.color(palette))
            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(project.status == .dormant ? Color.secondary : Color.primary)
            Spacer(minLength: 6)
            ProgressBar(progress: project.progress, color: project.status.color(palette))
                .frame(width: 64, height: 5)
            Text(DeskFormat.percent(project.progress))
                .font(DeskTheme.number(12))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// Vue détail: tous les projets, avec tâches, prochaine étape et dernier commit.
struct DetailView: View {
    @ObservedObject private var palette = WallpaperPalette.shared
    @ObservedObject private var launch = LaunchAtLogin.shared
    @ObservedObject var store: FeedStore<ProjectsFeed>
    @ObservedObject var host: WidgetHostState

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let feed = store.feed {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(feed.projects) { project in
                                DetailCard(project: project)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    footer(for: feed)
                } else {
                    EmptyNotice(message: store.problem)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // Un clic sur l'en-tête replie le widget
    private var header: some View {
        HStack {
            Text("Projets")
                .font(DeskTheme.number(22))
            Spacer()
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { host.toggle() }
    }

    // Pied du widget: âge des données (orange après deux heures) et bouton de lancement au démarrage
    private func footer(for feed: ProjectsFeed) -> some View {
        let stale = Date().timeIntervalSince(feed.generatedAt) > 7200
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mis à jour \(DeskFormat.relative(feed.generatedAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(stale ? palette.warning : Color.secondary)
                if stale {
                    Text("Le collecteur ne tourne plus?")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.warning)
                }
                Spacer()
            }
            launchButton
        }
    }

    // Un clic active ou coupe le lancement automatique à l'ouverture de session
    private var launchButton: some View {
        HStack(spacing: 5) {
            Image(systemName: "power")
                .font(.system(size: 10, weight: .bold))
            Text(launch.isEnabled ? "Lancement au démarrage : activé" : "Lancement au démarrage : désactivé")
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(launch.isEnabled ? palette.accent : Color.secondary)
        .contentShape(Rectangle())
        .onTapGesture { launch.toggle() }
    }
}

// La fiche d'un projet dans la vue détail. Un clic ouvre son dossier dans le Finder.
struct DetailCard: View {
    @ObservedObject private var palette = WallpaperPalette.shared
    let project: Project

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                ProgressRing(progress: project.progress, lineWidth: 5, color: project.status.color(palette))
                Text(DeskFormat.percent(project.progress))
                    .font(DeskTheme.number(11))
                    .monospacedDigit()
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(tasksLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let next = project.nextTask {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Suite")
                            .font(.system(size: 11, weight: .semibold))
                        Text(next)
                            .font(.system(size: 11))
                            .lineLimit(2)
                    }
                }
                if let commit = project.lastCommit {
                    Text("\(project.branch ?? "git") \u{00B7} \(commit.subject)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let dirty = project.dirtyFiles, dirty > 0 {
                    Text("\(dirty) \(dirty > 1 ? "fichiers modifiés" : "fichier modifié")")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.warning)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
        }
    }

    // "actif" puis "il y a 2 j" quand la date est connue
    private var statusLine: String {
        guard let date = project.lastActivity else { return project.status.label }
        return "\(project.status.label) \u{00B7} \(DeskFormat.relative(date))"
    }

    private var tasksLine: String {
        guard let done = project.tasksDone, let total = project.tasksTotal else {
            return "Pas de liste de tâches à cocher"
        }
        return "\(done) sur \(total) tâches"
    }
}
