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
| `hasWon` | `Bool` | True when a 2048 tile appears (before acknowledgment) |
| `isGameOver` | `Bool` | True when no moves remain |
| `boardWidth` / `boardHeight` | `Int` | Board dimensions (3–1024) |
| `wrapsAround` | `Bool` | Enable wrap-around (toroidal) mode |
| `isAutoplaying` | `Bool` | Whether AI autoplay is running |
| `autoplaySpeed` | `Double` | Moves per second (1–10) |

**Key methods:**

| Method | Purpose |
|---|---|
| `startNewGame()` | Reset board, place 2 random tiles |
| `move(_ direction:)` | Animate a slide in one direction |
| `continueAfterWin()` | Dismiss the win overlay and keep playing |
| `updateBoardSize(width:height:)` | Resize and restart |
| `setWrapsAround(_:)` | Toggle toroidal mode |
| `setAutoplaying(_:)` | Start/stop AI autoplay |
| `setAutoplaySpeed(_:)` | Adjust autoplay rate |

**Animation pipeline (inside `move`):**

1. `makeMovePlan(for:)` computes tile destinations, merges, and removals (no mutation)
2. `slidingTiles` animates via `withAnimation(.easeOut)` — tiles slide to new positions
3. After `slideDuration` (170ms), `finishMove(_:)` applies merges (value updates + removal), adds a random tile, and fades in the new tile
4. After `popDuration` (140ms), `clearTileHighlights()` resets `isNew`/`isMerged` flags and releases `isMoving` lock

**Autoplay:**

A `Task` runs a loop: sleep → `performAutoplayStep()` → repeat. Each step picks the highest-scoring move via `bestAutoplayDirection()` using a greedy heuristic (merge score × 10 + tiles moved). The delay is an inverse linear ramp from 700ms (speed=1) to 90ms (speed=10).

### GameView (`Shared/GameView.swift`)

The monolithic SwiftUI view hierarchy:

```
GameView
├── header (title + score pills)
├── BoardView
│   ├── GridBackground (Canvas — efficient large-board rendering)
│   └── TileView (per tile: rounded rect + value text)
├── controls
│   ├── New Game button
│   ├── Wrap toggle
│   ├── Auto toggle
│   ├── Speed slider
│   ├── Width / Height steppers
│   └── Palette selector (Classic / Ocean / Contrast)
├── keyboardHandler (macOS-only NSViewRepresentable)
└── overlay (win / game-over sheet)
```

**Palette system (`GamePalette` enum):**

Three presets (`classic`, `ocean`, `highContrast`) each defining:
- `gameBackground`, `boardBackground`, `emptyTile`, `controlsBackground`
- `scoreBackground`, `unselectedControlBackground`
- `selectedControlText`, `primaryText`, `secondaryText`, `lightText`, `accent`
- `tileColor(for:)` + `tileTextColor(for:)` — value-to-color mapping per palette

**Board layout (`BoardView`):**

Uses `GeometryReader` to compute tile size dynamically from available space. Spacing scales with board density (`cellSpacing`). Tiles are positioned absolutely inside a `ZStack` using `.position(x:y:)`. A `.scaleEffect(1.08)` is applied to merged tiles during their pop animation.

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
```

---

## Persistence

- **Best score** stored in `UserDefaults` under key `Game1.BestScore`
- Updated immediately when score exceeds best
- Loaded on `init()`, no other persistence

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Single `ObservableObject` | Simple enough to keep state in one place; avoids cross-model sync bugs |
| Animation via `Task.sleep` + `withAnimation` | Fine-grained control over multi-phase animations (slide → merge → pop) |
| Canvas for grid background | Efficient for large boards; avoids N individual view overhead |
| `NSViewRepresentable` for macOS keyboard | Required because SwiftUI has no native key-down capture for arrow keys |
| `@MainActor` on model | Ensures all state mutations happen on the main actor (required for SwiftUI observation) |
| Wrap mode as toggle | Adds strategic variety with minimal code changes to the core algorithm |
