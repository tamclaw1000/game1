import SwiftUI

struct GameView: View {
    @StateObject private var model = GameModel()
    @State private var palette: GamePalette = .classic
    @State private var showHistory = false

    var body: some View {
        ZStack {
            palette.gameBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header

                BoardView(
                    tiles: model.tiles,
                    width: model.boardWidth,
                    height: model.boardHeight,
                    palette: palette
                )
                .gesture(swipeGesture)
                .accessibilityLabel("2048 board")
                .overlay(keyboardHandler)

                controls

                Text("Version \(GameModel.appVersion)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            .padding()
            .frame(maxWidth: 560)

            if model.hasWon {
                overlay(title: "2048!", message: "You reached the target tile.", primaryTitle: "Continue") {
                    model.continueAfterWin()
                }
            } else if model.isGameOver {
                overlay(title: "Game over", message: "No more moves are available.", primaryTitle: "New game") {
                    model.startNewGame()
                }
            }
        }
        .tint(palette.accent)
        .sheet(isPresented: $showHistory) {
            HistoryView(history: model.gameHistory, palette: palette)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text("2048")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(palette.primaryText)

            Spacer()

            ScorePill(title: "Score", value: model.score, palette: palette)
            ScorePill(title: "Best", value: model.bestScore, palette: palette)
            ScorePill(title: "Highest", value: model.highestTile, palette: palette)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button("New Game") {
                    model.startNewGame()
                }
                .buttonStyle(.borderedProminent)

                Button("History") {
                    showHistory = true
                }
                .buttonStyle(.bordered)

                Toggle("Wrap", isOn: Binding(
                    get: { model.wrapsAround },
                    set: { model.setWrapsAround($0) }
                ))
                .toggleStyle(.switch)
                .foregroundStyle(palette.primaryText)
                .fixedSize()

                Toggle("Auto", isOn: Binding(
                    get: { model.isAutoplaying },
                    set: { model.setAutoplaying($0) }
                ))
                .toggleStyle(.switch)
                .foregroundStyle(palette.primaryText)
                .fixedSize()

                Spacer()
            }

            HStack(spacing: 10) {
                Text("Speed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                Slider(
                    value: Binding(
                        get: { model.autoplaySpeed },
                        set: { model.setAutoplaySpeed($0) }
                    ),
                    in: GameModel.minimumAutoplaySpeed...GameModel.maximumAutoplaySpeed,
                    step: 1
                )

                Text("\(Int(model.autoplaySpeed))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Stepper(
                    "Width \(model.boardWidth)",
                    value: Binding(
                        get: { model.boardWidth },
                        set: { model.updateBoardSize(width: $0) }
                    ),
                    in: GameModel.minimumBoardSide...GameModel.maximumBoardSide
                )

                Stepper(
                    "Height \(model.boardHeight)",
                    value: Binding(
                        get: { model.boardHeight },
                        set: { model.updateBoardSize(height: $0) }
                    ),
                    in: GameModel.minimumBoardSide...GameModel.maximumBoardSide
                )
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.primaryText)

            HStack(spacing: 8) {
                Text("Color")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                ForEach(GamePalette.allCases) { option in
                    Button(option.name) {
                        palette = option
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(option == palette ? palette.selectedControlText : palette.primaryText)
                    .frame(minWidth: 86)
                    .padding(.vertical, 8)
                    .background(
                        option == palette ? palette.accent : palette.unselectedControlBackground,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(palette.controlsBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                let direction: MoveDirection

                if abs(width) > abs(height) {
                    direction = width > 0 ? .right : .left
                } else {
                    direction = height > 0 ? .down : .up
                }

                model.move(direction)
            }
    }

    @ViewBuilder
    private var keyboardHandler: some View {
        #if os(macOS)
        KeyboardMoveView { direction in
            model.move(direction)
        }
        #else
        EmptyView()
        #endif
    }

    private func overlay(
        title: String,
        message: String,
        primaryTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(palette.primaryText)

                Text(message)
                    .font(.headline)
                    .foregroundStyle(palette.secondaryText)

                HStack(spacing: 12) {
                    Button(primaryTitle) {
                        action()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("New Game") {
                        model.startNewGame()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(24)
        }
    }
}

private struct BoardView: View {
    let tiles: [GameTile]
    let width: Int
    let height: Int
    let palette: GamePalette

    var body: some View {
        GeometryReader { proxy in
            let spacing = cellSpacing(for: proxy.size)
            let maxTileWidth = (proxy.size.width - spacing * CGFloat(width + 1)) / CGFloat(width)
            let maxTileHeight = (proxy.size.height - spacing * CGFloat(height + 1)) / CGFloat(height)
            let tileSide = max(0.05, min(maxTileWidth, maxTileHeight))
            let boardWidth = tileSide * CGFloat(width) + spacing * CGFloat(width + 1)
            let boardHeight = tileSide * CGFloat(height) + spacing * CGFloat(height + 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.boardBackground)

                GridBackground(
                    width: width,
                    height: height,
                    tileSide: tileSide,
                    spacing: spacing,
                    color: palette.emptyTile
                )

                ForEach(tiles) { tile in
                    TileView(tile: tile, palette: palette)
                        .frame(width: tileSide, height: tileSide)
                        .position(
                            x: cellX(column: tile.column, tileSide: tileSide, spacing: spacing),
                            y: cellY(row: tile.row, tileSide: tileSide, spacing: spacing)
                        )
                        .scaleEffect(tile.isMerged ? 1.08 : 1)
                        .transition(.asymmetric(insertion: .scale(scale: 0.24).combined(with: .opacity), removal: .opacity))
                        .zIndex(tile.isMerged ? 2 : 1)
                }
            }
            .frame(width: boardWidth, height: boardHeight)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(CGFloat(width) / CGFloat(height), contentMode: .fit)
        .frame(maxHeight: 480)
    }

    private func cellSpacing(for size: CGSize) -> CGFloat {
        let denseSpacing = min(size.width / CGFloat(max(width, 1)) / 7, size.height / CGFloat(max(height, 1)) / 7)
        return min(10, max(0.15, denseSpacing))
    }

    private func cellX(column: Int, tileSide: CGFloat, spacing: CGFloat) -> CGFloat {
        spacing + tileSide / 2 + CGFloat(column) * (tileSide + spacing)
    }

    private func cellY(row: Int, tileSide: CGFloat, spacing: CGFloat) -> CGFloat {
        spacing + tileSide / 2 + CGFloat(row) * (tileSide + spacing)
    }
}

private struct GridBackground: View {
    let width: Int
    let height: Int
    let tileSide: CGFloat
    let spacing: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            if tileSide < 2 {
                let rect = CGRect(x: spacing, y: spacing, width: max(0, size.width - spacing * 2), height: max(0, size.height - spacing * 2))
                context.fill(Path(rect), with: .color(color))
                return
            }

            for row in 0..<height {
                for column in 0..<width {
                    let rect = CGRect(
                        x: spacing + CGFloat(column) * (tileSide + spacing),
                        y: spacing + CGFloat(row) * (tileSide + spacing),
                        width: tileSide,
                        height: tileSide
                    )
                    let path = Path(roundedRect: rect, cornerRadius: min(6, tileSide * 0.2))
                    context.fill(path, with: .color(color))
                }
            }
        }
    }
}

private struct TileView: View {
    let tile: GameTile
    let palette: GamePalette

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(palette.tileColor(for: tile.value))
            .overlay {
                Text("\(tile.value)")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.05)
                    .lineLimit(1)
                    .foregroundStyle(palette.tileTextColor(for: tile.value))
                    .padding(4)
            }
            .help("\(tile.value)")
            .accessibilityLabel("\(tile.value)")
    }
}

private struct ScorePill: View {
    let title: String
    let value: Int
    let palette: GamePalette

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.lightText.opacity(0.78))

            Text("\(value)")
                .font(.headline.weight(.black))
                .foregroundStyle(palette.lightText)
                .monospacedDigit()
        }
        .frame(minWidth: 74)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.scoreBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum GamePalette: String, CaseIterable, Identifiable {
    case classic
    case ocean
    case highContrast

    var id: Self { self }

    var name: String {
        switch self {
        case .classic:
            return "Classic"
        case .ocean:
            return "Ocean"
        case .highContrast:
            return "Contrast"
        }
    }

    var gameBackground: Color {
        switch self {
        case .classic:
            return Color(red: 0.96, green: 0.94, blue: 0.88)
        case .ocean:
            return Color(red: 0.91, green: 0.97, blue: 0.97)
        case .highContrast:
            return Color(red: 0.08, green: 0.09, blue: 0.10)
        }
    }

    var boardBackground: Color {
        switch self {
        case .classic:
            return Color(red: 0.62, green: 0.55, blue: 0.48)
        case .ocean:
            return Color(red: 0.16, green: 0.42, blue: 0.50)
        case .highContrast:
            return Color(red: 0.22, green: 0.24, blue: 0.27)
        }
    }

    var emptyTile: Color {
        switch self {
        case .classic:
            return Color(red: 0.74, green: 0.68, blue: 0.60)
        case .ocean:
            return Color(red: 0.70, green: 0.85, blue: 0.86)
        case .highContrast:
            return Color(red: 0.36, green: 0.38, blue: 0.42)
        }
    }

    var scoreBackground: Color {
        switch self {
        case .classic:
            return Color(red: 0.49, green: 0.43, blue: 0.37)
        case .ocean:
            return Color(red: 0.05, green: 0.27, blue: 0.34)
        case .highContrast:
            return Color(red: 0.01, green: 0.01, blue: 0.01)
        }
    }

    var controlsBackground: Color {
        switch self {
        case .classic:
            return Color(red: 0.88, green: 0.84, blue: 0.75)
        case .ocean:
            return Color(red: 0.72, green: 0.87, blue: 0.88)
        case .highContrast:
            return Color(red: 0.20, green: 0.22, blue: 0.25)
        }
    }

    var unselectedControlBackground: Color {
        switch self {
        case .classic:
            return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .ocean:
            return Color(red: 0.89, green: 0.97, blue: 0.97)
        case .highContrast:
            return Color(red: 0.34, green: 0.36, blue: 0.40)
        }
    }

    var selectedControlText: Color {
        switch self {
        case .classic, .ocean:
            return Color.white
        case .highContrast:
            return Color.black
        }
    }

    var primaryText: Color {
        switch self {
        case .classic:
            return Color(red: 0.42, green: 0.36, blue: 0.30)
        case .ocean:
            return Color(red: 0.04, green: 0.24, blue: 0.31)
        case .highContrast:
            return Color.white
        }
    }

    var secondaryText: Color {
        switch self {
        case .classic:
            return Color(red: 0.48, green: 0.43, blue: 0.37)
        case .ocean:
            return Color(red: 0.11, green: 0.36, blue: 0.42)
        case .highContrast:
            return Color(red: 0.78, green: 0.82, blue: 0.87)
        }
    }

    var lightText: Color {
        switch self {
        case .classic, .ocean:
            return Color(red: 0.98, green: 0.96, blue: 0.91)
        case .highContrast:
            return Color.black
        }
    }

    var accent: Color {
        switch self {
        case .classic:
            return Color(red: 0.78, green: 0.40, blue: 0.22)
        case .ocean:
            return Color(red: 0.04, green: 0.48, blue: 0.58)
        case .highContrast:
            return Color(red: 1.00, green: 0.86, blue: 0.12)
        }
    }

    func tileColor(for value: Int) -> Color {
        switch self {
        case .classic:
            return classicTileColor(for: value)
        case .ocean:
            return oceanTileColor(for: value)
        case .highContrast:
            return contrastTileColor(for: value)
        }
    }

    func tileTextColor(for value: Int) -> Color {
        switch self {
        case .classic:
            return value <= 4 ? primaryText : lightText
        case .ocean:
            return value <= 8 ? primaryText : lightText
        case .highContrast:
            switch value {
            case 2...32:
                return Color.black
            default:
                return Color.white
            }
        }
    }

    private func classicTileColor(for value: Int) -> Color {
        switch value {
        case 2:
            return Color(red: 0.93, green: 0.89, blue: 0.82)
        case 4:
            return Color(red: 0.90, green: 0.83, blue: 0.72)
        case 8:
            return Color(red: 0.91, green: 0.58, blue: 0.36)
        case 16:
            return Color(red: 0.90, green: 0.43, blue: 0.28)
        case 32:
            return Color(red: 0.86, green: 0.32, blue: 0.30)
        case 64:
            return Color(red: 0.78, green: 0.20, blue: 0.22)
        case 128:
            return Color(red: 0.85, green: 0.70, blue: 0.34)
        case 256:
            return Color(red: 0.77, green: 0.61, blue: 0.25)
        case 512:
            return Color(red: 0.47, green: 0.66, blue: 0.43)
        case 1024:
            return Color(red: 0.25, green: 0.56, blue: 0.55)
        default:
            return Color(red: 0.21, green: 0.41, blue: 0.57)
        }
    }

    private func oceanTileColor(for value: Int) -> Color {
        switch value {
        case 2:
            return Color(red: 0.77, green: 0.92, blue: 0.91)
        case 4:
            return Color(red: 0.61, green: 0.85, blue: 0.84)
        case 8:
            return Color(red: 0.34, green: 0.68, blue: 0.73)
        case 16:
            return Color(red: 0.19, green: 0.55, blue: 0.64)
        case 32:
            return Color(red: 0.11, green: 0.43, blue: 0.56)
        case 64:
            return Color(red: 0.07, green: 0.33, blue: 0.48)
        case 128:
            return Color(red: 0.31, green: 0.57, blue: 0.42)
        case 256:
            return Color(red: 0.46, green: 0.64, blue: 0.31)
        case 512:
            return Color(red: 0.63, green: 0.56, blue: 0.28)
        case 1024:
            return Color(red: 0.72, green: 0.43, blue: 0.28)
        default:
            return Color(red: 0.78, green: 0.28, blue: 0.28)
        }
    }

    private func contrastTileColor(for value: Int) -> Color {
        switch value {
        case 2:
            return Color(red: 0.98, green: 0.98, blue: 0.98)
        case 4:
            return Color(red: 0.86, green: 0.91, blue: 1.00)
        case 8:
            return Color(red: 0.56, green: 0.83, blue: 1.00)
        case 16:
            return Color(red: 0.22, green: 0.72, blue: 1.00)
        case 32:
            return Color(red: 0.15, green: 0.94, blue: 0.67)
        case 64:
            return Color(red: 0.49, green: 1.00, blue: 0.39)
        case 128:
            return Color(red: 1.00, green: 0.86, blue: 0.12)
        case 256:
            return Color(red: 1.00, green: 0.65, blue: 0.16)
        case 512:
            return Color(red: 1.00, green: 0.41, blue: 0.24)
        case 1024:
            return Color(red: 1.00, green: 0.31, blue: 0.55)
        default:
            return Color(red: 0.86, green: 0.45, blue: 1.00)
        }
    }
}

#if os(macOS)
import AppKit

private struct KeyboardMoveView: NSViewRepresentable {
    let onMove: (MoveDirection) -> Void

    func makeNSView(context: Context) -> KeyCatchingView {
        let view = KeyCatchingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: KeyCatchingView, context: Context) {
        nsView.onMove = onMove
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCatchingView: NSView {
    var onMove: ((MoveDirection) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onMove?(.left)
        case 124:
            onMove?(.right)
        case 125:
            onMove?(.down)
        case 126:
            onMove?(.up)
        default:
            super.keyDown(with: event)
        }
    }
}
#endif

private struct HistoryView: View {
    let history: [GameRecord]
    let palette: GamePalette

    var body: some View {
        VStack(spacing: 0) {
            Text("Game History")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(palette.primaryText)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if history.isEmpty {
                Spacer()
                Text("No games played yet")
                    .font(.headline)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(history.reversed()) { record in
                            HistoryRow(record: record, palette: palette)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 420, height: 400)
        .background(palette.gameBackground)
    }
}

private struct HistoryRow: View {
    let record: GameRecord
    let palette: GamePalette

    private var configLabel: String {
        let board = "\(record.boardWidth)×\(record.boardHeight)"
        let wrap = record.wrapsAround ? " wrap" : ""
        let auto = record.wasAutoplay ? " auto" : ""
        return board + wrap + auto
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date, style: .time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Text(configLabel)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 10) {
                    Stat(value: record.score, label: "Score", palette: palette)
                    Stat(value: record.highestTile, label: "Tile", palette: palette)
                    Stat(value: record.moveCount, label: "Moves", palette: palette)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.controlsBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    let palette: GamePalette

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.callout.weight(.black))
                .foregroundStyle(palette.primaryText)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9).weight(.bold))
                .foregroundStyle(palette.secondaryText)
        }
    }
}
