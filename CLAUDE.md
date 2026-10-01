# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

RunTracker is a SwiftUI iOS app (Xcode project, no SPM/CocoaPods dependencies) that generates walkable loop routes of a requested length around the user, navigates them turn-by-turn, and records completed runs.

- Deployment target: **iOS 26.5**, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Frameworks: SwiftUI, SwiftData, MapKit, CoreLocation, WeatherKit (the `com.apple.developer.weatherkit` entitlement is required; WeatherKit needs a real signed build, it does not work in a plain simulator run without the entitlement provisioned).
- Only one shared scheme: `RunTracker`.

## Commands

Simulator must run iOS ≥ 26.5 (e.g. `iPhone Air`, `iPhone 17e`); older simulators (iPhone 16 / iOS 18) will not launch this target.

```bash
xcodebuild -scheme RunTracker -destination 'platform=iOS Simulator,name=iPhone Air' build
```

```bash
xcodebuild test -scheme RunTracker -destination 'platform=iOS Simulator,name=iPhone Air' -only-testing:RunTrackerTests
```

Single suite or single test (Swift Testing suites are plain structs, so the identifier is `Target/Suite/test()`):

```bash
xcodebuild test -scheme RunTracker -destination 'platform=iOS Simulator,name=iPhone Air' -only-testing:RunTrackerTests/RouteGeneratorTests/seedControlsRandomness
```

`RunTrackerTests` uses **Swift Testing** (`@Test` / `#expect`); `RunTrackerUITests` still uses XCTest and is slow — exclude it with `-only-testing:RunTrackerTests` unless you are specifically working on UI tests.

## Conventions

- **Doc comments and inline comments are written in Turkish**; type names, properties, and user-facing strings are in English. Match this when editing — new comments in an existing Turkish file should be Turkish.
- Comments here explain *why a constant has the value it has* and what broke before ("eskiden …"). When you change a tuned constant in `GenerationPolicy` or `NavigationViewModel`, update its rationale comment rather than deleting it.
- The project defaults to `@MainActor` isolation. Pure value types that must be usable off the main actor are marked explicitly `nonisolated struct` / `nonisolated enum` (`Geo`, `LoopShape`, `RadiusSolver`, `RouteFootprint`, `GenerationPolicy`, `RoutePoint`, `RouteSegment`).

## Architecture

### Route generation (the core of the app)

Four layers, deliberately separated so the geometry and the budget arithmetic are testable without a network:

| File | Role |
| --- | --- |
| `RunTracker/Geo.swift` | Flat-earth coordinate math: distance, bearing, offset, projection, polyline helpers, and `MeasuredPath` (distance-along-a-line lookup and even resampling, shared by direction arrows and route footprints). |
| `RunTracker/LoopGeometry.swift` | Pure geometry and heuristics: `SeededRandom`, `LoopShape` (vertex ring), `RadiusSolver` (converges radius → target distance), `BearingPlanner` (picks the direction least used recently), `DetourEstimate` (learned road-distance/straight-line factor per map cell + direction), `RouteFootprint` (corridor-based overlap and repeated-stretch detection), `ShapeSchedule` (how many shapes are generated vs. sent to the network, and when the free near-duplicate skip is allowed). No MapKit calls. |
| `RunTracker/DirectionsClient.swift` | Network layer: `DirectionsProviding` protocol (stubbed in tests), `RequestGate` (concurrency cap), `RequestPacer` (token bucket keeping sustained rate under MapKit's ~50 req/min throttle), `LegFetcher` (fetch + LRU-ish cache of walking legs). Knows nothing about geometry. |
| `RunTracker/GenerationPolicy.swift` | Every tunable of the engine, with the rationale for each value, plus per-failure recovery limits and backoff. There is no separate request budget: the plan itself (attempts × evaluations, one repair per shape, counted recoveries, two time limits) bounds the request count, and `RequestPacer` bounds the rate. |
| `RunTracker/GenerationStore.swift` | `GenerationStoring` and its `UserDefaults` implementation: learned detour factors and the recent-route history (`RouteHistoryEntry`, JSON-encoded). |
| `RunTracker/GeneratedRoute.swift` | `GeneratedRoute` (the engine's output) and `RouteGenerationError`. |
| `RunTracker/RouteGenerator.swift` | The engine. Pipeline: (1) try several loop shapes in different bearings, converging radius each round and judging the candidate at the end of every round — the first acceptable one returns immediately; (2) otherwise the best near-miss ("relaxed") candidate; (3) otherwise an out-and-back fallback; only total network failure throws. |

Two cross-cutting rules that are easy to break:

- **There is exactly one `RouteViewModel` / `RouteGenerator` in the app.** `RunTrackerApp.RootView` creates it and injects it via `.environment(routes)`; `MapView` and `HomeView` read it with `@Environment(RouteViewModel.self)`. Creating a per-tab instance splits the MapKit rate-limit budget (causing throttling), splits the leg cache, and splits the recent-route history so two tabs generate identical routes. Do not instantiate `RouteViewModel()` or `RouteGenerator()` outside `RootView` (previews excepted).
- **Route state is a single enum**, `RouteGenerationState` (`idle` / `generating(previous:)` / `ready` / `failed`) — contradictory combinations are unrepresentable. Don't reintroduce parallel `isLoading` / `error` flags.

Generation persists two things across launches via `GenerationStoring` (backed by `UserDefaults`): learned detour factors (speed — the first radius guess lands closer) and recent route footprints (diversity — the next route opens in a different direction). Tests inject an in-memory store instead.

Tests reflect this split: `LoopGeometryTests.swift` covers the network-free geometry, `RouteGeneratorTests.swift` drives the full engine against a fake walking network with a fixed seed, so runs are deterministic. When adding engine behaviour, add a stub-network test rather than hitting MapKit.

### Navigation and tracking

- `FollowablePath` is the protocol `NavigationViewModel` follows; `GeneratedRoute` (has MapKit `legs`, so it has turn instructions), the SwiftData `TraveledPath`, and `ReversedPath` (no legs → instruction-free following) all conform. Navigation never learns where a path came from. `reversed()` flips geometry only: `MKRoute` steps are directional and cannot be reversed, so the reversed direction is followed without turn instructions — direction arrows carry the heading.
- `NavigationViewModel` does not observe location itself — the view calls `update(location:)`. It handles route matching, off-route confirmation, rerouting (with its own cooldown, because MapKit throttles), and arrival. Reroute requests go through an injected `DirectionsProviding` (tests pass a fake), and the in-flight reroute is a stored task that `stop()` cancels so a late answer cannot revive a stopped navigator.
- **A run does not have to start at the route's beginning.** `start(path:)` only builds the route and enters `.waitingToStart`; the run begins when the user comes within `startRadius` of the route, joining at whatever point they are nearest (`entryMatch`). Progress, `journeyDistance`, and arrival are all measured from that entry point, not from the route's start — so a runner joining mid-loop sees an empty progress bar and only the distance left to the finish. `entryMatch` breaks near-ties toward the *earliest* point on purpose: a loop's first and last point are the same coordinate, so tie-breaking the other way would mark a run finished before it started.
- `LocationManager` (`@Observable`, `CLLocationManagerDelegate`) owns permission, the recorded `pathSegments`, and auto-pause. Pauses **split the path into a new segment**, which is why paths are `[[CLLocationCoordinate2D]]` everywhere rather than a flat array.
- `RunCamera` keeps the map centered on the user, tilted, and rotated to travel direction, falling back to compass heading when stopped. Heading changes under `headingThreshold` are ignored and moves glide linearly over about the GPS interval. Any user pan/zoom/rotate (`MapCameraPosition.positionedByUser`) turns following off until the follow button (`toggleFollowing()`) turns it back on.
- **Draw routes with `RouteOverlay` (RouteArrow.swift), never a bare `MapPolyline`.** It bundles the line with its direction arrows, because the line alone is ambiguous: a loop doesn't show which way round it goes, and a reversed route is pixel-identical to the forward one. Pass `density: .compact` for list thumbnails. Maps whose camera moves continuously (navigation, the main map) must pass pre-computed `arrows` and keep them in `@State`, or the whole route gets re-measured on every camera frame. The one exception to "no bare `MapPolyline`" is navigation's greyed-out `completedPolyline`: `NavigationViewModel` splits the route at the runner's position into `completedPolyline` (grey, no arrows) and `upcomingPolyline` + `upcomingArrows` (drawn with `RouteOverlay`). The recorded trail is not drawn on the navigation map.
- **Live Activities.** Both run screens own a `RunLiveActivity` (start on appear, `update` on every location — it throttles to one push per 5 s unless the phase/instruction changes — end on disappear). The UI lives in the `RunTrackerWidgets` extension target; `Shared/RunActivityAttributes.swift` is compiled into **both** targets (synchronized folder in both targets' `fileSystemSynchronizedGroups`) and must not reference app-only types. The Lock Screen "End" button is `EndRunIntent` (a `LiveActivityIntent`, so it runs in the app process) which calls `RunActivityBridge.endRun`, set by the open run screen to its own `endRun()`. The widget can't see `Theme.swift`, so it repeats the few tokens it needs and uses the *bright* brand colors for fills (the asset catalog serves dim dark variants inside the always-dark Dynamic Island).
- Run screens call `LocationManager.setRunsInBackground(true)` so recording and the Live Activity continue with the phone locked (`UIBackgroundModes: location`, When-In-Use permission is enough). Other screens must not enable it. Each run screen owns its own `LocationManager` (it records the path); `HomeView` and `MapView` share one that `MainView` injects via `.environment`.
- **Run-screen chrome lives in `RunScreenChrome.swift`**: `RunTopBanner`, `RunBottomPanel`, `RunStat`, `FollowToggle`, and the `.runScreenLifecycle(...)` modifier that wires background location, the Live Activity, the Lock Screen End bridge and camera following. Screen-specific work goes in its `onStart` / `onLocation` / `onStop` hooks. Both screens save through `RunSession.saveFinishedRun(...)`.
- `NavigationView` is presented with `.fullScreenCover` from all three entry points (main map, favorites sheet, session detail) — it is its own screen with a single back button, not a page pushed onto a stack, and never inside the favorites sheet.

### Data model (SwiftData)

`RunTrackerApp` registers `RunSession`, `TraveledPath`, and `User` in the model container.

- `User` — created by the `UserQAView` onboarding questionnaire; `RootView` shows onboarding when no `User` exists and `MainView` otherwise, injecting the user via `.environment(user)`. Derived stats (`totalDistance`, `avgPace`, `weeklyTarget`) live on the model.
- `RunSession` — a finished run: segments actually travelled, distance, duration, optional `plannedDistance`, and relationships to `User` and `TraveledPath`. Written in `FreeRunView` and `NavigationView` when the run ends.
- `TraveledPath` — a reusable recorded path that can be favorited and re-navigated (`FavoritePathsSheet`).
- Coordinates are persisted as `RouteSegment`/`RoutePoint` (`Codable` structs), not `CLLocationCoordinate2D`. The planned route is never persisted — only what was actually run; map overlays (`RunRouteOverlay`) are derived in the view each time.

### Design system

`RunTracker/Theme.swift` is the single source of the app's look. Use it rather than inventing colors, radii or shadows in a view — the repeated inline `colorScheme == .dark ? .steelGray : .white` card is exactly what it replaced.

- **Palette roles are fixed.** `secondaryGreen` (#10B981) is primary: actions, focus, selection, success, the active tab, `AccentColor`, *and every route line on every map*. `primaryBlue` (#38BDF8) is secondary: transient states (rerouting, pause/follow toggles, free run) and the day end of the weather card. Primary buttons and progress bars use the green → blue gradient (`Color.brandGradient`). Backgrounds are the neutrals `canvas` / `surface` / `hairline`, which are the only colorsets with real light/dark variants.
- **Filled accent buttons use dark text** (`Color.onAccent`), never white. `secondaryGreen` (#10B981) and `primaryBlue` (#38BDF8) are light enough that white text lands under 3:1; dark text clears 7:1. This is a contrast requirement, not a style choice.
- **Glass is for maps only.** `glassEffect` belongs on controls floating over a live map (Run, Navigation, Free Run) where you need to see through. Every other surface is a flat `.card()`.
- Type: `Font.display(_:weight:)` / `.screenTitle` / `.statValue` are SF Rounded, used for numbers and titles; body text stays SF Pro. Live numbers (timers, distances) also need `.monospacedDigit()` or they jitter as digits change.
- Building blocks: `.card()`, `.screenBackground()`, `ScreenHeader`, `SectionLabel`, `StatView`, `ProgressBar`, `EmptyStateView`, `PrimaryButtonStyle`, `SecondaryButtonStyle`.

Two traps worth remembering:

- **Never put a `List` inside a `ScrollView`.** Home and Profile both did; the nested scroll areas clipped rows to a fixed height. Both now use `LazyVStack`. `SessionListView` keeps a real `List` because it needs swipe-to-delete, with clear row backgrounds and hidden separators.
- **Pin `usage:` when formatting a `Measurement`.** Without it the formatter picks its own unit and renders 0 km as "0 cm". Use `usage: .asProvided` (or `.road`).

### Screens

`MainView` is a three-tab `TabView`: `HomeView` (greeting, weekly goal, forecast, recent runs), `MapView` (generate and preview a route, entry point to navigation and favorites), `ProfileView` (identity, weekly goal, all-time stats, this week's runs).

**Both run screens — `NavigationView` and `FreeRunView` — are presented with `.fullScreenCover`, never pushed.** They carry no navigation bar: a glass banner at the top holds the single back button, a glass panel at the bottom holds the numbers and the end-run action. `RunSessionDetailView` and `SessionListView` are ordinary pushed screens with a normal bar.
