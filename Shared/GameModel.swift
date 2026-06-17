import SwiftUI

enum MoveDirection {
    case up
    case down
    case left
    case right
}

struct GameTile: Identifiable, Equatable {
    let id: UUID
    var value: Int
    var row: Int
    var column: Int
    var isNew: Bool
    var isMerged: Bool

    init(id: UUID = UUID(), value: Int, row: Int, column: Int, isNew: Bool = false, isMerged: Bool = false) {
        self.id = id
        self.value = value
        self.row = row
        self.column = column
        self.isNew = isNew
        self.isMerged = isMerged
    }
}

@MainActor
final class GameModel: ObservableObject {
    static let appVersion = "2.2.0"
    static let minimumBoardSide = 3
    static let maximumBoardSide = 1024
    static let minimumAutoplaySpeed = 1.0
    static let maximumAutoplaySpeed = 10.0

    @Published private(set) var tiles: [GameTile]
    @Published private(set) var score: Int
    @Published private(set) var bestScore: Int
    @Published private(set) var hasWon: Bool
    @Published private(set) var isGameOver: Bool
    @Published private(set) var boardWidth: Int
    @Published private(set) var boardHeight: Int
    @Published private(set) var wrapsAround: Bool
    @Published private(set) var isAutoplaying: Bool
    @Published private(set) var autoplaySpeed: Double
    @Published private(set) var highestTile: Int
    @Published private(set) var gameHistory: [GameRecord]
    @Published private(set) var moveCount: Int

    private var hasAcknowledgedWin = false
    private var isMoving = false
    private var moveTask: Task<Void, Never>?
    private var autoplayTask: Task<Void, Never>?
    private let bestScoreKey = "Game1.BestScore"
    private let slideDuration: UInt64 = 170_000_000
    private let popDuration: UInt64 = 140_000_000

    init() {
        self.tiles = []
        self.score = 0
        self.bestScore = UserDefaults.standard.integer(forKey: bestScoreKey)
        self.hasWon = false
        self.isGameOver = false
        self.boardWidth = 4
        self.boardHeight = 4
        self.wrapsAround = false
        self.isAutoplaying = false
        self.autoplaySpeed = 5.0
        self.highestTile = 0
        self.gameHistory = []
        self.moveCount = 0
        startNewGame()
    }

    func startNewGame() {
        moveTask?.cancel()
        isMoving = false
        score = 0
        hasWon = false
        hasAcknowledgedWin = false
        isGameOver = false
        highestTile = 0
        moveCount = 0

        var nextTiles: [GameTile] = []
        addRandomTile(to: &nextTiles)
        addRandomTile(to: &nextTiles)

        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            tiles = nextTiles
        }

        clearTileHighlights(after: popDuration)
    }

    func updateBoardSize(width: Int? = nil, height: Int? = nil) {
        let nextWidth = clampBoardSide(width ?? boardWidth)
        let nextHeight = clampBoardSide(height ?? boardHeight)
        guard nextWidth != boardWidth || nextHeight != boardHeight else {
            return
        }

        boardWidth = nextWidth
        boardHeight = nextHeight
        startNewGame()
    }

    func setWrapsAround(_ enabled: Bool) {
        wrapsAround = enabled
    }

    func setAutoplaying(_ enabled: Bool) {
        guard enabled != isAutoplaying else {
            return
        }

        isAutoplaying = enabled
        if enabled {
            startAutoplay()
        } else {
            autoplayTask?.cancel()
            autoplayTask = nil
        }
    }

    func setAutoplaySpeed(_ speed: Double) {
        autoplaySpeed = min(max(speed, Self.minimumAutoplaySpeed), Self.maximumAutoplaySpeed)
    }

    func continueAfterWin() {
        hasAcknowledgedWin = true
        hasWon = false
    }

    func move(_ direction: MoveDirection) {
        guard !isMoving, !isGameOver, let plan = makeMovePlan(for: direction) else {
            return
        }

        isMoving = true
        moveCount += 1
        score += plan.points
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: bestScoreKey)
        }

        if isAutoplaying {
            // Skip animations during autoplay — apply the move instantly
            tiles = plan.slidingTiles
            finishMove(plan)
            clearTileHighlights()
        } else {
            withAnimation(.easeOut(duration: Double(slideDuration) / 1_000_000_000)) {
                tiles = plan.slidingTiles
            }

            let slideDuration = self.slideDuration
            let popDuration = self.popDuration
            moveTask?.cancel()
            moveTask = Task { [weak self, plan, slideDuration, popDuration] in
                do {
                    try await Task.sleep(nanoseconds: slideDuration)
                } catch {
                    return
                }

                await MainActor.run {
                    self?.finishMove(plan)
                }

                do {
                    try await Task.sleep(nanoseconds: popDuration)
                } catch {
                    return
                }

                await MainActor.run {
                    self?.clearTileHighlights()
                }
            }
        }
    }

    private func finishMove(_ plan: MovePlan) {
        var resolvedTiles = plan.slidingTiles.filter { !plan.removedTileIDs.contains($0.id) }

        for index in resolvedTiles.indices {
            if let value = plan.valueUpdates[resolvedTiles[index].id] {
                resolvedTiles[index].value = value
                resolvedTiles[index].isMerged = true
            }
        }

        addRandomTile(to: &resolvedTiles)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
            tiles = resolvedTiles
        }

        let board = boardMatrix(from: resolvedTiles)
        let maxValue = board.flatMap { $0 }.max() ?? 0
        if maxValue > highestTile {
            highestTile = maxValue
        }

        if board.flatMap({ $0 }).contains(2048), !hasAcknowledgedWin {
            if isAutoplaying {
                hasAcknowledgedWin = true
            } else {
                hasWon = true
            }
        }
        isGameOver = !canMove(in: board)
        if isGameOver {
            let record = GameRecord(
                score: score,
                highestTile: highestTile,
                moveCount: moveCount,
                boardWidth: boardWidth,
                boardHeight: boardHeight,
                wrapsAround: wrapsAround,
                wasAutoplay: isAutoplaying
            )
            gameHistory.append(record)
            setAutoplaying(false)
        }
    }

    private func startAutoplay() {
        autoplayTask?.cancel()
        autoplayTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await MainActor.run {
                    self?.autoplayDelay ?? 290_000_000
                }

                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }

                await MainActor.run {
                    self?.performAutoplayStep()
                }
            }
        }
    }

    private func performAutoplayStep() {
        guard isAutoplaying else {
            return
        }

        if hasWon {
            continueAfterWin()
        }

        guard !isMoving else {
            return
        }

        guard !isGameOver else {
            setAutoplaying(false)
            return
        }

        guard let direction = bestAutoplayDirection() else {
            setAutoplaying(false)
            return
        }

        move(direction)
    }

    private func bestAutoplayDirection() -> MoveDirection? {
        let candidates = MoveDirection.allCases.compactMap { direction -> (direction: MoveDirection, score: Int)? in
            guard let plan = makeMovePlan(for: direction) else {
                return nil
            }

            let mergeScore = plan.points * 10
            let movementScore = plan.movedTileCount
            return (direction, mergeScore + movementScore)
        }

        guard let bestScore = candidates.map(\.score).max() else {
            return nil
        }

        return candidates.filter { $0.score == bestScore }.randomElement()?.direction
    }

    private func clearTileHighlights(after delay: UInt64) {
        moveTask?.cancel()
        moveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            await MainActor.run {
                self?.clearTileHighlights()
            }
        }
    }

    private func clearTileHighlights() {
        tiles = tiles.map { tile in
            var tile = tile
            tile.isNew = false
            tile.isMerged = false
            return tile
        }
        isMoving = false
    }

    private func makeMovePlan(for direction: MoveDirection) -> MovePlan? {
        let currentTiles = tiles.map { tile in
            var tile = tile
            tile.isNew = false
            tile.isMerged = false
            return tile
        }

        var slidingTilesByID = Dictionary(uniqueKeysWithValues: currentTiles.map { ($0.id, $0) })
        var removedTileIDs = Set<UUID>()
        var valueUpdates: [UUID: Int] = [:]
        var points = 0
        let lineCount = direction.isHorizontal ? boardHeight : boardWidth

        for line in 0..<lineCount {
            let tilesInLine = tilesInLine(line, direction: direction, from: currentTiles)
            let targets = wrapsAround
                ? wrappedTargets(for: tilesInLine, line: line, direction: direction)
                : standardTargets(for: tilesInLine, line: line, direction: direction)

            for target in targets {
                for tileID in target.tileIDs {
                    guard var slidingTile = slidingTilesByID[tileID] else {
                        continue
                    }
                    slidingTile.row = target.row
                    slidingTile.column = target.column
                    slidingTilesByID[tileID] = slidingTile
                }

                if target.tileIDs.count == 2, let keptID = target.tileIDs.first, let removedID = target.tileIDs.last {
                    valueUpdates[keptID] = target.value
                    removedTileIDs.insert(removedID)
                    points += target.value
                }
            }
        }

        let slidingTiles = currentTiles.compactMap { slidingTilesByID[$0.id] }
        let changedPosition = zip(currentTiles, slidingTiles).contains { before, after in
            before.row != after.row || before.column != after.column
        }

        guard changedPosition || !removedTileIDs.isEmpty else {
            return nil
        }

        let movedTileCount = zip(currentTiles, slidingTiles).filter { before, after in
            before.row != after.row || before.column != after.column
        }.count

        return MovePlan(
            slidingTiles: slidingTiles,
            removedTileIDs: removedTileIDs,
            valueUpdates: valueUpdates,
            points: points,
            movedTileCount: movedTileCount
        )
    }

    private func standardTargets(for tiles: [GameTile], line: Int, direction: MoveDirection) -> [LineTarget] {
        var targets: [LineTarget] = []

        for tile in tiles {
            if let lastIndex = targets.indices.last,
               !targets[lastIndex].hasMerged,
               targets[lastIndex].value == tile.value {
                targets[lastIndex].value *= 2
                targets[lastIndex].hasMerged = true
                targets[lastIndex].tileIDs.append(tile.id)
            } else {
                let position = targetPosition(for: targets.count, in: line, direction: direction)
                targets.append(
                    LineTarget(
                        value: tile.value,
                        row: position.row,
                        column: position.column,
                        tileIDs: [tile.id]
                    )
                )
            }
        }

        return targets
    }

    private func wrappedTargets(for tiles: [GameTile], line: Int, direction: MoveDirection) -> [LineTarget] {
        var movingTiles = tiles
        var targets: [LineTarget] = []

        if movingTiles.count > 1,
           let first = movingTiles.first,
           let last = movingTiles.last,
           first.value == last.value {
            movingTiles.removeLast()
            movingTiles.removeFirst()
            let position = targetPosition(for: 0, in: line, direction: direction)
            targets.append(
                LineTarget(
                    value: first.value * 2,
                    row: position.row,
                    column: position.column,
                    hasMerged: true,
                    tileIDs: [first.id, last.id]
                )
            )
        }

        for tile in movingTiles {
            if let lastIndex = targets.indices.last,
               !targets[lastIndex].hasMerged,
               targets[lastIndex].value == tile.value {
                targets[lastIndex].value *= 2
                targets[lastIndex].hasMerged = true
                targets[lastIndex].tileIDs.append(tile.id)
            } else {
                let position = targetPosition(for: targets.count, in: line, direction: direction)
                targets.append(
                    LineTarget(
                        value: tile.value,
                        row: position.row,
                        column: position.column,
                        tileIDs: [tile.id]
                    )
                )
            }
        }

        return targets
    }

    private func tilesInLine(_ line: Int, direction: MoveDirection, from tiles: [GameTile]) -> [GameTile] {
        switch direction {
        case .left:
            return tiles
                .filter { $0.row == line }
                .sorted { $0.column < $1.column }
        case .right:
            return tiles
                .filter { $0.row == line }
                .sorted { $0.column > $1.column }
        case .up:
            return tiles
                .filter { $0.column == line }
                .sorted { $0.row < $1.row }
        case .down:
            return tiles
                .filter { $0.column == line }
                .sorted { $0.row > $1.row }
        }
    }

    private func targetPosition(for offset: Int, in line: Int, direction: MoveDirection) -> (row: Int, column: Int) {
        switch direction {
        case .left:
            return (line, offset)
        case .right:
            return (line, boardWidth - 1 - offset)
        case .up:
            return (offset, line)
        case .down:
            return (boardHeight - 1 - offset, line)
        }
    }

    private func addRandomTile(to tiles: inout [GameTile]) {
        let occupiedCells = Set(tiles.map { Cell(row: $0.row, column: $0.column) })
        let emptyCells = (0..<boardHeight).flatMap { row in
            (0..<boardWidth).compactMap { column in
                let cell = Cell(row: row, column: column)
                return occupiedCells.contains(cell) ? nil : cell
            }
        }

        guard let cell = emptyCells.randomElement() else {
            return
        }

        tiles.append(
            GameTile(
                value: Double.random(in: 0..<1) < 0.9 ? 2 : 4,
                row: cell.row,
                column: cell.column,
                isNew: true
            )
        )
    }

    private func boardMatrix(from tiles: [GameTile]) -> [[Int]] {
        var board = Array(repeating: Array(repeating: 0, count: boardWidth), count: boardHeight)
        for tile in tiles where tile.row < boardHeight && tile.column < boardWidth {
            board[tile.row][tile.column] = tile.value
        }
        return board
    }

    private func canMove(in board: [[Int]]) -> Bool {
        if board.flatMap({ $0 }).contains(0) {
            return true
        }

        for row in 0..<boardHeight {
            for column in 0..<boardWidth {
                let value = board[row][column]
                if row + 1 < boardHeight, board[row + 1][column] == value {
                    return true
                }
                if column + 1 < boardWidth, board[row][column + 1] == value {
                    return true
                }
                if wrapsAround, boardHeight > 1, row == 0, board[boardHeight - 1][column] == value {
                    return true
                }
                if wrapsAround, boardWidth > 1, column == 0, board[row][boardWidth - 1] == value {
                    return true
                }
            }
        }

        return false
    }

    private func clampBoardSide(_ value: Int) -> Int {
        min(max(value, Self.minimumBoardSide), Self.maximumBoardSide)
    }

    private var autoplayDelay: UInt64 {
        let normalized = (autoplaySpeed - Self.minimumAutoplaySpeed) / (Self.maximumAutoplaySpeed - Self.minimumAutoplaySpeed)
        let maxDelay = 700_000_000.0
        let minDelay = 1_000_000.0  // 1ms minimum — essentially instant
        return UInt64(maxDelay - normalized * (maxDelay - minDelay))
    }
}

private struct MovePlan {
    let slidingTiles: [GameTile]
    let removedTileIDs: Set<UUID>
    let valueUpdates: [UUID: Int]
    let points: Int
    let movedTileCount: Int
}

private struct LineTarget {
    var value: Int
    let row: Int
    let column: Int
    var hasMerged = false
    var tileIDs: [UUID]
}

private struct Cell: Hashable {
    let row: Int
    let column: Int
}

private extension MoveDirection {
    static let allCases: [MoveDirection] = [.up, .left, .down, .right]

    var isHorizontal: Bool {
        switch self {
        case .left, .right:
            return true
        case .up, .down:
            return false
        }
    }
}

struct GameRecord: Identifiable {
    let id: UUID
    let date: Date
    let score: Int
    let highestTile: Int
    let moveCount: Int
    let boardWidth: Int
    let boardHeight: Int
    let wrapsAround: Bool
    let wasAutoplay: Bool

    init(
        score: Int,
        highestTile: Int,
        moveCount: Int,
        boardWidth: Int,
        boardHeight: Int,
        wrapsAround: Bool,
        wasAutoplay: Bool
    ) {
        self.id = UUID()
        self.date = Date()
        self.score = score
        self.highestTile = highestTile
        self.moveCount = moveCount
        self.boardWidth = boardWidth
        self.boardHeight = boardHeight
        self.wrapsAround = wrapsAround
        self.wasAutoplay = wasAutoplay
    }
}
