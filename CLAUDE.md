# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

RunTracker is a SwiftUI iOS app (Xcode project, no SPM/CocoaPods dependencies) that generates walkable loop routes of a requested length around the user, navigates them turn-by-turn, and records completed runs.

- Deployment target: **iOS 26.5**, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Frameworks: SwiftUI, SwiftData, MapKit, CoreLocation, WeatherKit (the `com.apple.developer.weatherkit` entitlement is required; WeatherKit needs a real signed build, it does not work in a plain simulator run without the entitlement provisioned).
- Only one shared scheme: `RunTracker`.

## Commands

Simulator must run iOS ≥ 26.5 (e.g. `iPhone 17`, `iPhone Air`); older simulators (iPhone 16 / iOS 18) will not launch this target.

```bash
xcodebuild -scheme RunTracker -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```bash
xcodebuild test -scheme RunTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RunTrackerTests
```

Single suite or single test (Swift Testing suites are plain structs, so the identifier is `Target/Suite/test()`):

```bash
xcodebuild test -scheme RunTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RunTrackerTests/RouteGeneratorTests/seedControlsRandomness
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
| `RunTracker/Geo.swift` | Flat-earth coordinate math: distance, bearing, offset, projection, polyline helpers. |
| `RunTracker/LoopGeometry.swift` | Pure geometry and heuristics: `SeededRandom`, `LoopShape` (vertex ring), `RadiusSolver` (converges radius → target distance), `BearingPlanner` (picks the direction least used recently), `DetourEstimate` (learned road-distance/straight-line factor per map cell + direction), `RouteFootprint` (corridor-based overlap and repeated-stretch detection). No MapKit calls. |
| `RunTracker/DirectionsClient.swift` | Network layer: `DirectionsProviding` protocol (stubbed in tests), `RequestGate` (concurrency cap), `RequestPacer` (token bucket keeping sustained rate under MapKit's ~50 req/min throttle), `LegFetcher` (fetch + LRU-ish cache of walking legs). Knows nothing about geometry. |
| `RunTracker/RouteGenerator.swift` | The engine. `GenerationPolicy` holds every tunable and **derives** the request budget from the plan (`loopRequestBudget`, `fallbackRequestBudget`). Pipeline: (1) try several loop shapes in different bearings, converging radius each round and judging the candidate at the end of every round — the first acceptable one returns immediately; (2) otherwise the best near-miss ("relaxed") candidate; (3) otherwise an out-and-back fallback; only total network failure throws. |

Two cross-cutting rules that are easy to break:

- **There is exactly one `RouteViewModel` / `RouteGenerator` in the app.** `RunTrackerApp.RootView` creates it and injects it via `.environment(routes)`; `MapView` and `HomeView` read it with `@Environment(RouteViewModel.self)`. Creating a per-tab instance splits the MapKit rate-limit budget (causing throttling), splits the leg cache, and splits the recent-route history so two tabs generate identical routes. Do not instantiate `RouteViewModel()` or `RouteGenerator()` outside `RootView` (previews excepted).
- **Route state is a single enum**, `RouteGenerationState` (`idle` / `generating(previous:)` / `ready` / `failed`) — contradictory combinations are unrepresentable. Don't reintroduce parallel `isLoading` / `error` flags.

Generation persists two things across launches via `GenerationStoring` (backed by `UserDefaults`): learned detour factors (speed — the first radius guess lands closer) and recent route footprints (diversity — the next route opens in a different direction). Tests inject an in-memory store instead.

Tests reflect this split: `LoopGeometryTests.swift` covers the network-free geometry, `RouteGeneratorTests.swift` drives the full engine against a fake walking network with a fixed seed, so runs are deterministic. When adding engine behaviour, add a stub-network test rather than hitting MapKit.

### Navigation and tracking

- `FollowablePath` is the protocol `NavigationViewModel` follows; both `GeneratedRoute` (has MapKit `legs`, so it has turn instructions) and the SwiftData `TraveledPath` (no legs → instruction-free following) conform. Navigation never learns where a path came from.
- `NavigationViewModel` does not observe location itself — the view calls `update(location:)`. It handles route matching, off-route confirmation, rerouting (with its own cooldown, because MapKit throttles), and arrival.
- `LocationManager` (`@Observable`, `CLLocationManagerDelegate`) owns permission, the recorded `pathSegments`, and auto-pause. Pauses **split the path into a new segment**, which is why paths are `[[CLLocationCoordinate2D]]` everywhere rather than a flat array.
- `RunCamera` keeps the map centered on the user, tilted, and rotated to travel direction, falling back to compass heading when stopped.

### Data model (SwiftData)

`RunTrackerApp` registers `RunSession`, `TraveledPath`, and `User` in the model container.

- `User` — created by the `UserQAView` onboarding questionnaire; `RootView` shows onboarding when no `User` exists and `MainView` otherwise, injecting the user via `.environment(user)`. Derived stats (`totalDistance`, `avgPace`, `weeklyTarget`) live on the model.
- `RunSession` — a finished run: segments actually travelled, distance, duration, optional `plannedDistance`, and relationships to `User` and `TraveledPath`. Written in `FreeRunView` and `NavigationView` when the run ends.
- `TraveledPath` — a reusable recorded path that can be favorited and re-navigated (`FavoritePathsSheet`).
- Coordinates are persisted as `RouteSegment`/`RoutePoint` (`Codable` structs), not `CLLocationCoordinate2D`. The planned route is never persisted — only what was actually run; map overlays (`RunRouteOverlay`) are derived in the view each time.

### Screens

`MainView` is a three-tab `TabView`: `HomeView` (weather/forecast, this week's sessions, quick route), `MapView` (generate and preview a route, entry point to navigation and favorites), `ProfileView` (stats, `EditProfileView`). Run screens are pushed from there: `NavigationView` (guided run on a `FollowablePath`) and `FreeRunView` (untracked-route run).
