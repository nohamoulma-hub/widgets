import AppKit
import ImageIO
import SwiftUI

// Lit les couleurs d'une image réduite pour en tirer la teinte dominante.
// Analogie: on rétrécit le fond d'écran en une mosaïque de 48 pixels, puis on regarde
// quelle couleur revient le plus. Les gris, noirs et blancs sont ignorés.
enum WallpaperSampler {
    // Renvoie la teinte (0 à 1) ou nil si l'image est illisible ou presque sans couleur
    static func dominantHue(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 48
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // 24 cases de 15 degrés; chaque pixel pèse d'autant plus qu'il est vif et clair
        var bins = [Double](repeating: 0, count: 24)
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let high = max(red, green, blue)
            let delta = high - min(red, green, blue)
            if delta == 0 || high < 0.2 { continue }
            let saturation = delta / high
            if saturation < 0.18 { continue }

            var hue: Double
            if high == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if high == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }

            let weight = saturation * high
            bins[min(Int(hue / 15), 23)] += weight
            total += weight
        }

        // Fond d'écran presque gris: on laisse la couleur par défaut
        if total < Double(width * height) * 0.03 { return nil }

        // On lisse avec les cases voisines pour ne pas dépendre d'une frontière entre deux cases
        var bestIndex = 0
        var bestScore = -1.0
        for index in 0..<24 {
            let before = bins[(index + 23) % 24]
            let after = bins[(index + 1) % 24]
            let score = bins[index] + 0.5 * (before + after)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return (Double(bestIndex) + 0.5) * 15 / 360
    }
}

// La couleur d'accent des widgets, tirée du fond d'écran.
// Elle se met à jour quand le fond d'écran change, et s'adapte au mode clair ou sombre.
// Le orange d'avertissement reste orange (il garde son sens), sauf si l'accent lui ressemble trop.
@MainActor
public final class WallpaperPalette: ObservableObject {
    public static let shared = WallpaperPalette()

    @Published public private(set) var accent: Color
    @Published public private(set) var warning: Color

    // Vert d'eau: la couleur utilisée quand le fond d'écran n'a pas de couleur exploitable
    private static let defaultHue = 0.46
    private static let followKey = "DeskWidgets.followWallpaper"

    private var lastStamp: String?
    private var timer: Timer?
    private var spaceObserver: NSObjectProtocol?

    // Choix de l'utilisateur, retenu d'une fois sur l'autre (menu clic droit)
    public var followsWallpaper: Bool {
        get { UserDefaults.standard.object(forKey: Self.followKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.followKey)
            lastStamp = nil
            refresh()
        }
    }

    private init() {
        let colors = Self.makeColors(hue: Self.defaultHue)
        accent = colors.accent
        warning = colors.warning
    }

    // Analyse le fond d'écran maintenant, puis surveille ses changements
    public func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // Ne refait l'analyse que si le fichier du fond d'écran a changé
    public func refresh() {
        guard followsWallpaper,
              let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else {
            apply(hue: Self.defaultHue)
            return
        }
        let stamp = Self.stamp(of: url)
        if stamp == lastStamp { return }
        lastStamp = stamp
        Task { @MainActor in
            let hue = await Task.detached(priority: .utility) {
                WallpaperSampler.dominantHue(of: url)
            }.value
            self.apply(hue: hue ?? Self.defaultHue)
        }
    }

    private func apply(hue: Double) {
        let colors = Self.makeColors(hue: hue)
        withAnimation(.easeInOut(duration: 0.6)) {
            accent = colors.accent
            warning = colors.warning
        }
    }

    // Chemin du fichier + date de modification: change quand le fond d'écran change
    private static func stamp(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let seconds = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return url.path + "|" + String(seconds)
    }

    // Accent à la teinte du fond d'écran; avertissement orange, ou rouge si l'accent est déjà orange
    private static func makeColors(hue: Double) -> (accent: Color, warning: Color) {
        let amber = 0.095
        let gap = abs(hue - amber)
        let warningHue = min(gap, 1 - gap) < 0.06 ? 0.0 : amber
        return (
            dynamic(hue: hue, light: (0.70, 0.62), dark: (0.55, 0.88)),
            dynamic(hue: warningHue, light: (0.85, 0.82), dark: (0.75, 0.95))
        )
    }

    // Une couleur qui change toute seule entre mode clair et mode sombre
    private static func dynamic(hue: Double, light: (CGFloat, CGFloat), dark: (CGFloat, CGFloat)) -> Color {
        let hueValue = CGFloat(hue)
        let color = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let tone = isDark ? dark : light
            return NSColor(hue: hueValue, saturation: tone.0, brightness: tone.1, alpha: 1)
        }
        return Color(nsColor: color)
    }
}
