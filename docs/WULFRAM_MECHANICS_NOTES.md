# Reverse-engineering Notes (Wulfram II → Tamaroyn)

These notes are distilled from the in-game help text packaged with the Wulfram II client and are used as a **mechanics/spec reference** for Tamaroyn.

## Core loop
- Two teams fight over a large 3D battlefield.
- Players drive hovertanks (at least two classes: heavier Tank, lighter Scout/Medic).
- Victory comes from annihilating enemy players and destroying enemy bases.

## Base building via cargo
- Structures are built by **picking up cargo boxes** and then **dropping/installing** their contents.
- Cargo is ordered via starship support and dropped onto the battlefield.
- Cargo can also appear in the open or be dropped by other means depending on server/map.

## Common structures
- Power Cell / Power Unit: provides base power.
- Fuel Pad: refuel hovertanks.
- Repair Pad: repairs hovertanks.
- Sentry Cannon: light automated defense.
- Gun Turret: heavier defense.
- Missile Launcher: guided projectile defense.
- Darklight: anti-scout detection/illumination.
- Skypump: enables starship travel between adjacent map sectors.
- Uplink: allows players to command their team’s starships.

## Starships and strategic layer
- The world is divided into **square sectors** shown in a strategy map.
- Each team has starships orbiting in sectors; ships can be commanded to:
  - Drop cargo
  - Perform orbital bombardment
  - Move between sectors (requires Skypumps for travel)
  - Warp-in additional starships (requires multiple Skypumps; game limits total ships)

## Navigation and map modes
- Fullscreen map provides multiple modes:
  - Visual map
  - “Altitude” map (height visualization)
  - “Slope” map (terrain steepness)
- Map supports zoom and cursor readouts.

## Targeting (original behavior)
- Mouse-based aiming.
- Targeting mode can cycle visible targets.
- A target lock influences missile weapons and some UI.

## Weapons (as named in Wulfram help)
- Autocannon (primary)
- Pulse Shell / Pulse Cannon
- Repair Beam (Scout)
- Piercer (missile)
- Thumper (artillery)
- Hunter (missile)
- Caltrop (area denial)
- Mine
- Flare (countermeasure)
- Maser

## Vehicle notes
- Tank:
  - Slower, tougher, more weapon slots
  - Jumpjets are available
- Scout/Medic:
  - Faster, lighter
  - Has Repair Beam

## Tamaroyn mapping (draft)
- Crimson Federation → **Ember Accord** (example)
- Azure Alliance → **Cobalt Synod** (example)
- Skypump → **Skywell**
- Uplink → **Orbital Relay**
- Cargo → **Drop Crate**

