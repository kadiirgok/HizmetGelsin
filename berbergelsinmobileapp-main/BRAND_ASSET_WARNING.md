# Brand Asset & Logo Redesign Warning — HizmetGelsin V1

## Overview
This document logs the visual branding asset status following the product name standardization to **HizmetGelsin**.

---

## 1. Logo Asset Identification
- **Asset File Path:** `assets/logo.png`
- **Android Splash Logo:** `android/app/src/main/res/drawable-nodpi/splash_logo.png`
- **Usage Sites:**
  - `lib/features/auth/screens/splash_screen.dart`
  - `lib/features/auth/widgets/auth_widgets.dart` (`AuthBrandHeader`)

---

## 2. Graphic Asset Audit & Decision
- **Current Monogram Status:** The logo image asset (`assets/logo.png`) contains the legacy "B" monogram graphic design.
- **Action Taken:**
  - Standardized all user-facing text references, titles, and accessibility labels from `BerberGelsin` to `HizmetGelsin`.
  - Preserved existing raster asset `assets/logo.png` without arbitrary automatic mutation or deletion to prevent visual regressions.
- **Recommendation:** A dedicated design/branding task is required to produce a new "H" monogram or HizmetGelsin vector logo asset suite (`assets/logo.png` and native splash drawables).
