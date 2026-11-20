# AirlinesSim

Mobile-first airline management simulator built with **Godot 4** and GDScript.

## Current milestone — Foundation / Stage 1

Included:
- Android portrait project configuration.
- Company creation (name, airline code, country, home airport).
- Local aircraft catalogue with Airbus, Boeing, Embraer, ATR, Bombardier, COMAC and Sukhoi models.
- Local airport dataset with IATA codes, coordinates, runway counts and city metadata.
- Aircraft purchase and fleet records.
- Route creation with aircraft range and home-location checks.
- Time simulation (pause, 1x, 2x, 4x, 8x).
- Basic flight completion, passenger demand estimation, fuel, airport-fee and maintenance cost model.
- Financial ledger.
- Autosave, two manual slots, JSON import/export.
- Portrait-oriented mobile UI.

## Run

1. Install Godot 4.3 or newer.
2. Import this repository's `project.godot`.
3. Press F6/F5 or export an Android APK using the Android export templates and SDK configured in Godot.

## Important data notes

Aircraft prices and operating figures are **balancing estimates**, not manufacturer quotations or certified operational performance. Aircraft performance varies by airline configuration, payload, engine option and operating conditions. Airport passenger-population figures are demand-model inputs, not official airport throughput statistics. Expand and validate the datasets before presenting the simulation as a source of real-world aviation data.

## Roadmap

1. Foundation: company, airport and aircraft data, persistence.
2. Operations: schedule generation, airport turnaround, taxi/takeoff/landing state machine, flight tracking and weather.
3. Economy: cabin classes, cargo, staffing, leases, debt, insurance, maintenance checks and market competition.
4. Growth: contracts, research, reputation, events and achievements.
5. Art/audio/polish: bespoke high-resolution pixel-art aircraft silhouettes, airport scenes, animation, sound and mobile performance profiling.

The current repository is an early playable foundation, not the complete game described in the product brief.
