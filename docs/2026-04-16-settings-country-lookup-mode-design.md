# Settings: Country Selector, Lookup Mode, Results Improvements

**Date:** 2026-04-16
**Status:** Approved

## Summary

Add two settings to the iOS app: country selector (Spain/UK/Netherlands/Norway) and a toggle to skip API lookups (plate-only mode). Improve the Results tab with search and date grouping.

## Settings Screen

Two new rows in SettingsViewController, in a new "Scan Preferences" section above the existing "Storage" section.

### Country selector

- Tappable row showing current country name and flag emoji.
- Opens a `UIAlertController` action sheet with four options: Spain (default), UK, Netherlands, Norway.
- Persisted in `UserDefaults` as `selectedCountry` (String: "ES", "UK", "NL", "NO"). Default: "ES".
- Changing country takes effect immediately for the next OCR frame.
- Existing records from other countries remain in the list — the setting only affects which plates pass the OCR filter going forward.

### Lookup vehicle data toggle

- `UISwitch` row. Label: "Lookup vehicle data". Default: ON.
- Persisted in `UserDefaults` as `lookupEnabled` (Bool). Default: `true`.
- When ON: current behavior — calls API after plate detection, shows loading overlay.
- When OFF: skips API call entirely. Creates `PlateScanRecord` with `vehicleData: nil`, a sighting with location, and the captured camera frame photo. No loading overlay shown. Plate appears in Results instantly with just the plate number.

## ScanViewModel Changes

### Country-aware validation

- Reads `selectedCountry` from `UserDefaults` on each `processRecognizedText` call.
- Validates plates against only the selected country's patterns (replaces hardcoded `.spain`).
- `PlateValidator.cleanEUBandPrefix` already handles all countries generically (strip 1-4 leading chars, accept if remainder matches selected country). No changes needed.

### Plate-only mode

When `lookupEnabled` is `false` and a new plate passes validation:

1. Save the camera frame as photo (same as current behavior).
2. Create a `Sighting` with location and photo.
3. Create a `PlateScanRecord` with `plate`, `vehicleData: nil`, `sightings: [sighting]`.
4. Append to `scanRecords` and persist.
5. No `fetchAndStore()` call. No loading overlay. No `isFetching` flag set.

The existing "refresh" mechanism on the detail screen can be used later to fetch vehicle data for any plate-only record.

## Results Tab Changes

### Search bar

- `UISearchBar` at the top of the Results table.
- Filters records by plate number (case-insensitive substring match).
- Filters in real-time as the user types.
- Showing/hiding the keyboard does not disrupt the table.

### Date grouping

- Records are grouped by discovery date (date of first sighting, formatted as "15 Apr 2026").
- Section headers show the date string.
- Within each section, records are ordered by discovery time (newest first within the day).
- Sections themselves are ordered newest-first (today at the top).

### Plate-only records display

- Records without vehicle data show: plate number + country badge.
- Records with vehicle data show: plate number + country badge + make/model (current behavior).

## Files Changed

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `SettingsViewController.swift` | Add country picker row and lookup toggle row |
| Modify | `ScanViewModel.swift` | Read settings, country-aware validation, plate-only mode |
| Modify | `PlateValidatorService.swift` | Accept country parameter in `cleanEUBandPrefix` |
| Modify | `ResultsViewController.swift` | Search bar, date-grouped sections |
| Modify | `ResultsViewModel.swift` | Filtering and grouping logic |
