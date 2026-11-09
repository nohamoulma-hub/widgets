import Foundation
import SwiftUI

// Où se trouvent les fichiers de données des widgets.
public enum DeskPaths {
    // ~/Library/Application Support/DeskWidgets
    public static var dataDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskWidgets", isDirectory: true)
    }

    public static func feed(named name: String) -> URL {
        dataDirectory.appendingPathComponent(name)
    }
}

// Lecture des fichiers JSON: clés en snake_case et dates ISO 8601.
public enum DeskJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { inner in
            let text = try inner.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: text) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: inner.codingPath, debugDescription: "Date illisible: \(text)")
            )
        }
        return decoder
    }
}

// Garde en mémoire le contenu d'un fichier JSON et se met à jour tout seul.
// Analogie: une boîte aux lettres avec une sonnette. Quand le collecteur dépose une
// nouvelle lettre, le widget est prévenu et relit. Une relecture toutes les minutes
// sert de filet de sécurité si la sonnette n'a pas sonné.
@MainActor
public final class FeedStore<Feed: Decodable>: ObservableObject {
    @Published public private(set) var feed: Feed?
    @Published public private(set) var problem: String?

    private let url: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?

    public init(url: URL) {
        self.url = url
    }

    // Lit une première fois puis surveille le dossier et la minuterie
    public func start() {
        reload()
        watchFolder()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // Relit le fichier. En cas d'échec, on garde les dernières données valides.
    public func reload() {
        guard let data = try? Data(contentsOf: url) else {
            if feed == nil { problem = "Le fichier de données n'existe pas encore." }
            return
        }
        do {
            feed = try DeskJSON.makeDecoder().decode(Feed.self, from: data)
            problem = nil
        } catch {
            NSLog("DeskKit: lecture impossible de %@: %@", url.path, String(describing: error))
            problem = "Le fichier de données est illisible."
        }
    }

    // Le collecteur remplace le fichier par un renommage: on surveille donc le dossier, pas le fichier.
    private func watchFolder() {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        watcher = source
    }
}
