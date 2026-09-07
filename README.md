# SquadIQ — Phase 1 + MVP1 implementation

## Update: Auth + Dashboard (MVP1 slice)

Added on top of the Phase 1 data layer below, per plan section 15's MVP1
scope:

- **Supabase Auth wiring** (`features/authentication/`): email/password
  sign-up and sign-in via `supabase_flutter`, with an `AuthRepository`
  that creates the app's own `users` row on first sign-up (bridging
  `auth.users` to the app's `users` table from `schema.sql`).
- **FPL account linking, read-only**: `AuthRepository.linkFplManagerId`
  takes only the user's *public* FPL manager ID (the number in their FPL
  profile URL) and verifies it resolves via `FantasyDataProvider` before
  saving it — no FPL username/password/session is ever requested or
  stored, per section 0's core constraint. `LinkFplAccountScreen` is the
  UI for this, shown automatically when a signed-in user has no linked
  ID yet.
- **Dashboard** (`features/dashboard/`): the single-screen home view from
  section 2 — deadline countdown (color-shifts as the deadline nears, per
  section 3's threshold idea), manager summary (team/points/rank),
  availability alerts (any squad player FPL flags as doubtful/injured/
  suspended), and a per-player next-fixture difficulty chip. This uses
  only raw FPL facts — no Player Rating / Expected Points / Confidence
  Score yet, since those are the Statistics Engine's job (MVP2, section
  15), not the dashboard's.
- **`main.dart`** now does real routing: `_AuthGate` shows `SignInScreen`
  or `DashboardScreen` based on Supabase auth state, and a
  `_MissingConfigScreen` if Supabase env vars weren't passed in.

### Running this slice

Supabase URL/anon key are read from `--dart-define` (never hardcoded,
per section 17):

```
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Apply `supabase/schema.sql` to that project first.

### What's still stubbed / next

- **Statistics Engine (MVP2)** doesn't exist yet — the dashboard's
  fixture-difficulty chip uses FPL's own difficulty rating directly as a
  placeholder for what will become `Player Rating` / `Expected Points`.
- **`fantasy_teams` table isn't populated yet.** The dashboard currently
  reads the user's squad straight from FPL's `picks` endpoint each load
  rather than caching it into `fantasy_teams.current_squad_snapshot` —
  wiring that cache is a natural next step once `drift`/offline support
  is prioritized.
- **No password reset / OAuth flow** — only email/password sign-up and
  sign-in, matching the minimum needed to prove the auth-gated routing
  works end to end.
- Same "no Dart SDK in this sandbox" caveat as Phase 1 applies: none of
  this has been run through `flutter analyze` or a real build. Review it
  as a first-pass implementation to compile and correct locally, not as
  already-verified code.

---

## Update: Statistics Engine (MVP2 slice)

Implements plan section 10 (Weighted Scoring Models) as a **pure,
deterministic** module — no AI/LLM calls, no randomness, no network I/O
inside the engine itself. This separation is the enforcement mechanism
for section 11's rule that the AI layer *explains* these numbers but
never invents or overrides them.

- **`StatisticsEngine`** (`features/statistics_engine/domain/statistics_engine.dart`)
  — pure functions computing, per player:
  - **Player Rating** (0–100): weighted blend of form (25%), upcoming
    fixture ease (20%), xGI (20%), minutes expectation (20%), ownership
    (5%), minus rotation risk (10%) — the exact weights from section 10.
  - **Rotation Risk** (0–100): minutes volatility, FPL's own
    availability flag, and positional competition, combined as a max
    (an injury flag alone is enough to flag risk, it doesn't need to
    "average out" with good minutes history).
  - **Expected Points**: a simple per-position model (goalkeeper/
    defender/midfielder/forward have different clean-sheet and goal
    point values, matching real FPL scoring rules).
  - **Captain Score**: expected points × 2, adjusted for fixture
    difficulty and starting certainty.
  - **Transfer Score**: expected-points delta over a gameweek horizon,
    minus a 4-point hit penalty when relevant, plus a small price-rise
    bonus.
  - **Differential flag**: ownership below 10% + rating above 60.
  - **Confidence Score**: derived from how much the underlying
    sub-scores *agree* with each other — this is what any future AI
    explanation attaches to a recommendation, per section 4's rule that
    confidence must come from the engine, not be asserted by the model.
  - **Team Rating + Gameweek Stance**: aggregates a starting XI into one
    number plus a deterministic label (attacking/balanced/defensive/
    differential-opportunity) — the AI layer turns this into prose, it
    doesn't decide the label.
- **`StatisticsRepository`** (`features/statistics_engine/data/`) — the
  only place that bridges `FantasyDataProvider` facts into the engine's
  input shape. Added `getPlayerHistory()` to `FantasyDataProvider` /
  `FplProvider` (via FPL's `element-summary/{id}/` endpoint) to get
  actual per-gameweek minutes and, where FPL exposes it, xG/xA — used
  for rotation-risk volatility and the xGI sub-score. Falls back to a
  documented form-based proxy when xG/xA isn't available for a player.
- **Dashboard integration**: the squad list now shows each starter's
  Player Rating next to their fixture-difficulty chip (tap/long-press
  for the reasons behind the number), and a new **Team Rating** card
  summarizes the whole starting XI with its gameweek stance.
- **`test/statistics_engine_test.dart`** — unit tests covering every
  method above (ordering sanity checks, boundary behavior, the exact
  points-hit penalty, differential flagging). Per plan section 8, this
  was called out as the top testing priority for the whole app; run with
  `flutter test` once you have the SDK locally — these haven't been run
  in this sandbox (no Dart SDK available here).

### Known simplifications to revisit

- Expected Points' clean-sheet probability is derived crudely from FPL's
  own fixture difficulty rating, not real club attack/defense strength —
  section 10 itself expects this v1 formula to be replaced once
  API-Football's team-strength data is wired up.
- `positionalCompetitorCount` is inferred heuristically (same club,
  same position, available, played minutes recently) rather than from a
  real depth-chart source — reasonable as a v1, worth revisiting if it
  produces obviously wrong rotation-risk calls for specific squads.
- The dashboard's rating badge only covers the starting XI, not the
  bench — bench-boost-aware Team Rating is a natural follow-up.

---

## Update: Emergency Coach (flagship feature, plan section 3)

Same pattern as the Statistics Engine: a **pure, deterministic**
`EmergencyCoachEngine` that detects problems and proposes fixes from
facts alone — the AI layer (when it's built) explains this output, it
never generates or overrides it (plan section 11).

- **`EmergencyCoachEngine`** (`features/emergency_coach/domain/`) checks
  the full 15-man squad for:
  - **Availability issues** — injured/suspended/unavailable starters
    (critical) vs. doubtful ones (warning only — a 75%-chance player
    isn't auto-benched, the user sees the context and decides). Critical
    flags get an automatic same-position bench-replacement suggestion,
    ranked by Player Rating.
  - **Blank fixtures** — a starter with no fixture this gameweek, with a
    bench alternative that does have one.
  - **Captaincy risk** — captain flagged unavailable (critical), or a
    fully-available starter whose Captain Score is >20% higher than the
    current captain's (informational swap suggestion).
  - **Bench stronger than starter** — a bench player rating 15+ points
    higher than a starter in the same position, informational only.
  - Every check **returns null/skips rather than fabricating a
    suggestion** when there's no valid same-position replacement — e.g.
    an injured goalkeeper with only midfielders on the bench produces
    the issue but no invented action.
- **`EmergencyCoachRepository`** composes the dashboard's already-loaded
  squad with `StatisticsRepository` scores for the full 15 (not just the
  starting XI, since bench players are the replacement candidates), then
  runs the engine. Includes `recordEvent()` to audit-log a plan to
  `emergency_coach_events` (schema.sql, plan section 13) — currently
  unused by the UI since it needs a `fantasy_teams.id` that doesn't
  exist yet (see the pending item below); wire it in once that table is
  populated.
- **UI**: a dashboard summary card (red for critical, orange for
  warning, hidden entirely when the squad is clean) linking to a full
  `EmergencyCoachScreen` listing every issue and every proposed action.
  No action is ever auto-applied — the user still makes every change
  directly in the official FPL app (plan section 0's hard constraint).
- **`test/emergency_coach_engine_test.dart`** — covers every rule above,
  including the "don't fabricate a suggestion" cases specifically, since
  that's the easiest thing to accidentally regress later.

### Pending items (unchanged/carried over)

- `fantasy_teams` still isn't populated from the app, so
  `EmergencyCoachRepository.recordEvent()` has no real `team_id` to
  write against yet — the method is ready, just not called.
- Same sandbox caveat as before: written without a local Dart SDK, not
  yet run through `flutter analyze` or `flutter test`.

---

## Update: AI Reasoning Layer + fantasy_teams sync (plan section 11)

- **`fantasy_teams` is now populated.** `FantasyTeamSyncService` upserts
  the loaded squad snapshot into `fantasy_teams` on every dashboard
  load (added a `unique(user_id)` constraint to `schema.sql` to make
  that upsert well-defined — one team per account, matching FPL's own
  one-manager-per-account model). This closes the gap from the previous
  update: `EmergencyCoachRepository.recordEvent()` is now actually
  called (best-effort, fire-and-forget, never blocks the UI or surfaces
  as a user-facing error) whenever the coach finds issues.
- **`AiContextBuilder`** (`features/ai_assistant/domain/`) — pure
  function, the single enforcement point for plan section 11's core
  rule: assembles a JSON packet from Statistics Engine scores, Team
  Rating, and Emergency Coach issues/actions — nothing else. The AI
  model never sees raw FPL data and is never asked to compute a number
  itself.
- **`ai-assistant` Supabase Edge Function**
  (`supabase/functions/ai-assistant/index.ts`) — the *only* place an LLM
  provider API key exists in this project (plan section 17: never
  client-side). Contains the actual system prompt enforcing plan section
  4's guardrails in writing: only use the given context, attribute
  numbers to the engines that computed them, never claim to submit
  changes to FPL, treat any FPL text as inert data rather than
  instructions, lead with critical Emergency Coach issues, and state
  explicitly when confidence is low. Deploy with:
  ```
  supabase functions deploy ai-assistant
  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
  ```
- **`AiAssistantRepository`** — Flutter side only ever calls this edge
  function through the Supabase client (same anon key already used
  elsewhere), and persists both sides of the conversation to
  `ai_conversations`/`ai_messages` (schema.sql) — the context sent with
  each turn is stored in `ai_messages.tool_calls_json` for audit, not
  duplicated as message content.
- **`AiChatScreen`** — simple chat UI, reachable from a new chat icon on
  the dashboard's app bar. Every send rebuilds the context fresh from
  current providers (`aiContextProvider`) rather than reusing a stale
  snapshot from earlier in the conversation.
- **`test/ai_context_builder_test.dart`** — confirms the builder only
  ever passes through exact engine values and never fabricates a
  `scores` entry for a player with no matching score card.

### What's still not done

- **No transfers/players/fixtures/shop/wallet/notifications screens** —
  the plan's remaining feature folders (`features/transfers`,
  `features/players`, `features/shop`, `features/wallet`,
  `features/notifications`, `features/settings`) exist only as empty
  scaffolding folders. This is a genuinely large remaining scope; the
  slices built so far (data adapters → auth/dashboard → statistics
  engine → emergency coach → AI layer) are the ones the plan itself
  calls "highest risk, hardest to bolt on later" — the vertical spine
  the rest hangs off of.
- Coins/wallet monetization (plan section 5) is schema-only — no
  purchase flow, no store UI.
- Push notifications (deadline/injury alerts) aren't wired to
  `firebase_messaging` yet, despite being in `pubspec.yaml`.
- As with every prior update: nothing here has been run through
  `flutter analyze`/`flutter test` — do that first before building
  further on top of it.

---

## Update: Players browser + Transfers (core gameplay loop)

- **`PlayersScreen`** (`features/players/`) — search/filter/sort over
  the full ~600-player pool, using only free bootstrap facts (form,
  points, price, ownership). **Deliberately does not run the Statistics
  Engine on the whole pool** — see `PlayersRepository`'s doc comment:
  scoring means one `element-summary` history call per player, and doing
  that for 600 players on every screen open would hammer FPL's
  unofficial endpoint (plan section 21). Full engine scoring stays
  reserved for bounded sets (a 15-man squad, or a small transfer
  shortlist — see below).
- **`TransfersScreen`** (`features/transfers/`) — pick any of your 15
  players to replace; suggestions are ranked by the Statistics Engine's
  Transfer Score over a 3-gameweek horizon (plan section 10). Two-stage
  filtering keeps this affordable against the same endpoint concern:
  stage 1 filters ~600 players down to a shortlist of 12 using only free
  facts (same position, availability, affordable given bank + sale
  price, ranked by raw form); stage 2 only then builds full engine
  inputs and scores that shortlist plus the outgoing player. Nothing
  here submits a transfer — same read-only constraint as everywhere else
  (plan section 0).
- Refactored `StatisticsRepository` to expose `buildEngineInputs()`
  publicly (previously a private helper only `scorePlayerIds` used) so
  Transfers can call `StatisticsEngine.calculateTransferScore` directly
  on a specific out/in pair, rather than going through the score-card
  bundle meant for squad-wide display.
- **`test/transfers_repository_test.dart`** — a hand-written fake
  `FantasyDataProvider` (no network, fully deterministic) exercising the
  real filtering rules end to end: position match enforced, budget
  enforced, availability enforced, and "no valid candidate" returns an
  empty list rather than an error.

### Still not done

- `features/fixtures`, `features/shop`, `features/wallet`,
  `features/notifications`, `features/settings` remain empty scaffolding
  — no screens built yet.
- No player detail screen (tapping a player in `PlayersScreen` currently
  does nothing) — a natural next step once there's somewhere to route
  to.
- Transfers doesn't yet account for points-hit costs or show the
  "free transfer available" state from `fantasy_teams` — it currently
  always assumes `isPointsHit: false`.

---

## Update: Fixtures, Settings, Wallet (schema-backed screens)

- **`FixturesScreen`** (`features/fixtures/`) — gameweek-tabbed fixture
  list with difficulty-colored badges for both sides of each match.
  `FixturesRepository.groupByGameweek()` is pure grouping/sorting logic
  split out from the fetch specifically so it's unit-testable without a
  data source — see `test/fixtures_repository_test.dart` (grouping
  correctness, gameweeks with no fixtures omitted, unknown-club fixtures
  skipped rather than crashing, sort-order independence from input
  order).
- **`SettingsScreen`** (`features/settings/`) — reads/writes
  `user_preferences` (schema.sql): four notification category toggles
  (deadline reminders, injury alerts, price changes, Emergency Coach
  alerts — the keys a future `firebase_messaging` integration would read
  from `notification_settings`, though that wiring itself still isn't
  done) and an AI tone preference (concise/detailed) that would flow
  into the edge function's system prompt once threaded through — not yet
  connected to `AiAssistantRepository`, worth doing as a quick follow-up
  since the column already exists.
- **`WalletScreen`** (`features/wallet/`) — **read-only** balance and
  transaction history from `wallets`/`coin_transactions`. Deliberately
  has no spend/purchase methods: per the schema's own RLS policy (and
  plan section 5), coin balance changes only happen through a backend
  service role after server-side receipt validation — building that
  service is a separate backend piece, out of scope for this
  Flutter-only slice. This screen is honestly just a viewer until that
  exists.
- Dashboard app bar now has entry points for all of the above
  (Fixtures, Transfers, Players, Ask SquadIQ, Wallet, Settings) — moved
  sign-out into the Settings screen rather than a standalone AppBar
  icon, now that there's a natural home for it.

### Rough completion status (see also the earlier percentage breakdown
### discussed with the user — this list reflects the delta since then)

| Area | Status |
|---|---|
| Data Adapters + Schema | Solid — FPL adapter complete, no 2nd source yet |
| Auth + Dashboard | Functional — no password reset/OAuth |
| Statistics Engine | v1 complete + tested — heuristic-based, not ML |
| Emergency Coach | Complete for its 4 rule categories + tested |
| AI Reasoning Layer | Wired end-to-end — no conversation memory beyond one session's context |
| Players / Transfers | Functional core loop, no player detail screen |
| Fixtures | Functional, tested |
| Settings | Functional, AI tone not yet threaded to the edge function |
| Wallet | Read-only viewer only — no purchase flow (needs a backend service) |
| Notifications (push) | Not started — `firebase_messaging` unused |
| Shop / Monetization UI | Not started |
| CI / `flutter analyze` / `flutter test` runs | Never run — no Dart SDK in this environment |

Still no local Dart SDK available in this sandbox to verify any of this
compiles — that remains the single most important next step before
building further.

---

## Update: Notifications + Shop (last two planned feature folders)

- **Local deadline reminders** (`features/notifications/`) —
  `NotificationRules` is pure scheduling logic (given a deadline and
  "now", which of the 48h/6h/90min thresholds still apply — plan section
  3's escalation idea) with no plugin dependency, fully unit-tested in
  `test/notification_rules_test.dart`. `NotificationScheduler` is the
  only place touching `flutter_local_notifications` directly. Wired to
  re-schedule on every dashboard load, gated on the
  `deadline_reminder`/`emergency_coach` toggles from Settings.
  **This is local-only** — it works from data already on the device, no
  backend needed. True server-initiated push (e.g. "a squad player's
  status just changed" detected server-side while the app is closed)
  still needs `firebase_messaging` wired to a real trigger, which is not
  built.
- **`ShopScreen`** (`features/shop/`) — lists `store_products`, but the
  "Buy" button is **honestly a placeholder**, not a working purchase.
  There's no `in_app_purchase` package integration, so there's no way to
  get a real platform receipt to validate. `ShopRepository` and the
  `validate-purchase` edge function exist and show the intended shape
  (client gets a receipt → sends it to the edge function → server
  validates and credits coins), but the edge function's receipt check is
  a stub that accepts anything non-empty — the file's own header comment
  flags this explicitly as not production-ready and lists what real
  Apple/Google receipt verification would require.

### Every plan section 15 feature folder now has *something* in it

Data adapters, auth, dashboard, statistics engine, emergency coach, AI
assistant, players, transfers, fixtures, settings, wallet, notifications,
and shop all have working (or honestly-labeled-as-stubbed) code now. The
remaining real work is depth, not breadth:

1. **Verify it actually compiles** — `flutter pub get` + `flutter
   analyze` + `flutter test`, none of which have run against this code
   yet (no Dart SDK in this sandbox).
2. **Real in-app-purchase integration** for Shop (the biggest genuine
   gap — everything else at least functions read-only).
3. **Real receipt validation** in `validate-purchase` (security-critical
   — do not ship the stub).
4. **Server-initiated push** via `firebase_messaging` for alerts that
   need to fire while the app is closed.
5. **Player detail screen**, **onboarding flow**, **password reset/OAuth**
   — smaller UX gaps noted throughout this file.
6. A second fantasy-data source (API-Football) per plan section 6's own
   risk mitigation for relying on FPL's unofficial endpoints alone.

---

## Fix: Flutter Web CORS (fpl-api Edge Function)

**The problem**: Flutter Web builds got CORS errors calling FPL directly
— the browser blocks it because FPL's response has no
`Access-Control-Allow-Origin` header for our domain. This is not
fixable from the client side; it's the browser enforcing same-origin
policy on FPL's response. Native builds (Android/iOS/desktop) never hit
this at all — CORS is a browser-only concept.

**What NOT to do**: an earlier iteration of this fix (done outside this
session, against a locally-modified copy) routed failed web requests
through a public third-party CORS proxy (`allorigins.win`). That was
reverted — a public proxy has no reliability or privacy guarantees,
every user's FPL data would transit an uncontrolled third party, and
FPL blocking that proxy's IP would break the app for every user at
once. **If you see any reference to `allorigins.win` or a similar public
CORS proxy anywhere in this codebase going forward, remove it — it was
explicitly rejected, not an oversight.**

**The actual fix**:
- **`supabase/functions/fpl-api/index.ts`** — a new, minimal Edge
  Function that proxies `GET` requests to `fantasy.premierleague.com/api`
  and attaches the CORS headers the browser needs. Deliberately a dumb
  proxy: no caching logic beyond a 60s edge-cache header, no
  FPL-specific parsing — all real TTL/caching stays in `FplProvider`'s
  `TtlCache` so behavior is identical whether a request went direct
  (native) or through this proxy (web).
- **`FplProvider._resolveBaseUrl()`** — the single place that decides
  which base URL to use, decided once at construction: `kIsWeb == true`
  routes through the Edge Function; every other platform calls FPL
  directly. No request-time fallback between the two — see the class's
  own doc comment for why that matters (a silent runtime fallback is
  exactly the pattern that led to the rejected proxy approach above).

**Deploy the Edge Function before testing on web**:
```
supabase functions deploy fpl-api --no-verify-jwt
```
`--no-verify-jwt` is correct here — this proxies public, unauthenticated
FPL data, there's no user identity to check. Optionally set
`ALLOWED_WEB_ORIGIN` (via `supabase secrets set`) to your actual deployed
web domain instead of the `*` default before shipping to production.






---

# Phase 1 (original): Data Adapters + Schema

This is the first slice of code from the project plan, following its own
recommended order: **Phase 0/1 → Data Adapters + Schema before any UI**
("أغلى غلطة ممكنة هنا هي تبني المنتج على مصدر بيانات هيتغيّر بعد شهرين").

## What's built here

- **Folder skeleton** (`lib/`) matching plan section 8's feature-based
  Clean Architecture, including the standalone `statistics_engine` and
  `data_providers` modules.
- **`FantasyDataProvider`** (`lib/data_providers/fantasy_data_provider.dart`)
  — the abstract interface every feature depends on. It is **read-only by
  design**: no transfer/captain/chip-submission method exists on it, per
  the legal/technical warning in plan section 0.
- **`FplProvider`** — a concrete implementation over FPL's public
  `bootstrap-static`, `fixtures`, and `entry/{id}` endpoints. Includes:
  - Retry with backoff for transient failures (`core/network/dio_client.dart`)
  - A TTL cache with a stale-fallback path, so a single failed FPL call
    degrades to "serve last known data" instead of an error (plan section
    21's mitigation for "FPL قد توقف الـ Endpoint فجأة")
  - Typed `AppFailure`s so callers (and later, the AI context builder)
    can tell "network blip" from "response shape changed" from "serving
    stale cache" — this distinction is what lets the AI layer say "I
    don't have fresh data" instead of guessing (plan section 4 guardrails)
- **Data models** for `Club`, `Player`, `Gameweek`, `Fixture`,
  `ManagerEntry`, and `SquadPick` — hand-written `fromJson`/`toJson` for
  now (see note below on `freezed`).
- **`supabase/schema.sql`** — implements every table from plan section 9,
  plus indexes from that section and baseline Row-Level Security policies
  from section 17. `coin_transactions` is append-only by omission: no
  authenticated-role INSERT/UPDATE/DELETE policy exists, so writes are
  only possible via a backend service role after server-side receipt
  validation.
- **`lib/main.dart`** — a throwaway smoke-test screen (not a real UI) that
  proves the adapter wiring works: it fetches gameweeks through
  `FantasyDataProvider` via Riverpod and shows the current deadline
  countdown. Delete this once `features/dashboard` exists.

## Deliberate simplifications vs. the plan (and why)

- **Models are hand-written, not `freezed`-generated.** The plan's stack
  (section 8) specifies `freezed` + `json_serializable`. This sandbox has
  no Dart/Flutter SDK to run `build_runner`, so generating and verifying
  codegen output here isn't possible. `freezed_annotation` /
  `json_serializable` are still in `pubspec.yaml`; migrating these five
  model files to `@freezed` classes once your team has local tooling is a
  mechanical, low-risk follow-up — do it before the models grow copyWith
  logic by hand in more than one place.
- **No `drift` local DB wiring yet.** The interface and adapter are done;
  offline caching of the user's squad (section 8) is a Phase 1 follow-up
  once `features/squad` exists to consume it.
- **No Supabase client wiring yet** — the schema is ready to run, but
  connecting `supabase_flutter` and Riverpod providers for auth/CRUD is
  naturally sequenced after this data layer, per the plan's own week-by-
  week breakdown (section "خطة التنفيذ العملية", weeks 2–4).
- **API-Football / RotoWire adapters are not implemented yet** — only
  the interface they'll implement (`FantasyDataProvider`) exists. Per
  plan section 6, FPL alone covers prices/points/ownership; fixtures'
  difficulty here still comes from FPL's own rating as a placeholder
  until the API-Football adapter lands.

## Before you run this for real

1. Run `flutter pub get`, then `dart run build_runner build` once you
   introduce any `@freezed`/`@JsonSerializable` classes (not required yet
   — current models don't use codegen).
2. Apply `supabase/schema.sql` to a fresh Supabase project
   (`supabase db push` or paste into the SQL editor).
3. Do the Phase 0 checks the plan calls out explicitly before writing
   more code against FPL's endpoints: confirm current rate-limit
   behavior and response shapes haven't drifted, since they're
   unversioned and unofficial (plan sections 0 and 21).

## Suggested next slice

Per the plan's MVP1 scope (section 15): wire `supabase_flutter` for auth
+ the `users`/`fantasy_teams` tables, then build `features/dashboard` to
consume `FantasyDataProvider` for real — deadline countdown, current
squad snapshot, and a basic fixture ticker.

---

## Update: Visual identity — "Matchday" design system

A full design system, applied app-wide via `ThemeData` rather than
per-screen styling. See `lib/core/theme/app_theme.dart` for the complete
rationale; summary:

- **Palette** (`app_colors.dart`) — a dark "under the floodlights" base
  (`nightPitch`/`turfSurface`) rather than a bright SaaS-white
  background, so the functional accent colors carry real weight:
  Turf Green (brand/positive), Armband Gold (captaincy only — kept rare
  on purpose), Red Card (critical only), Caution Amber (warning),
  Assist Blue (differential/info).
- **Type** (`app_typography.dart`) — Barlow Condensed (bold, tabular
  figures) for anything that should read like a stadium scoreboard —
  Player Rating, Team Rating, prices, the deadline countdown — paired
  with Inter for body/list text. Two families, two clearly separate
  jobs, not a random mix.
- **`StatusColors`** (`status_colors.dart`) — a `ThemeExtension`
  exposed as `context.status.{good,warning,critical,info,featured}`.
  This replaced every hardcoded `Colors.green`/`Colors.red`/etc. across
  the app (dashboard, emergency coach, fixtures, wallet) with one
  semantic source of truth — green/gold/amber/red/blue now mean the
  same thing on every screen, not just "whatever felt right in this
  particular widget."
- **`StatNumber`** / **`StatusAccentCard`** (`core/widgets/`) — the two
  reusable pieces that encode the system's layout principles: big
  condensed numerals with a caption (scoreboard, not spreadsheet), and
  a 4px left-edge color bar instead of tinting a whole card background
  (avoids the generic "every card is a different pastel" SaaS look,
  especially in lists of several issues/alerts at once).
- Refactored to the new system: `DashboardScreen` (the flagship
  example — deadline card, team rating, alerts, fixture ticker all use
  `context.status` + the new widgets), `EmergencyCoachScreen`,
  `FixturesScreen`, `WalletScreen`, and the inline error text in
  `SignInScreen`/`LinkFplAccountScreen`/`AiChatScreen`.

### Not yet themed / follow-ups

- `PlayersScreen`, `TransfersScreen`, `SettingsScreen`, `ShopScreen`
  didn't have hardcoded colors to begin with (they only used default
  Material widgets), so they already inherit the new theme automatically
  — but haven't been hand-tuned to use `StatNumber`/`StatusAccentCard`
  where it'd help (e.g. Transfer Score readouts could use `StatNumber`).
- **`google_fonts` fetches font files from Google's CDN at runtime** by
  default — fine for development, but see the production note in
  `app_typography.dart` about bundling both fonts as local assets before
  shipping (avoids the external network dependency and any GDPR
  consideration for EU users).
- No light theme — the system is dark-only by design intent (see
  `app_theme.dart`'s rationale), but if a light mode is ever wanted,
  `StatusColors` and the type scale would need a second variant.
