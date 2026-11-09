import AppKit
import Combine
import SwiftUI

// Fenêtre sans bordure posée sur le bureau: au-dessus des icônes, sous toutes les autres fenêtres.
// Elle ne prend jamais le focus, donc cliquer dessus ne dérange pas l'app que tu utilises.
final class DesktopPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    convenience init(size: CGSize) {
        self.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Vue SwiftUI qui accepte le clic même quand sa fenêtre n'est pas au premier plan,
// et qui déplace la fenêtre quand on la fait glisser.
// Le glisser est géré ici plutôt que par macOS, car un clic sur le widget
// (pour le déplier) et un glisser (pour le déplacer) se confondraient sinon.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var dragState: WidgetHostState?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // On note d'où part le geste, puis on laisse SwiftUI voir l'appui
    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        isDragging = false
        super.mouseDown(with: event)
    }

    // Au-delà de 4 points de mouvement, ce n'est plus un clic: on déplace la fenêtre
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = windowStart, let window = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        if !isDragging && hypot(dx, dy) < 4 { return }
        isDragging = true
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    // Après un glisser, on le signale pour que le relâchement ne soit pas pris pour un clic
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            dragState?.markDragEnd()
            isDragging = false
        }
        super.mouseUp(with: event)
    }
}

// Fond flouté aux coins arrondis, qui laisse deviner le fond d'écran derrière.
enum PanelChrome {
    static func makeBackground(radius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = roundedMask(radius: radius)
        return view
    }

    // Image-gabarit qui s'étire en gardant les coins ronds
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// État partagé entre la fenêtre et la vue: le widget est-il déplié?
@MainActor
public final class WidgetHostState: ObservableObject {
    @Published public var expanded = false
    private var lastDragEnd = Date.distantPast

    public init() {}

    // Un clic déplie ou replie, sauf s'il vient juste de terminer un glisser
    public func toggle() {
        if Date().timeIntervalSince(lastDragEnd) < 0.3 { return }
        expanded.toggle()
    }

    func markDragEnd() {
        lastDragEnd = Date()
    }
}

// Tout ce qu'il faut savoir d'un widget pour l'afficher.
// Pour créer un nouveau widget, on fournit simplement une de ces fiches.
public struct DeskWidgetDescriptor {
    public let id: String
    public let compactSize: CGSize
    public let detailSize: CGSize
    public let makeRoot: @MainActor (WidgetHostState) -> AnyView
    public let refresh: (@MainActor () -> Void)?

    public init(
        id: String,
        compactSize: CGSize,
        detailSize: CGSize,
        refresh: (@MainActor () -> Void)? = nil,
        makeRoot: @escaping @MainActor (WidgetHostState) -> AnyView
    ) {
        self.id = id
        self.compactSize = compactSize
        self.detailSize = detailSize
        self.refresh = refresh
        self.makeRoot = makeRoot
    }
}

// Cible du menu clic droit (les menus AppKit ont besoin d'un objet Objective-C)
@MainActor
final class MenuActions: NSObject {
    private let refresh: (@MainActor () -> Void)?

    init(refresh: (@MainActor () -> Void)?) {
        self.refresh = refresh
        super.init()
    }

    @objc func refreshNow() {
        refresh?()
    }

    // Active ou coupe le lancement à l'ouverture de session, et met la coche à jour
    @objc func toggleLaunch(_ sender: NSMenuItem) {
        let launch = LaunchAtLogin.shared
        launch.toggle()
        sender.state = launch.isEnabled ? .on : .off
    }

    // Active ou coupe les couleurs tirées du fond d'écran, et met la coche à jour
    @objc func toggleWallpaper(_ sender: NSMenuItem) {
        let palette = WallpaperPalette.shared
        palette.followsWallpaper.toggle()
        sender.state = palette.followsWallpaper ? .on : .off
    }
}

// Remet les coches du menu à jour à chaque ouverture (le bouton du widget peut avoir changé l'état)
extension MenuActions: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if item.tag == 1 { item.state = WallpaperPalette.shared.followsWallpaper ? .on : .off }
            if item.tag == 2 { item.state = LaunchAtLogin.shared.isEnabled ? .on : .off }
        }
    }
}

// Le chef d'orchestre d'un widget: crée la fenêtre, la place, la redimensionne
// quand on clique, et retient sa position d'une fois sur l'autre.
@MainActor
public final class WidgetHost {
    private let descriptor: DeskWidgetDescriptor
    private let panel: DesktopPanel
    private let state: WidgetHostState
    private let actions: MenuActions
    private var expansion: AnyCancellable?

    public init(descriptor: DeskWidgetDescriptor) {
        let state = WidgetHostState()
        let panel = DesktopPanel(size: descriptor.compactSize)
        let actions = MenuActions(refresh: descriptor.refresh)

        // Fond flou avec le contenu SwiftUI par-dessus, collé aux quatre bords
        let background = PanelChrome.makeBackground(radius: DeskTheme.cornerRadius)
        let content = FirstMouseHostingView(rootView: descriptor.makeRoot(state))
        content.sizingOptions = []
        content.dragState = state
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background

        // Menu clic droit: actualiser et quitter
        let menu = WidgetHost.makeMenu(actions: actions)
        background.menu = menu
        content.menu = menu

        self.descriptor = descriptor
        self.panel = panel
        self.state = state
        self.actions = actions

        placePanel()
        expansion = state.$expanded.dropFirst().sink { [weak self] expanded in
            self?.applySize(expanded: expanded, animated: true)
        }
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    // Déplie le widget (option --expanded au lancement, pratique pour les tests)
    public func expand() {
        state.expanded = true
    }

    // Retrouve la position précédente, ou se range en haut à droite au premier lancement
    private func placePanel() {
        let name = "DeskWidgets." + descriptor.id
        let savedKey = "NSWindow Frame " + name
        let firstLaunch = UserDefaults.standard.string(forKey: savedKey) == nil
        _ = panel.setFrameAutosaveName(name)
        if firstLaunch, let screen = NSScreen.main {
            let area = screen.visibleFrame
            let size = descriptor.compactSize
            let origin = NSPoint(x: area.maxX - size.width - 24, y: area.maxY - size.height - 24)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        applySize(expanded: false, animated: false)
    }

    // Change la taille en gardant le coin haut gauche en place, sans sortir de l'écran
    private func applySize(expanded: Bool, animated: Bool) {
        let size = expanded ? descriptor.detailSize : descriptor.compactSize
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        if let area = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if frame.minY < area.minY { frame.origin.y = area.minY }
            if frame.maxX > area.maxX { frame.origin.x = area.maxX - size.width }
        }
        panel.setFrame(frame, display: true, animate: animated)
        panel.invalidateShadow()
    }

    private static func makeMenu(actions: MenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = actions
        let refresh = NSMenuItem(title: "Actualiser", action: #selector(MenuActions.refreshNow), keyEquivalent: "")
        refresh.target = actions
        menu.addItem(refresh)
        let wallpaper = NSMenuItem(title: "Couleurs du fond d'écran", action: #selector(MenuActions.toggleWallpaper(_:)), keyEquivalent: "")
        wallpaper.target = actions
        wallpaper.tag = 1
        wallpaper.state = WallpaperPalette.shared.followsWallpaper ? .on : .off
        menu.addItem(wallpaper)
        let launch = NSMenuItem(title: "Lancer au démarrage", action: #selector(MenuActions.toggleLaunch(_:)), keyEquivalent: "")
        launch.target = actions
        launch.tag = 2
        launch.state = LaunchAtLogin.shared.isEnabled ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }
}
