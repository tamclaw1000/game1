# Architecture — Game1 (2048)

## Overview

Game1 is a native SwiftUI implementation of the classic 2048 puzzle game. It targets both **iOS** and **macOS** from a single shared codebase with platform-specific app entry points.

```
Game1.xcodeproj
├── Shared/          ← Shared model + view (the game)
│   ├── GameModel.swift
│   └── GameView.swift
├── iOS/
│   └── Game1iOSApp.swift     ← iOS app entry point
├── macOS/
│   └── Game1MacApp.swift     ← macOS app entry point
├── build.sh                 ← xcodebuild wrapper
├── run.sh                   ← build + launch wrapper
├── ARCHITECTURE.md
└── README.md
```

## App Targets

### iOS (`Game1iOSApp.swift`)

- `@main` SwiftUI `App` struct — `Game1iOSApp`
- Renders `GameView()` inside a `WindowGroup`
- No additional chrome; relies entirely on shared views
- Input: swipe gestures (`DragGesture`)

### macOS (`Game1MacApp.swift`)

- `@main` SwiftUI `App` struct — `Game1MacApp`
- Renders `GameView()` with `.frame(minWidth: 420, minHeight: 520)`
- Window resizability set to `.contentMinSize`
- Input: swipe gestures + arrow keys (via `NSViewRepresentable` bridge)

---

## Shared Architecture

### GameModel (`Shared/GameModel.swift`)

The central model — a `@MainActor` `ObservableObject` that owns all game state and mutating logic.

**Published state:**

| Property | Type | Purpose |
|---|---|---|
| `tiles` | `[GameTile]` | All tiles currently on the board |
| `score` | `Int` | Current session score |
| `bestScore` | `Int` | Persistent best score (UserDefaults) |
| `bestHighestTile` | `Int` | Persistent best tile ever reached (UserDefaults) |
| `highestTile` | `Int` | Highest tile in the current game |
| `moveCount` | `Int` | Moves made in the current game |
| `gameHistory` | `[GameRecord]` | In-memory list of completed games |
| `hasWon` | `Bool` | True when a 2048 tile appears (before acknowledgment) |
| `isGameOver` | `Bool` | True when no moves remain |
| `boardWidth` / `boardHeight` | `Int` | Board dimensions (3–1024) |
| `wrapsAround` | `Bool` | Enable wrap-around (toroidal) mode |
| `isAutoplaying` | `Bool` | Whether AI autoplay is running |
| `autoplaySpeed` | `Double` | Autoplay speed (1–10) |

**Key methods:**

| Method | Purpose |
|---|---|
| `startNewGame()` | Reset board, score, move count; place 2 random tiles |
| `move(_ direction:)` | Animate a slide in one direction (or apply instantly during autoplay) |
| `continueAfterWin()` | Dismiss the win overlay and keep playing |
| `updateBoardSize(width:height:)` | Resize grid preserving existing tiles (grow/shrink left and bottom) |
| `setWrapsAround(_:)` | Toggle toroidal mode |
| `setAutoplaying(_:)` | Start/stop AI autoplay |
| `setAutoplaySpeed(_:)` | Adjust autoplay rate |

**Animation pipeline (inside `move` — manual mode):**

1. `makeMovePlan(for:)` computes tile destinations, merges, and removals (no mutation)
2. `withAnimation(.easeOut)` slides tiles to new positions (170ms)
3. After `slideDuration`, `finishMove(_:)` applies merges, adds a random tile, fades it in (spring animation, ~220ms)
4. After `popDuration` (140ms), `clearTileHighlights()` resets `isNew`/`isMerged` flags and releases `isMoving` lock

**Autoplay mode:**
- During autoplay (`isAutoplaying == true`), `move(_:)` skips all animations and applies the move plan synchronously — making it run as fast as SwiftUI can re-render
- A `Task` loop runs `performAutoplayStep()` with a configurable delay (700ms at speed 1 → 1ms at speed 10)
- Each step picks the best move via `bestAutoplayDirection()` using a greedy heuristic (merge points × 10 + tiles moved)

### GameView (`Shared/GameView.swift`)

The monolithic SwiftUI view hierarchy:

```
GameView
├── header (title "2048" + score pills)
│   ├── ScorePill — "SCORE" (current game score)
│   ├── ScorePill — "HIGHEST" (highest tile this game)
│   └── BestPill — "BEST" (best score + best tile ever, persisted)
├── BoardView
│   ├── GridBackground (Canvas — efficient large-board rendering)
│   └── TileView (per tile: rounded rect + dynamically scaled value text + hover tooltip)
├── controls
│   ├── New Game button
│   ├── History button (opens Game History sheet)
│   ├── Wrap toggle
│   ├── Auto toggle
│   ├── Speed slider (1–10)
│   ├── Width / Height steppers
│   └── Palette selector (8 schemes: Classic, Ocean, Contrast, Candy, Forest, Noir, Sunset, Mint)
├── keyboardHandler (macOS-only NSViewRepresentable for arrow keys)
└── overlay (win / game-over sheet)
```

**Palette system (`GamePalette` enum):**

8 presets each defining a complete color system:

| Property | Role |
|---|---|
| `gameBackground` | App/background fill |
| `boardBackground` | Board area fill |
| `emptyTile` | Background of empty cell slots |
| `scoreBackground` | Background for score pills (always dark) |
| `scoreText` | Primary value text on score pills (always white) |
| `scoreLabelText` | Label text on score pills (white at 75%) |
| `controlsBackground` | Controls panel fill |
| `unselectedControlBackground` | Unselected palette button fill |
| `primaryText` | General text on light backgrounds |
| `secondaryText` | Muted text (version, secondary info) |
| `accent` | Highlight/selected button color |
| `selectedControlText` | Text on selected palette button (white) |
| `lightText` | High-contrast text on dark surfaces (always white) |
| `tileColor(for:)` | Value → tile background color |
| `tileTextColor(for:)` | Value → tile text color |

**Board layout (`BoardView`):**

Uses `GeometryReader` to compute tile size dynamically from available space. Spacing scales with board density (`cellSpacing`). Tiles positioned absolutely in a `ZStack` via `.position(x:y:)`. Merged tiles get a `.scaleEffect(1.08)` pop animation.

**Tile text scaling:**

Every tile renders its value with `.font(.system(size: 40)).minimumScaleFactor(0.05)`. SwiftUI dynamically shrinks text to fit the tile — no manual font-size switching. The `.help()` modifier adds a native hover tooltip on macOS showing the exact number.

### Game History (`Shared/GameView.swift`)

- `GameRecord` struct stores: score, highest tile, move count, board dimensions, wrap mode, autoplay flag, date
- Records are appended to `gameHistory` automatically when a game ends
- Accessible via the "History" button in controls → opens a sheet

---

## `MoveDirection` — Input Abstraction

```swift
enum MoveDirection {
    case up, down, left, right
}
```

Swipe gestures map translation vectors to directions (larger axis wins). macOS arrow keys (`keyCode` 123–126) map directly. The direction drives `tilesInLine(_:direction:from:)` which sorts tile rows/columns to process them from the leading edge inward.

---

## Move Resolution (Core Algorithm)

### `makeMovePlan(for:)` → `MovePlan`

1. Strips `isNew`/`isMerged` flags from all tiles
2. For each line (row for horizontal moves, column for vertical):
   - Collects tiles in that line, sorted from leading edge
   - Calls `standardTargets(for:line:direction:)` or `wrappedTargets(for:line:direction:)`
3. Each `LineTarget` represents a final cell: tile IDs that land there, merged value, merge flag
4. Simultaneous merges (2 tiles into 1) set `removedTileIDs` and `valueUpdates`
5. If no tile positions changed and nothing was removed, returns `nil` (no-op guard)

### Merge Rules (standard mode)

- Tiles collide and merge when two adjacent tiles in the slide direction have the same value
- A tile that already merged in this move cannot merge again
- Resulting tile value = sum (2× the original)

### Wrap Mode (toroidal)

- The first and last tiles in a line can merge together (wrapping around the board edge)
- After a potential wrap-merge, the remaining tiles are processed with standard rules
- Game-over checks also consider wrap adjacency for vertical/horizontal edges

### Data Model

```
MovePlan
├── slidingTiles: [GameTile]      — tiles at their new positions
├── removedTileIDs: Set<UUID>     — tiles consumed by merges
├── valueUpdates: [UUID: Int]     — surviving merged tile → new value
├── points: Int                   — score earned this move
└── movedTileCount: Int           — tiles that changed position

LineTarget
├── value: Int                    — tile value at this target cell
├── row, column: Int              — target cell coordinates
├── hasMerged: Bool               — was a merge performed here?
└── tileIDs: [UUID]               — tile IDs landing here (1 or 2)

GameRecord (Identifiable)
├── id: UUID
├── date: Date
├── score: Int
├── highestTile: Int
├── moveCount: Int
├── boardWidth / boardHeight: Int
├── wrapsAround: Bool
└── wasAutoplay: Bool
```

---

## Persistence

| Key | Value | Updated |
|---|---|---|
| `Game1.BestScore` | Best ever score | When score exceeds best |
| `Game1.HighestTile` | Best ever tile value | When a new tile exceeds previous best |

Both loaded on `init()` from `UserDefaults`.

---

## Grid Resize Behavior

`updateBoardSize(width:height:)` reshapes the board without resetting state:

| Operation | Behavior |
|---|---|
| **Increase width** | Existing tiles shift right → new empty columns appear on the **left** |
| **Decrease width** | Leftmost columns are removed → remaining tiles shift left |
| **Increase height** | New empty rows added at the **bottom** |
| **Decrease height** | Bottommost rows (and tiles on them) are removed |

Score, move count, highest tile, and game state carry over. Win/game-over are recalculated after resize.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Single `ObservableObject` | Simple enough to keep state in one place; avoids cross-model sync bugs |
| Animation via `Task.sleep` + `withAnimation` | Fine-grained control over multi-phase animations (slide → merge → pop) |
| Skip animations during autoplay | Fast-forward moves at CPU speed instead of animation-limited pace |
| `NSViewRepresentable` for macOS keyboard | Required because SwiftUI has no native key-down capture for arrow keys |
| `@MainActor` on model | Ensures all state mutations happen on the main actor (required for SwiftUI observation) |
| Wrap mode as toggle | Adds strategic variety with minimal code changes to the core algorithm |
| Dynamic font scaling (`minimumScaleFactor: 0.05`) | Guarantees any tile value is visible without manual font-size tiers |
| `scoreText` / `scoreLabelText` as palette properties | Ensures score pills are always readable regardless of palette |
| In-memory game history | Simple, no persistence needed for session history |
| Grid resize preserves tiles | Avoiding game restart on board reshape enables continuous play |
