# فلوس (Floos)

A deliberately minimal expense tracker for iOS + Android, built in Flutter.
This is a **starter skeleton** — the spine the rest of the app hangs off — with
the original app's worst bugs designed out from the start rather than patched
later.

> The package is named `floos` (`pubspec.yaml` `name:`, `package:floos/...`
> imports). Bundle/app IDs under `android/`/`ios/` still use the original
> `masareef` placeholder and should be updated before publishing.

---

## What's baked in (and why)

Three of the original's complaints were the same root cause: recurring entries
that depended on background execution, which iOS suspension and Android Doze
silently kill. The fixes:

- **Recurrence is lazily evaluated, not scheduled.** We store recurrence
  *rules*, and on every launch/resume a deterministic catch-up
  (`lib/domain/recurrence_engine.dart`) materializes any occurrences that came
  due while the app was closed, then advances a per-rule marker. No background
  task, nothing dropped, and running it repeatedly is idempotent. The pure date
  math lives in `lib/domain/recurrence_math.dart` and is covered by
  `test/recurrence_math_test.dart`. This single decision fixes fixed-monthly
  income, lagging weekly expenses, and inconsistent monthly bills at once.

- **Savings is a ledger, not a stored balance.** The current amount is always
  `SUM(contributions)` (`SavingsDao.watchTotal`), never a mutable field that can
  drift out of sync — which is the usual cause of "savings is buggy as fuck."

- **Reactive lists.** The UI reads drift `.watch()` streams, so an insert
  (including ones the recurrence engine generates) refreshes the screen
  automatically. No more "go in and refresh the month" to see your data.

- **Analysis-friendly export** (`lib/data/export.dart`): long format, one row
  per transaction, ISO dates, numeric amount with **no** `ر.س` in the cell,
  category id + name in separate columns, UTF-8 **with BOM** so Excel renders
  Arabic correctly.

Categories are user-editable (icon + color + type) and ship with a sensible
Arabic default set, so the app isn't empty on first launch and you're not stuck
with five icons.

---

## Run it

This skeleton has no platform folders yet (no `/ios`, `/android`). Generate them,
then build. `flutter create .` only adds missing scaffolding — it will **not**
overwrite anything in `lib/`.

```bash
# 1. Generate the iOS/Android/etc. platform folders in place.
flutter create .

# 2. Fetch dependencies.
flutter pub get

# 3. Generate the drift database code (creates lib/data/database.g.dart).
dart run build_runner build --delete-conflicting-outputs

# 4. Run the tests (pure date math — no device needed).
flutter test

# 5. Launch on a simulator/device.
flutter run
```

> **Heads up — not yet compiled.** This project was assembled in a sandbox
> without the Flutter SDK and without pub.dev access, so `flutter pub get`,
> `build_runner`, and `flutter test` have **not** been run against it here. The
> code is written to compile cleanly, but you may need to nudge a dependency
> version to match your installed Flutter/Dart. If `build_runner` complains,
> running `flutter pub upgrade` and regenerating usually resolves it. The
> `.g.dart` files are intentionally not included — step 3 creates them.

---

## Structure

```
lib/
  main.dart                     entry point; runs catch-up, then launches
  app.dart                      MaterialApp, Arabic RTL locale, light/dark theme
  data/
    enums.dart                  TxnType, Frequency
    tables.dart                 drift table definitions
    database.dart               AppDatabase + all DAOs + default categories
    export.dart                 analysis-friendly CSV export
  domain/
    recurrence_math.dart        pure, testable occurrence date math
    recurrence_engine.dart      the launch/resume catch-up
    date_grouping.dart          pure, testable اليوم/أمس/date grouping for lists
  ui/
    home_screen.dart            net-this-month hero card + day-grouped list
    add_transaction_sheet.dart  add a one-off transaction
    recurring_screen.dart       list/pause/reactivate recurrence rules
    add_recurrence_sheet.dart   create a recurrence rule
    savings_screen.dart         goals list with reactive per-goal progress
    goal_detail_screen.dart     contribution history + add-contribution for one goal
    add_goal_sheet.dart         create a savings goal
    add_contribution_sheet.dart add a contribution to a goal
    category_editor_screen.dart list/add/archive/unarchive categories
    add_category_sheet.dart     create a category (icon + color pickers)
    icon_registry.dart          iconKey -> IconData mapping
    theme/tokens.dart           design tokens + light/dark ColorScheme + CategoryTileColors
    widgets/                    CategoryIconTile, IconKeyPicker, ColorSwatchPicker
test/
  recurrence_math_test.dart     monthly/weekly/yearly clamps, bounds, idempotency
  date_grouping_test.dart       today/yesterday/date labels, grouping order
  widget_test.dart              home screen smoke test
```

---

## Left for next (deliberately not in v1)

- Editing/skipping a single recurrence occurrence (an exceptions table) —
  transactions already carry `recurrenceId` to make this possible.
- Backup to the **user's own** iCloud/Google Drive + import. (Running our own
  server was intentionally dropped: it makes us the custodian of everyone's
  financial data, which is a breach target and PDPL exposure for no real v1
  benefit. Local-first keeps the data in the user's custody.)
- Reminder notifications — decoupled by design: they only *remind*, they never
  create data, so a missed notification can't corrupt anything.
