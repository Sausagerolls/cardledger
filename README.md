# CardLedger

Inventory + pricing app for trading-card traders. Log cards with photos and a purchase
price; instantly see the sale price for any profit target with tax factored in. Built for
Dragon Ball Fusion World first, but multi-system from day one. Native iOS/iPadOS with
iCloud backup, and a built-in local web server so you can browse and edit your inventory
from any computer's browser on the same Wi-Fi.

## Status

- ✅ Native app (iOS 17+, iPhone + iPad): inventory, add/edit cards with photos,
  per-instance unique codes + QR, live pricing calculator, settings, onboarding.
- ✅ In-app QR scanning, deep links, QR-sheet printing (A4, 12/page), CSV export.
- ✅ Desktop access: on-device web server (Bonjour) — view/add/edit from a browser on
  the same network, with CSV + QR-sheet download.
- ✅ iCloud sync/backup (toggle in Settings).

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate          # regenerate CardLedger.xcodeproj from project.yml
open CardLedger.xcodeproj   # then ⌘R, or:

xcodebuild -project CardLedger.xcodeproj -scheme CardLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The Xcode project is generated — **edit `project.yml` and Swift sources, not the
`.xcodeproj`** (it's disposable; rerun `xcodegen generate`).

### Debug launch arguments
- `-seedSample` — insert demo Dragon Ball cards.
- `-openFirstCard` — open straight into a card's detail (for screenshots).

## Enabling iCloud backup (one-time)

`PersistenceController` already *prefers* a CloudKit-mirrored store and silently falls
back to a local store when the entitlement isn't present (e.g. the Simulator). To turn on
real backup of cards **and photos** to the user's private iCloud:

1. Open the project in Xcode, select the **CardLedger** target → **Signing & Capabilities**.
2. Pick your **Team** (paid Apple Developer account).
3. **+ Capability → iCloud** → tick **CloudKit** → container `iCloud.com.cardledger.app`.
4. **+ Capability → Background Modes** → tick **Remote notifications**.

That's it — no code change. See `CardLedger/Support/CardLedger.entitlements` for reference.

## How pricing works

Pure math lives in `Pricing/PricingEngine.swift`. Rates come from **Settings**:

- **Flat VAT on full price** (default): `sale = cost × (1 + profit) × (1 + VAT)`
- **VAT margin scheme** (toggle): VAT charged only on the profit margin.

Example: cost £45, 10% profit, 20% VAT → list at **£59.40**.

## Short codes & QR

Each card gets a Crockford-base32 code like `DBF-7K3Q` (game prefix + unambiguous suffix).
The QR encodes `cardledger://card/<shortCode>`. Scanning in-app (Scan tab) or with the
system Camera opens the matching card. Find-by-code also works by typing the code.

## Architecture

```
CardLedger/
  App/            App entry, root tab navigation, deep links
  Models/         SwiftData models (Card, CardPhoto, GameSystem, CardCondition) — CloudKit-ready
  Persistence/    ModelContainer (CloudKit → local fallback), seeding
  Pricing/        PricingEngine (pure), TaxMethod
  ShortCode/      Unique short-code generator
  Services/       QR generation, pluggable card-database providers (Dragon Ball)
  Design/         Theme tokens + reusable components
  Features/       Inventory, AddCard, CardDetail, Search/Scan, Settings
  Support/        Info.plist (generated), entitlements
```

Card metadata auto-fill is pluggable: conform to `CardDatabaseProvider` and register it to
support another game. Sources (no key unless noted): Dragon Ball Fusion World (static
GitHub dataset), Magic (Scryfall), Yu-Gi-Oh! (YGOPRODeck), Pokémon (pokemontcg.io,
optional key). Manual entry always works.

## Desktop access

The **Desktop** tab starts a small on-device web server (Network framework + Bonjour) that
serves the inventory to any browser on the same Wi-Fi at `http://<ip>:8080` /
`cardledger.local:8080`. The browser can **view, add, edit and delete** cards, filter by
game/sold, and download a CSV or the QR print sheet. It runs only while the app is
foreground (iOS suspends background apps), on the local network.

## Source availability & licence

This repository is **source-available**: published so you can read exactly how
CardLedger works and handles your data. **All rights reserved — no licence is granted.**
You may view the code, but may not copy, modify, redistribute, or reuse it (in whole or
in part) in other projects without prior written permission from Giant Mushroom Studio.

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is not committed — run `xcodegen generate` after cloning.

© 2026 Giant Mushroom Studio. CardLedger and the Giant Mushroom Studio name are trademarks
of their owner. Card names, artwork and trademarks shown via auto-fill belong to their
respective owners.
