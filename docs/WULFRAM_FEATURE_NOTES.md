# Wulfram II → Tamaroyn feature notes (reverse engineered from shipped data/help)

> This project does **not** reuse the original game's code. These notes summarize observable gameplay and the shipped in-game help text so Tamaroyn can implement similar mechanics with original code and assets.

## Core loop
- Team-based multiplayer on large 3D terrain maps.
- Two main vehicle classes:
  - Tank (tougher, slower, more weapon slots, has jumpjets)
  - Scout/Medic (faster, lighter, has repair beam)
- Teams win by destroying enemy bases and players.

## Base building / logistics
- Cargo boxes can be picked up and dropped.
- Cargo boxes can contain deployables (example list):
  - Power Cell
  - Fuel Pad
  - Repair Pad
  - Sentry Cannons
  - Gun Turret
  - Missile Launchers
  - Darklight (radar / minimap coverage)
  - Skypump (allows friendly starship movement between sectors)
  - Uplink (lets players control their team's starship)

## Strategic layer
- Strategy map shows terrain with overlays: visual map, altitude, slope, radar.
- The map is divided into “sectors” (squares) used for starship movement.
- Starships orbit above sectors.
  - They can drop cargo or perform orbital bombardment.
  - With enough skypumps, ships can move sector-to-sector.
  - With two skypumps, teams can warp in additional ships (up to three total).

## Weapons (high-level)
- Autocannon (primary)
- Pulse shell (tank)
- Repair beam (scout)
- Piercer
- Thumper
- Hunter
- Caltrop
- Mine
- Flare
- Maser

## Movement
- Hover vehicle movement, with player-adjustable altitude.
- Tank has jumpjets (temporary thrust).
