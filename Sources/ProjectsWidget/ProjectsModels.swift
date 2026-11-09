import Foundation
import SwiftUI
import DeskKit

// Le contenu de projects.json, tel que le collecteur l'écrit.
public struct ProjectsFeed: Decodable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let summary: ProjectsSummary
    public let projects: [Project]
}

public struct ProjectsSummary: Decodable {
    public let total: Int
    public let active: Int
    public let quiet: Int
    public let dormant: Int
    public let unknown: Int
    public let averageProgress: Double?
}

// Un état inconnu du widget retombe sur "unknown" au lieu de faire échouer la lecture
public enum ProjectStatus: String, Decodable {
    case active
    case quiet
    case dormant
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProjectStatus(rawValue: raw) ?? .unknown
    }
}

public struct ProjectCommit: Decodable {
    public let subject: String
    public let date: Date
}

public struct Project: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let path: String
    public let status: ProjectStatus
    public let progress: Double?
    public let tasksDone: Int?
    public let tasksTotal: Int?
    public let nextTask: String?
    public let progressSource: String?
    public let lastActivity: Date?
    public let lastCommit: ProjectCommit?
    public let branch: String?
    public let dirtyFiles: Int?
}

// Couleur (tirée de la palette du fond d'écran) et libellé de chaque état
extension ProjectStatus {
    @MainActor
    func color(_ palette: WallpaperPalette) -> Color {
        switch self {
        case .active: return palette.accent
        case .quiet: return palette.warning
        case .dormant: return Color.secondary.opacity(0.55)
        case .unknown: return Color.secondary.opacity(0.35)
        }
    }

    var label: String {
        switch self {
        case .active: return "actif"
        case .quiet: return "calme"
        case .dormant: return "en veille"
        case .unknown: return "sans date"
        }
    }
}
