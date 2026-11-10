//
//  MacPlayer.swift
//  WazKit
//
//  The Mac player with the iPhone player's look: AVKit's own controls are off and these are drawn
//  over the video instead — ✕, Picture in Picture, AirPlay, full screen and zoom top left, volume top right,
//  skip back / play / skip ahead in the middle, speed, audio and subtitles bottom right, and the
//  scrubber along the bottom. Double-click (or Z) steps through the zoom levels — fit, fill, cinema (no black bars) — and a
//  trackpad pinch or +/− zooms further.
//  The controls fade out after 3 seconds without the mouse moving, and come back when it moves.
//

#if os(macOS)
import SwiftUI
import AVKit
import Combine

public struct PlayerContainer: View {
    @ObservedObject var controller: PlayerController
    @StateObject private var state = PlaybackState()
    @State private var zoom = Zoom.fit
    private var zoomed: Bool { zoom != .fit }
    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var lastMouse = NSEvent.mouseLocation
    /// The scrubber's position while it is being dragged (0…1).
    @State private var scrubbing: Double?

    public init(controller: PlayerController) { self.controller = controller }

    public var body: some View {
        ZStack {
            PlayerLayerView(player: controller.player, zoom: zoom, state: state,
                            onDoubleClick: { zoom = zoom.next; poke() }, onKey: key)
            controls
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .animation(.easeInOut(duration: 0.5), value: controlsVisible)
        }
        .background(Color.black)
        .onAppear { state.attach(controller.player) }
        .onDisappear { state.detach() }
        // Watch the pointer itself: any movement shows the controls; 3 seconds without one fades them
        // (playing or paused), unless the scrubber is being dragged.
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            let mouse = NSEvent.mouseLocation
            if mouse != lastMouse {
                lastMouse = mouse
                poke()
            } else if scrubbing == nil, controlsVisible, Date().timeIntervalSince(lastActivity) > 3 {
                controlsVisible = false
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    private func poke() {
        lastActivity = Date()
        if !controlsVisible { controlsVisible = true }
    }

    // MARK: Layout

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                circle("xmark", help: "Stop") { controller.stop() }
                capsule {
                    button(state.pictureInPicture ? "pip.exit" : "pip.enter", help: "Picture in Picture") { state.togglePictureInPicture() }
                        .disabled(!state.canPictureInPicture)
                    AirPlayButton(player: controller.player).frame(width: 28, height: 28).help("AirPlay")
                    button(state.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           help: state.isFullScreen ? "Exit Full Screen" : "Full Screen") { state.toggleFullScreen() }
                    button(zoom.symbol, help: zoom.help) { zoom = zoom.next }
                }
                Spacer()
                capsule {
                    CapsuleSlider(value: Binding(get: { Double(state.volume) },
                                                 set: { state.setVolume(Float($0), on: controller.player) }))
                        .frame(width: 140)
                    button(volumeIcon, help: state.volume == 0 ? "Unmute" : "Mute") {
                        state.setVolume(state.volume == 0 ? 1 : 0, on: controller.player)
                    }
                }
            }
            Spacer()
            HStack(spacing: 56) {
                circle("gobackward.10", size: 64, help: "Skip Back 10 Seconds") { controller.skip(-10) }
                circle(controller.isPlaying ? "pause.fill" : "play.fill", size: 92, help: controller.isPlaying ? "Pause" : "Play") {
                    controller.playPause()
                }
                circle("goforward.10", size: 64, help: "Skip Ahead 10 Seconds") { controller.skip(10) }
            }
            Spacer()
            HStack {
                Spacer()
                capsule {
                    menu("gauge.with.dots.needle.67percent", help: "Playback Speed") {
                        ForEach([0.5, 0.75, 1, 1.25, 1.5, 2] as [Float], id: \.self) { rate in
                            Toggle(rate == 1 ? "Normal" : "\(rate.formatted())×", isOn: Binding(
                                get: { state.rate == rate }, set: { _ in state.setRate(rate, on: controller.player) }))
                        }
                    }
                    if let audible = state.audible, audible.options.count > 1 {
                        menu("waveform", help: "Audio") { options(audible, allowsOff: false) }
                    }
                    if let legible = state.legible, !legible.options.isEmpty {
                        menu("captions.bubble", help: "Subtitles") { options(legible, allowsOff: true) }
                    }
                }
            }
            .padding(.bottom, 12)
            scrubber
        }
        // 25 points from the window edges; zoomed, the picture fills the window and they sit at 24 as before.
        .padding(zoomed ? 24 : 25)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private var volumeIcon: String {
        state.volume == 0 ? "speaker.slash.fill" : state.volume < 0.34 ? "speaker.wave.1.fill" : state.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    @ViewBuilder private var scrubber: some View {
        HStack(spacing: 14) {
            if state.duration > 0 {
                let shown = scrubbing.map { $0 * state.duration } ?? state.time
                Text(Self.clock(shown)).monospacedDigit()
                CapsuleSlider(value: Binding(get: { scrubbing ?? (state.time / state.duration) }, set: { scrubbing = $0 }),
                              onEnded: { fraction in
                                  controller.player.seek(to: CMTime(seconds: fraction * state.duration, preferredTimescale: 600))
                                  state.time = fraction * state.duration
                                  scrubbing = nil
                              })
                Text("−" + Self.clock(max(0, state.duration - shown))).monospacedDigit()
            } else {
                Text("LIVE").font(.callout.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
        }
        .font(.title3)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 24)
        .frame(height: 60)
        .chrome(in: Capsule())
    }

    @ViewBuilder private func options(_ group: PlaybackState.Group, allowsOff: Bool) -> some View {
        if allowsOff {
            Toggle("Off", isOn: Binding(get: { group.selected == nil }, set: { _ in state.select(nil, in: group, on: controller.player) }))
        }
        ForEach(group.options, id: \.self) { option in
            Toggle(option.displayName, isOn: Binding(get: { group.selected == option },
                                                     set: { _ in state.select(option, in: group, on: controller.player) }))
        }
    }

    // MARK: Pieces


    private func circle(_ symbol: String, size: CGFloat = 52, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .frame(width: size, height: size)
                .chrome(in: Circle())
                .contentShape(Circle())
        }
        .help(help)
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 22) { content() }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .chrome(in: Capsule())
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .help(help)
    }

    private func menu(_ symbol: String, help: String, @ViewBuilder _ content: () -> some View) -> some View {
        Menu(content: content) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.white)
        .fixedSize()
        .help(help)
    }

    /// Space plays/pauses, ←/→ skip 10 seconds, ↑/↓ volume, F full screen, Z next zoom level, +/− zoom in
    /// and out a step, Esc leaves full screen.
    private func key(_ event: NSEvent) -> Bool {
        poke()
        switch event.keyCode {
        case 49: controller.playPause()
        case 123: controller.skip(-10)
        case 124: controller.skip(10)
        case 126: state.setVolume(min(1, state.volume + 0.1), on: controller.player)
        case 125: state.setVolume(max(0, state.volume - 0.1), on: controller.player)
        case 53: guard state.isFullScreen else { return false }; state.toggleFullScreen()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": state.toggleFullScreen()
            case "z": zoom = zoom.next
            case "=", "+": state.view.flatMap { $0 as? VideoLayerView }?.magnify(by: 1.1)
            case "-": state.view.flatMap { $0 as? VideoLayerView }?.magnify(by: 1 / 1.1)
            default: return false
            }
        }
        return true
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

extension View {
    /// The controls' background: Liquid Glass on macOS 26 and later, a dark translucent fill before that.
    @ViewBuilder func chrome(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(Color(white: 0.13).opacity(0.85), in: shape)
                .overlay(shape.stroke(.white.opacity(0.08)))
        }
    }
}

/// A thin capsule track the drag sets (0…1), like the iPhone player's scrubber and volume.
private struct CapsuleSlider: View {
    @Binding var value: Double
    var onEnded: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white.opacity(0.9)).frame(width: max(8, geometry.size.width * fraction))
            }
            .frame(height: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value = min(max($0.location.x / geometry.size.width, 0), 1) }
                .onEnded { onEnded?(min(max($0.location.x / geometry.size.width, 0), 1)) })
        }
        .frame(height: 28)
    }
}

/// AVKit's AirPlay route button, drawn white without its border.
private struct AirPlayButton: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        view.setRoutePickerButtonColor(.white, for: .normalHighlighted)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

/// What the controls show: time, volume, speed, audio and subtitle choices, Picture in Picture, full screen.
@MainActor
final class PlaybackState: ObservableObject {
    struct Group {
        let group: AVMediaSelectionGroup
        let options: [AVMediaSelectionOption]
        var selected: AVMediaSelectionOption?
    }

    @Published var time: Double = 0
    /// 0 while unknown, and for live streams.
    @Published var duration: Double = 0
    @Published var volume: Float = 1
    @Published var rate: Float = 1
    @Published var audible: Group?
    @Published var legible: Group?
    @Published var isFullScreen = false
    @Published var pictureInPicture = false
    @Published var canPictureInPicture = false

    weak var view: NSView?
    var pipController: AVPictureInPictureController? {
        didSet {
            pipObservers = pipController.map { pip in
                [pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
                     DispatchQueue.main.async { self?.canPictureInPicture = pip.isPictureInPicturePossible } },
                 pip.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] pip, _ in
                     DispatchQueue.main.async { self?.pictureInPicture = pip.isPictureInPictureActive } }]
            } ?? []
        }
    }
    private var pipObservers: [NSKeyValueObservation] = []
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var itemObserver: NSKeyValueObservation?

    func attach(_ player: AVPlayer) {
        guard self.player == nil else { return }
        self.player = player
        volume = player.volume
        rate = player.defaultRate
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = time.seconds.isFinite ? time.seconds : 0
                let duration = player.currentItem?.duration.seconds ?? 0
                self.duration = duration.isFinite ? duration : 0
            }
        }
        itemObserver = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async { self?.loadOptions(player.currentItem) }
        }
    }

    func detach() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemObserver = nil
        player = nil
    }

    private func loadOptions(_ item: AVPlayerItem?) {
        audible = nil
        legible = nil
        guard let item else { return }
        Task {
            guard let asset = item.asset as AVAsset? else { return }
            let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
            let text = try? await asset.loadMediaSelectionGroup(for: .legible)
            guard player?.currentItem === item else { return }
            audible = audio.map { Group(group: $0, options: $0.options, selected: item.currentMediaSelection.selectedMediaOption(in: $0)) }
            // Forced subtitles (foreign-language parts) aren't a choice.
            legible = text.map { group in
                Group(group: group, options: group.options.filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) },
                      selected: item.currentMediaSelection.selectedMediaOption(in: group))
            }
        }
    }

    func select(_ option: AVMediaSelectionOption?, in group: Group, on player: AVPlayer) {
        player.currentItem?.select(option, in: group.group)
        if audible?.group == group.group { audible?.selected = option }
        if legible?.group == group.group { legible?.selected = option }
    }

    func setVolume(_ value: Float, on player: AVPlayer) {
        player.volume = value
        player.isMuted = false
        volume = value
    }

    func setRate(_ value: Float, on player: AVPlayer) {
        player.defaultRate = value
        if player.rate > 0 { player.rate = value }
        rate = value
    }

    func toggleFullScreen() { view?.window?.toggleFullScreen(nil) }

    func togglePictureInPicture() {
        guard let pipController else { return }
        pipController.isPictureInPictureActive ? pipController.stopPictureInPicture() : pipController.startPictureInPicture()
    }
}

/// How the picture sits in the window: the whole movie, filling the window, or filling it with the
/// movie's 2.39:1 cinema band (for wide films delivered with black bars inside a 16:9 video).
enum Zoom {
    case fit, fill, cinema

    var next: Zoom {
        switch self {
        case .fit: .fill
        case .fill: .cinema
        case .cinema: .fit
        }
    }

    var symbol: String {
        switch self {
        case .fit: "arrow.up.left.and.arrow.down.right.rectangle"
        case .fill: "rectangle.expand.vertical"
        case .cinema: "arrow.down.right.and.arrow.up.left.rectangle"
        }
    }

    var help: String {
        switch self {
        case .fit: "Zoom to Fill (double-click or Z)"
        case .fill: "Zoom to Cinema, No Black Bars (double-click or Z)"
        case .cinema: "Fit the Movie (double-click or Z)"
        }
    }
}

/// The video itself (an AVPlayerLayer, so Picture in Picture can be started from our button). It takes
/// keyboard focus as soon as it is on screen, so space/arrows drive playback instead of the sidebar;
/// SwiftUI hands focus back to the sidebar after the first attempt, so it keeps claiming it on layout
/// passes until it holds it, and again whenever the window becomes key or the video is clicked.
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    let zoom: Zoom
    let state: PlaybackState
    let onDoubleClick: () -> Void
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        view.playerLayer.player = player
        view.state = state
        state.view = view
        return view
    }

    func updateNSView(_ view: VideoLayerView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.onKey = onKey
        view.zoom = zoom
    }
}

final class VideoLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    weak var state: PlaybackState?
    var onDoubleClick: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    private var observers: [NSObjectProtocol] = []
    private var claimsLeft = 0
    private var rectObserver: NSKeyValueObservation?

    /// The zoom level; changing it starts over from the level's own size (no pinch).
    var zoom = Zoom.fit {
        didSet { if zoom != oldValue { pinch = 1; applyZoom(animated: true) } }
    }
    /// Pinch (or +/−) on top of the level, 1…4×.
    private var pinch: CGFloat = 1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // The video is a sublayer so it can be scaled past the view's edges (the view clips it).
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        layer = root
        playerLayer.videoGravity = .resizeAspect
        root.addSublayer(playerLayer)
        // The picture's rect is known once the movie loads; size the zoom to it then.
        rectObserver = playerLayer.observe(\.videoRect, options: .new) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyZoom(animated: false) }
        }
    }

    /// Scales the fitted picture: fill covers the window; cinema covers it with the 2.39:1 band in the
    /// middle of the picture, which crops off black bars baked into a 16:9 video.
    private func applyZoom(animated: Bool) {
        let size = bounds.size
        let picture = playerLayer.videoRect
        var scale: CGFloat = 1
        if picture.width > 0, picture.height > 0, size.width > 0, size.height > 0 {
            switch zoom {
            case .fit: scale = 1
            case .fill: scale = max(size.width / picture.width, size.height / picture.height)
            case .cinema:
                let band = min(picture.height, picture.width / 2.39)
                scale = max(size.width / picture.width, size.height / band)
            }
        }
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(0.3) } else { CATransaction.setDisableActions(true) }
        playerLayer.setAffineTransform(CGAffineTransform(scaleX: scale * pinch, y: scale * pinch))
        CATransaction.commit()
    }

    func magnify(by factor: CGFloat) {
        pinch = min(max(pinch * factor, 1), 4)
        applyZoom(animated: false)
    }

    /// Trackpad pinch zooms in and out beyond the level.
    override func magnify(with event: NSEvent) {
        magnify(by: 1 + event.magnification)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    private var hasFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }

    private func claimFocus() {
        guard let window, !hasFocus else { return }
        window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        if state?.pipController == nil { state?.pipController = AVPictureInPictureController(playerLayer: playerLayer) }
        state?.isFullScreen = window.styleMask.contains(.fullScreen)
        claimsLeft = 10
        DispatchQueue.main.async { [weak self] in self?.claimFocus() }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.claimFocus() }
            },
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state?.isFullScreen = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state?.isFullScreen = false }
            },
        ]
    }

    /// Never claims focus inside layout itself: taking focus makes SwiftUI rebuild and lay out the window
    /// synchronously, which re-entered here before the count went down and recursed until the stack ran out.
    /// The count goes down first and the claim waits for the next turn of the run loop.
    override func layout() {
        super.layout()
        // Bounds and position, not frame: frame is undefined while the layer has a transform.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.bounds = bounds
        playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        applyZoom(animated: false)
        guard claimsLeft > 0, !hasFocus else { claimsLeft = 0; return }
        claimsLeft -= 1
        DispatchQueue.main.async { [weak self] in self?.claimFocus() }
    }

    override func mouseDown(with event: NSEvent) {
        claimFocus()
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
#endif
