import SwiftUI

// Les polices et mesures communes à tous les widgets. Les couleurs d'accent viennent de WallpaperPalette.
// Analogie: la charte graphique de la maison, pour que chaque nouveau widget ait le même air de famille.
public enum DeskTheme {
    public static let cornerRadius: CGFloat = 22
    public static let padding: CGFloat = 16
    public static let track = Color.primary.opacity(0.10)

    // Chiffres arrondis, utilisés pour les pourcentages et les gros titres
    public static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

// Petites fonctions de mise en forme en français
public enum DeskFormat {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter
    }()

    // "il y a 3 j", "il y a 2 h"...
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        if abs(date.timeIntervalSince(now)) < 60 { return "à l'instant" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    // "68 %" ou "-" quand il n'y a pas de valeur
    public static func percent(_ value: Double?) -> String {
        guard let value = value else { return "-" }
        return "\(Int((value * 100).rounded()))\u{202F}%"
    }
}

// Barre de progression fine. Sans valeur, seul le rail est dessiné.
public struct ProgressBar: View {
    private let progress: Double?
    private let color: Color

    public init(progress: Double?, color: Color) {
        self.progress = progress
        self.color = color
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(DeskTheme.track)
                if let progress = progress {
                    let ratio = CGFloat(min(max(progress, 0), 1))
                    Capsule()
                        .fill(color)
                        .frame(width: max(geometry.size.height, geometry.size.width * ratio))
                }
            }
        }
    }
}

// Anneau de progression, à poser avec un texte au centre
public struct ProgressRing: View {
    private let progress: Double?
    private let lineWidth: CGFloat
    private let color: Color

    public init(progress: Double?, lineWidth: CGFloat = 5, color: Color) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        ZStack {
            Circle().stroke(DeskTheme.track, lineWidth: lineWidth)
            if let progress = progress {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }
}

// Pastille de couleur pour un état
public struct StatusDot: View {
    private let color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

// Cadre commun d'un widget: marges et fin liseré. Le flou de fond est posé par le panneau.
public struct WidgetCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(DeskTheme.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: DeskTheme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
