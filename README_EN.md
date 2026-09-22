# MoYing 墨影 🎬📚

[简体中文](./README.md) | **English** | [日本語](./README_JA.md)

A **dual-theme (dark / light)** book and movie tracking app — Flutter, cross-platform, local-first
and offline-first, with optional online metadata lookup.

Bottom navigation with four tabs: **Dashboard / Books / Movies / Profile**.

- **Dashboard**: two stat cards (reading progress ring + average movie rating badge), a horizontal
  "current tasks" row, and a reading list plus movie grid (4 items each, with "view all" links)
- **Books / Movies**: search + dynamic filters + list/grid toggle; tap a card for details, long-press
  to edit. Detail pages include a full cast & crew sheet and a stills gallery; actor pages
  back-reference every work they appear in
- **Profile**: nickname / signature / avatar editing, theme selection (dark / light / follow system),
  statistics, data-source management, cloud sync, and error logs

Since v0.9.0 the app starts with an **empty library** — you add your own records. Every change is
persisted locally. (Demo seed data is kept for tests only.)

## Running

```bash
# Verified with Flutter 3.24.x (including 3.24.5)
flutter pub get
flutter run            # pick a target device (Android / iOS / macOS)
```

> Behind restrictive networks, configure a mirror first:
> ```bash
> export PUB_HOSTED_URL=https://pub.flutter-io.cn
> export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
> ```

Build an Android APK:

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## Verification

```bash
flutter analyze       # static analysis (CI runs it with --fatal-infos; expects 0 issues)
flutter test          # unit + widget tests (currently 35 files, 490 cases)
```

CI (`.github/workflows/ci.yml`) runs, on every push / PR to `main`:
`flutter analyze --fatal-infos` → `flutter test` → `flutter build web`.

> **Platform support**: **Android / iOS / macOS are the primary targets** — persistence, image
> management, backup and WebDAV sync all rely on the local filesystem via `dart:io`.
> The Web target **compiles** (CI builds it), but has no local filesystem: `persistence_stub.dart`
> falls back to in-memory storage (lost on refresh), log persistence and export
> (`log_sink_stub.dart` / `log_exporter_stub.dart`) degrade to no-ops, and image / backup / sync
> entry points are hidden or downgraded per platform. In short: "the UI runs, but it is not a
> supported production platform."

## Version history

- **v0.9.3** (current development version, not yet tagged):
  - **Architecture refactor**: reorganised per the four-layer componentisation + MVVM spec — files
    now live under `app / business / component / foundation`; `XxxScreen` → `XxxPage`,
    `*_screen.dart` → `*_page.dart`; 9 `part` groups and all `widget` keyword usages removed;
    **reverse dependencies 61 → 0**. Structural migration only, no behaviour change.
  - **Error logging**: new `AppLogger` hub (info/warn/error/fatal levels, 500-entry in-memory ring
    buffer, 2 MB rolling log file, serialised write chain) plus global exception guards
    (`FlutterError.onError` / `PlatformDispatcher.onError`). Instrumentation covers network retries,
    data-source fetches, and sync/backup failures. A new "Error logs" page in Profile offers level
    statistics, a list, export via the system share sheet, copy-all, and clear.
    **Local only — nothing is ever uploaded.**
  - **Movie details**: real TMDB cast avatars and stills, a new **cast & crew sheet** (grouped by
    director / actors, searchable) and a **stills & posters gallery** (tabbed, lazily built with
    slivers). Stills are cached to disk, so reopening the gallery makes zero network requests.
  - **Lookup enhancements**: a "self-hosting guide" entry on the data-source page (Markdown tutorial
    with GitHub + Render free-hosting examples); book search now aggregates multiple sources
    (dedup + merge, with Chinese category mapping); the custom source adapts to Douban-style APIs
    (`pubdate`, nested `rating`, HTML stripping); cover requests add a `Referer` per host, mirror
    fallback, two-level caching, and layered timeouts with one retry.
  - **Sync**: new record-level **LWW merge engine** (union by id, newer `updatedAt` wins) and a
    **pre-sync local snapshot** safety net (keeps the most recent few, so a bad merge can be rolled
    back); sync / restore / export are mutually exclusive, and pending writes are flushed before a
    restore; JSON cloud backups are now discoverable (both `.zip` and `.json` are listed/restored).
  - **Images**: single-image compression with a size ceiling (magic-byte sniffing → proportional
    downscale to a max long edge → re-encode, kept under 5 MB on disk).
  - **Editing**: ratings are manual only (auto-fill removed); the star picker supports drag scoring
    with cross-threshold haptics; manually entered books can fetch a cover online; the movie detail
    header uses a horizontal card layout; profile sheets share a consistent height.
  - **Performance**: the cast list and actor filmography switched from eager building to
    `CustomScrollView` + `SliverList.builder`; the `prefer_const_constructors` lint family is fully
    satisfied.
  - **Post-v0.9.3 development batches** (added before tagging):
    - **Module decoupling completed**: cross-module sibling imports **49 → 0** — a shared kernel was
      extracted into `business/shared/` (7 cross-module DTOs + the shared `LibraryStore` repository
      + the category mapper), `LibraryFacade` / `DataSourceFacade` interfaces were introduced
      (other modules depend on the interfaces only; the app layer registers the same instance), and
      cross-module navigation now goes through centralised routing
      (`AppRoutes` + `app/router.dart`).
    - **Edit controllers**: `BookEditController` / `MovieEditController` (ChangeNotifier) make the
      editing logic unit-testable without a widget tree; 69 new unit tests.
    - **Long functions eliminated**: all 30 functions ≥80 lines were split (longest 194 → 44 lines).
    - **String constants layer**: `foundation/constants/app_strings.dart` consolidates 53 reused
      strings across pages.
    - **Typography scale**: `app/config/app_typography.dart` defines the `AppType` size constants
      (convention for new code).
    - **Robustness**: `Movie.copyWith`'s `emoji` now uses a sentinel (fixes a lost placeholder on
      every edit save); data-source exceptions carry structured semantics (`DataSourceErrorKind`, so
      status decisions no longer match Chinese message text); backup parsing normalises boundary
      errors (type errors become `BackupException`); corrupted settings / data-source configs are
      quarantined and fall back to defaults.
    - **Misc**: six bottom-sheet drag handles consolidated into `SheetGrabber`; gradient-card
      opacities named via `_OnGradient`; the "no cover found" hint now branches on whether an ISBN
      was provided; deferred seed loading (production startup no longer copies demo data); AppLogger
      gained incremental counters and a subscribing log page.
- **v0.9.2**: book detail/edit UI rework — the detail page became a cover + rating card + two-column
  info cards + synopsis/notes layout; the edit page became a top-bar cancel/save pill with grouped
  card forms, and reading progress changed from a slider to "pages read / total pages" inputs
  (0 pages → plan to read, full → finished), with the delete button shown in edit mode only. Added a
  `publisher` field wired to online lookup. Fixed a save-ordering defect: the confirmation dialog for
  reverting reading progress used to appear after the loading state, so the button spun before the
  dialog; it is now shown before loading.
- **v0.9.1**: fixed a bug where the list page did not refresh after deleting a book/movie (the
  `UnmodifiableListView` dynamic view made `context.select` miss the change); unified the profile
  edit sheet to the BottomSheet style; enhanced book lookup — added `BookDataSource.getBookDetail`,
  Google Books/OpenLibrary now backfill category/pages/synopsis, results collapse into a "filled"
  state after picking, and custom sources gained a `detailUrlTemplate` config (graceful degradation
  when empty); custom movie sources gained detail-interface configuration too.
- **v0.9.0**: three-section personal statistics dashboard — annual metric bar + GitHub-style
  contribution heatmap (30-day / quarterly / annual), category preference donut + rating
  distribution bars (pure CustomPainter), reading progress bars + annual five-star cover wall; plus
  an annual report page (last finished / fastest reading week / the book that broke your preference).
  Removed built-in demo seed data: first launch is an empty library (tests and the Web preview still
  use mock data).
- **v0.8.2**: smart parsing for custom data sources (user-provided API config); local image caching
  (avoids repeated downloads); WebDAV compatibility fixes.
- **v0.8.1**: improved the profile info sheet; fixed duration input echo in the movie editor; global
  request throttling for data sources to avoid 429s; switched the default book source from Google
  Books to OpenLibrary (no API key, no rate limit); implemented the OpenLibrary source; deduplicated
  shared components between the book/movie editors (M4/M5); wrapped up the code-review report
  (spec details, dependency cleanup, test isolation).
- **v0.8.0**: dark/light themes, offline-first, dual book-and-movie tracking, WebDAV cloud sync, and
  online metadata lookup.

## Architecture

Four-layer componentisation + MVVM. Dependencies flow strictly one way — **upper layers may depend
on lower ones, never the reverse**:

```
app (5)  →  business {shared kernel} (75)  →  component (9)  →  foundation (16)
```

| Layer | Responsibility | May depend on |
|---|---|---|
| `app/` | Application layer: global config (theme / transitions / typography), root container, **global route table** | all layers below |
| `business/` | Business layer: split by **module**, each with internal MVVM layering; `shared/` is the cross-module kernel | `shared` / `component` / `foundation` |
| `component/` | Reusable UI components and design tokens | `foundation` |
| `foundation/` | Logging / network / storage / utils / **route names & string constants**; knows no business models | none |

**Hard rules**:

1. **Page naming**: always `xxx_page.dart` → class `XxxPage`.
2. **View naming**: name by function (`xxx_card.dart` / `xxx_sheet.dart` / `xxx_picker.dart`);
   **never use the `widget` keyword** in file or class names.
3. **Design tokens** live in `component/theme/app_palette.dart`; the type scale lives in
   `app/config/app_typography.dart` (`AppType`, used by new code; existing code migrates as touched).
4. `foundation/` must not import anything from `business/` (models included).
5. `component/` must not import `business/`. When business capability is needed, declare a
   **contract + InheritedWidget** in the component layer and inject the implementation from the app
   layer above `MaterialApp` (see `component/media/local_media_scope.dart`).
6. **Zero direct references between business modules** (achieved in v0.9.3). Cross-module
   collaboration has exactly two allowed paths:
   - Depend on the `business/shared/` kernel: pure DTOs (`model/`), the shared repository
     (`repository/library_store.dart`), the facade interfaces (`library_facade.dart` /
     `data_source_facade.dart`) and pure utilities;
   - Navigate via `Navigator.pushNamed(AppRoutes.xxx)` (route-name constants live in
     `foundation/constants/app_routes.dart`), with **page construction centralised in
     `app/router.dart`** — never import a sibling module's Page class.
7. **Facade registration**: `LibraryProvider` / `DataSourceProvider` implement `LibraryFacade` /
   `DataSourceFacade`; the app layer registers the **same instance** via
   `ListenableProvider<Facade>.value` (use `ListenableProvider`, not `Provider` — only the former
   subscribes to notifications so `context.select` rebuilds).

## Directory structure

```
lib/ (106 .dart files, ~25,000 lines)

├── main.dart                          # Entry: provider wiring (incl. facade dual-registration),
│                                      #   global exception guards, theme & transition setup
│
├── app/                               # (1) Application layer (5 files)
│   ├── config/
│   │   ├── app_theme.dart             # Palette → ThemeData (Material 3)
│   │   ├── app_typography.dart        # AppType type-scale constants (single source for sizes)
│   │   └── fade_slide_transitions.dart # Global page transition: fade + slight rise
│   ├── pages/
│   │   └── root_page.dart             # Root container: bottom navigation (Dashboard/Books/Movies/Profile)
│   └── router.dart                    # Global route table: builds the pages for each AppRoutes entry
│
├── business/                          # (2) Business layer — by module + shared kernel (75 files)
│   ├── shared/                        # Shared kernel (11 files): the only cross-module dependency
│   │   ├── model/                     # Cross-module DTOs (7): book / movie / actor / stats /
│   │   │                              #   user_profile / sync_settings / data_source
│   │   ├── repository/
│   │   │   └── library_store.dart     # JSON storage: atomic write / merged write / schemaVersion / images
│   │   ├── library_facade.dart        # Library facade contract (consumed by stats / profile / sync)
│   │   ├── data_source_facade.dart    # Data-source facade contract (consumed by library editors / sync)
│   │   └── book_category_mapper.dart  # English → Chinese category mapping (pure, zero deps)
│   │
│   ├── library/                       # Book & movie library (29 files)
│   │   ├── model/                     # Module-local models (3): cast_item / edit_result / mock_data
│   │   ├── repository/                # Startup wiring (3): persistence{,_io,_stub} (conditional import; Web → memory)
│   │   ├── page/                      # 8 pages: books / movies / book_detail / book_edit /
│   │   │                              #   movie_detail / movie_edit / movie_stills / actor_detail
│   │   ├── view/                      # 12 view components: details / edit forms / sheets / cards / ratings
│   │   └── view_model/                # library_provider (global state) + book/movie_edit_controller
│   │
│   ├── data_source/                   # Online metadata lookup (13 files)
│   │   ├── model/deploy_guide.dart    # "Self-hosting guide" Markdown string constants
│   │   ├── page/data_source_page.dart # Data-source management (movie/book sections, default-source radio, connection test)
│   │   ├── service/                   # Interface / registry / credential store / result merger + 4 implementations
│   │   │                              #   (TMDB / OpenLibrary / Google Books / custom smart parsing)
│   │   ├── view/                      # Source list & config sheet / self-hosting guide sheet
│   │   └── view_model/                # data_source_provider: implements the DataSourceFacade contract
│   │
│   ├── stats/                         # Statistics & charts (10 files)
│   │   ├── model/statistics.dart      # Three-section dashboard aggregation (heatmap / categories / ratings / annual)
│   │   ├── page/                      # dashboard / personal_stats / annual_report
│   │   └── view/                      # stats_card / heatmap_calendar / chart_view and other chart components
│   │
│   ├── sync/                          # Cloud sync & backup (8 files)
│   │   ├── page/data_sync_page.dart   # Sync (WebDAV cloud sync + local export/import)
│   │   ├── service/                   # webdav_client (PROPFIND/MKCOL/PUT/GET) / backup /
│   │   │                              #   merge_engine (LWW) / snapshot / secure_storage
│   │   ├── view/data_sync_view.dart   # Sync page components (config card / actions / merge summary)
│   │   └── view_model/sync_provider.dart # Mutually exclusive sync actions (upload / restore / auto-sync)
│   │
│   └── profile/                       # Profile & logs (4 files)
│       ├── page/                      # profile_page / error_log_page
│       └── view/                      # profile_view / error_log_view
│
├── component/                         # (3) Shared UI components (9 files)
│   ├── common/                        # grid_item_card / progress_ring / sheet_grabber
│   ├── media/                         # media_cover / media_tile / cover_placeholder /
│   │                                  #   local_media_scope (contract injection) / model/media_ref
│   └── theme/app_palette.dart         # Global palette ThemeExtension (dark / light) + context.colors
│
└── foundation/                        # (4) Foundation layer — knows no business (16 files)
    ├── constants/                     # app_routes (route names) / app_strings (shared copy)
    ├── logger/                        # Logging hub: levels + ring buffer + serialised writes + 2 MB rolling
    │                                  #   (io / stub per platform) + export (io / stub)
    ├── network/                       # cover_headers (Referer) / http_retry (layered timeout + retry)
    ├── storage/secure_store.dart      # Minimal credential interface + Keychain / Keystore impl
    └── utils/                         # date_format / image_pick / image_compress / ttl_cache
```

## Tests

`test/` contains **35 test files with 490 cases**, covering:

- **Models & storage**: JSON round-trips, `LibraryStore` atomic/merged writes and `schemaVersion`,
  the image pipeline and compression ceiling
- **State layer**: `Provider` persistence and concurrent writes; the logging hub's ring buffer,
  incremental counters, concurrent write chain, and truncation alignment
- **Edit controllers**: `BookEditController` / `MovieEditController` unit tests without a widget tree
  (form normalisation, director↔actor sync, lookup backfill, sentinel semantics)
- **Online lookup**: data-source config and credentials, result caching (TTL + LRU), multi-source
  aggregation and dedup, custom-source smart parsing, field-backfill regressions, layered timeouts
  and retries on weak networks, cover host detection
- **Sync**: backup round-trips (JSON / ZIP with images), WebDAV PROPFIND, the LWW merge engine,
  snapshot fallback
- **Statistics**: heatmap dedup rules, category shares, rating buckets, annual-report highlights
- **UI flows**: suggestion input, filter reset, long-press navigation, list refresh after delete,
  empty-state tap-through on the dashboard, cast sheet and stills page, drag star rating, error-log
  page, and narrow-screen layout regressions

## Feature notes

- **Dark / light themes**: the palette is injected as a `ThemeExtension` and always read via
  `context.colors.xxx`. Dark is the original design (`#0F0F0F` background / `#1A1A2E` cards); light
  is its inverse (near-white background, pure-white cards, dark-grey text). The preference is stored
  in `profile.json` and restored on restart; "follow system" is supported.
- **Graceful covers**: local images and remote URLs are supported; a missing cover or a load failure
  falls back to an HSL gradient with a letter/emoji mark, so the layout never breaks offline.
- **State management**: Provider (`ChangeNotifier`) is the single source of truth; the UI only reads
  from it and all writes persist through it. List pages narrow their subscriptions with
  `context.select` to avoid unrelated rebuilds. Cross-module consumption goes through the facade
  interfaces (`LibraryFacade` / `DataSourceFacade`) — depending on abstractions, not sibling
  implementations.
- **Circular progress ring**: `CustomPainter` + `SweepGradient` with a 900 ms eased animation.
- **Suggest-as-you-type input**: book categories and movie genres are multi-select tags combining
  suggestions and free text; a movie's director is automatically pinned to the first cast slot on
  focus loss.
- **Error logging**: levelled records with a 500-entry in-memory ring buffer and a 2 MB rolling file,
  replayed at startup — so a crash on the previous launch is still visible on the next one.
  **Only errors / warnings / crashes and request failures are recorded; browsing behaviour is never
  tracked and nothing is uploaded.** See the `AppLogger` doc comments for the privacy constraints.

## Implemented

- **Local persistence**: JSON file storage (`LibraryStore`) with atomic writes (`.tmp` + rename),
  `schemaVersion` validation, automatic merging of writes within the same tick, and a serialised
  write chain to prevent concurrent overwrites; the user profile lives in its own `profile.json`
- **Full CRUD for books / movies / actors**: three editors plus detail pages; deleting an actor that
  is still referenced by a movie is rejected with the referencing titles listed
- **Search & filtering**: keyword search; category / genre / status dropdown filters whose options
  are derived from existing data (including user-defined values); tapping an author on a detail page
  jumps to the library with the filter pre-filled
- **Image management**: pick from the gallery / paste a URL / remove a cover; images are copied into
  the app's private directory and compressed under the size ceiling; orphaned files are reclaimed on
  replace or delete
- **Cast & stills**: the movie detail page's "Cast & crew" entry opens a grouped, searchable sheet;
  "Stills → All" opens a tabbed stills-and-posters gallery whose images are cached to disk, so
  reopening makes zero network requests; tapping an actor opens their page with a full filmography
- **Dashboard driven by real data**: both stat cards, current tasks, and the reading/movie grids are
  computed live from library data with empty-state fallbacks; when the library is empty the whole
  empty-state card is tappable and leads straight to "Add book / Add movie"; "View all" switches to
  the corresponding tab
- **Profile**: nickname / signature / avatar editing (tapping the avatar card shows a read-only
  sheet; "Edit profile" opens the editor), a statistics page, and theme selection
- **Three-section dashboard statistics (personal stats page)**: a top annual metric bar (X books ·
  Y movies · Z hours watched) plus a GitHub-style contribution heatmap (30-day / quarterly / annual;
  counting rule: one entity counts once per day, different entities accumulate; four shades for
  0 / 1 / 2 / 3+, aggregating a book's createdAt / startedAt / finishedAt and a movie's watchDate);
  a middle category-preference donut (top 5 with a percentage legend) and a 1–5 star rating
  distribution bar chart (both pure `CustomPainter`, zero third-party dependencies); and a bottom
  reading-progress list (3 by default, with a "view all" sheet), the annual five-star cover wall and
  the annual-report entry — every section has an empty-state message
- **Annual report**: a yearly snapshot page (`annual_report_page.dart`) with a gradient overview card
  (books finished / pages read / hours watched / top category of the year), the last book finished,
  the week with the most pages read, and the book that broke your preference (a book finished this
  year whose category differs from your overall most frequent one); computed live from the data
- **Sync / backup**: WebDAV cloud sync (Jianguoyun, Nextcloud and other standard WebDAV services) —
  four server settings plus a connection test, immediate backup / restore from cloud (with a
  confirmation dialog and a local snapshot fallback), auto-sync on launch (optionally Wi-Fi-only,
  throttled to once an hour), and backups optionally including local images (single JSON file or a
  ZIP with images). Cross-device conflicts are resolved by a **record-level LWW merge** (union by id,
  newer `updatedAt` wins) with a local snapshot kept before and after the merge for rollback. Local
  export opens a save-location picker so you choose the destination (the include-images toggle
  follows the sync preference: on → ZIP, off → JSON) — the fallback for offline environments.
  Credentials live in the platform secure storage (Keystore / Keychain); `settings.json` never
  contains the password; the feature is hidden on Web
- **Online metadata lookup (optional)**: "Data sources" in Profile — TMDB is built in for movies;
  OpenLibrary (default) and Google Books for books. **Adding a third-party site needs no built-in
  preset**: fill in a Base URL and API key for a custom source and the smart parser takes over
  (recursively finds the data list, maps Chinese/English field aliases, and understands plain arrays,
  `{data: […]}` and `{results: […]}` shapes) — which is how Douban, Bangumi and similar sites work.
  The page also ships a "self-hosting guide" (Markdown tutorial with GitHub + Render free-hosting
  examples). Multiple sources can be added with one marked as default, and each supports a connection
  test and config editing. The "Quick search" box at the top of the book/movie editors searches
  online as you type (500 ms debounce + TTL/LRU result cache) and fills the form when you pick a
  result (books: ISBN and cover; movies: director / cast / runtime / genres / poster), recording the
  provenance in `source` on save. Book search aggregates multiple sources (dedup + merge, with
  Chinese category mapping). Cover requests add a per-host `Referer` to bypass hotlink protection,
  with mirror fallback, layered timeouts and one retry. The TMDB API key is stored in secure storage;
  data-source configs are included in backup/restore via `data_sources.json` (schemaVersion 2,
  backward compatible), and after a cloud restore the configs reload automatically with a prompt for
  sources missing credentials. When nothing is configured or the network is down, the lookup block
  hides itself and manual entry is unaffected
- **Error logs (Profile → Error logs)**: levelled and categorised records of app errors and request
  failures, covering global uncaught exceptions (framework and async), exhausted network retries,
  data-source fetch failures, and sync/backup errors. The page provides level statistics, a
  newest-first list, **export** (writes a local `.txt` and opens the system share sheet),
  **copy all** (clipboard) and **clear** (with confirmation). Data stays on-device; you decide
  whether to send it to the developer

## Roadmap (not implemented)

- [ ] Annual goals: set yearly reading / watching targets and track completion on the dashboard
  (charts and the annual report already exist; goal tracking has not started)
- [ ] Wire up the dashboard's top-bar search / notification buttons (currently no-ops)

## Development conventions

- **Dependency direction**: strictly one-way — `app → business → component → foundation`.
- **Module decoupling**: business modules have zero direct references. Cross-module data goes through
  `business/shared/` (DTOs / repository / facade interfaces); cross-module navigation goes through
  `AppRoutes` route names (page construction centralised in `app/router.dart`). Importing a sibling
  module's page / view_model is forbidden.
- **Colours**: always `context.colors.xxx`; static constant colours are forbidden (a `const` subtree
  would not repaint on theme change). New code uses `AppType` constants for font sizes.
- **Naming**: pages are `XxxPage` / `xxx_page.dart`; view components are named by function and must
  not use the `widget` keyword.
- **Change tests alongside code**: touching `LibraryStore`, the merge engine, data-source parsing or
  other core logic requires accompanying tests. The acceptance bar for any change is
  `flutter analyze` (0 issues) plus a fully green `flutter test`.
- **Format gate**: the `dart format --set-exit-if-changed` step in CI is commented out by default;
  to enable it, run `dart format .` locally first and then uncomment the step in
  `.github/workflows/ci.yml`.

## License

Released under the [MIT License](./LICENSE), Copyright (c) 2026 Aftery.
