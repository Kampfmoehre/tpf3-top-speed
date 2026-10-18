# Changelog

## 0.5.1 (2026-10-18)

- Fix: expanding the card crashed the game ("Item of Component must be a layout", from the tooltip on the
  "Track" column header).

## 0.5.0 (2026-10-18)

- The card can be expanded to a table with one row per section of the line: steepest climb,
  highest speed measured on that section as a bar, and the track limit. In the vehicle window the
  section the vehicle is driving is highlighted.
- Colours: green only when the vehicle reached its own top speed; when a track limit below that
  holds it back, the track limit is highlighted (an upgrade would help); yellow below 50 %. The
  collapsed row follows the same rule.
- The shared track collector also reads track heights and catenary (used by Line Rate Preview
  0.17.0).

## 0.4.1 (2026-10-16)

- Opening a window re-reads its line's track, so a track upgrade shows within seconds instead of up
  to 5 minutes.

## 0.4.0 (2026-10-16)

- Shows the line's highest track speed limit next to the reached speed ("· track 100 km/h", mod
  parameter, on by default); lines without vehicles show "no vehicles".

## 0.3.3 (2026-10-09)

- Fix: the measured speed is now really reset when a vehicle's consist is replaced or modified.

## 0.3.2 (2026-10-07)

- Reset the measured speed when a vehicle was replaced.

## 0.3.1 (2026-10-06)

- First release: highest measured speed per vehicle and per line in the vehicle and line windows.
