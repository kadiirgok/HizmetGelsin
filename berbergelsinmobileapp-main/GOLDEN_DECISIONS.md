# Golden Image Decisions Log — Flutter Test Stabilization V1

## Overview
This document records all baseline decisions and rationale for updated Golden test evidence files during the stabilization phase.

---

## 1. Golden Test Infrastructure Changes
- **Font Binding:** Replaced legacy hardcoded `.flutter-sdk-fast` relative file path lookups with a dynamic multi-candidate font locator (`loadTestFonts()` in `test/support/visual_test_helper.dart`). `Roboto-Regular.ttf` is now bound to both `'Roboto'` and `'Ahem'` font families. `MaterialIcons-Regular.otf` is bound to `'MaterialIcons'`.
- **Button Typography:** `getVisualTestTheme()` applies `fontFamily: 'Roboto'` across `textTheme`, `filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`, and `elevatedButtonTheme`.
- **Viewport & DevicePixelRatio:** Enforced deterministic `Size(390, 844)` logical viewport and `devicePixelRatio = 1.0`.
- **Animation Stability:** Replaced blocking `pumpAndSettle()` timeouts on repeating skeleton animations with fixed 300ms frame pumps.

---

## 2. Updated Golden Images Audit

### Task 126 — Profile Screens (`test/features/auth/task126_profile_visual_evidence_test.dart`)
- **Golden Files:** `task126/profile-home.png`, `task126/profile-loading.png`, `task126/profile-edit.png`, `task126/profile-account-summary.png`, `task126/profile-security.png`, `task126/profile-logout.png`, `task126/profile-delete-account.png`, `task126/profile-error.png`.
- **Previous Issue:** Buttons rendered square block Ahem fonts and missing icons when executed outside `.flutter-sdk-fast` directory context.
- **Why New Image is Correct:** Clear, legible Roboto text and crisp Material icons at 390x844 resolution.
- **Production UI Changed:** No. Only test harness font and button theme bindings updated.
- **Resolution:** 390x844 logical pixels.

### Task 129 — Secondary Customer Screens (`test/features/customer_secondary/task129_visual_evidence_test.dart`)
- **Golden Files:** `task129/addresses.png`, `task129/addresses-empty.png`, `task129/favorites.png`, `task129/favorites-empty.png`, `task129/ratings.png`, `task129/ratings-empty.png`, `task129/notifications.png`, `task129/notifications-empty.png`.
- **Previous Issue:** Missing `setUpAll` font loader caused all texts and icons to render as solid black Ahem rectangular boxes.
- **Why New Image is Correct:** Fully rendered typography and icons for addresses, favorites, ratings, and notification badges.
- **Production UI Changed:** No. Test harness now correctly loads test fonts and theme.
- **Resolution:** 390x844 logical pixels.

### Task 124 — Map Discovery Home (`test/features/map/task124_visual_evidence_test.dart`)
- **Golden Files:** `task124/home.png`, `task124/home-loading.png`, `task124/categories.png`, `task124/search-results.png`, `task124/address-search.png`, `task124/address-selector.png`, `task124/upcoming-appointment.png`, `task124/nearby-businesses.png`.
- **Previous Issue:** Relied on fragile path lookup for `.flutter-sdk-fast`; missing button theme typography binding.
- **Why New Image is Correct:** Clean rendering of map category pills, cards, address modals, and search chips.
- **Production UI Changed:** No.
- **Resolution:** 390x844 logical pixels.

### Task 125 — Map & List Discovery View (`test/features/map/task125_visual_evidence_test.dart`)
- **Golden Files:** `task125/map-default.png`, `task125/map-selected-business.png`, `task125/map-clusters.png`, `task125/map-filters.png`, `task125/map-search-area.png`, `task125/map-no-location.png`, `task125/map-error.png`, `task125/list-map-sync.png`.
- **Previous Issue:** Golden matcher appended duplicate `.png` extension (`map-default.png.png`); missing font loader bindings in test suite context.
- **Why New Image is Correct:** Single `.png` filenames matching standard baseline path; full font and icon rendering across map overlays and sheet controls.
- **Production UI Changed:** No.
- **Resolution:** 390x844 logical pixels.

### Task 130 — Business Detail Screen (`test/features/map/task130_business_detail_visual_evidence_test.dart`)
- **Golden File:** `task130/business-detail-final.png`.
- **Previous Issue:** Rigid SDK path dependency caused missing font textures on non-standard SDK locations.
- **Why New Image is Correct:** Fully legible barber details, rating badges, service list, and action buttons.
- **Production UI Changed:** No.
- **Resolution:** 390x844 logical pixels.

### Task 127 — Appointments & Flow (`test/features/requests/task127_appointments_visual_evidence_test.dart`)
- **Golden Files:** `task127/appointments-active.png`, `task127/appointments-upcoming.png`, `task127/appointments-history.png`, `task127/appointments-cancelled.png`, `task127/request-detail.png`, `task127/request-timeline.png`, `task127/cancel-flow.png`, `task127/reschedule-flow.png`.
- **Previous Issue:** Missing Roboto/Ahem font loader fallback and button text theme overrides.
- **Why New Image is Correct:** Clear layout for tabs, timeline status nodes, cancel reason picker, and reschedule date time pickers.
- **Production UI Changed:** No.
- **Resolution:** 390x844 logical pixels.
