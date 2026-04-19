# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TDSA-VcomAI-3.0 is an Arma 3 AI overhaul script/mod based on Vcom AI v4.3.0 with TDSA customizations. It replaces vanilla AI behavior with group-level FSM-driven tactics: flanking, building clearing, artillery calls, mine planting, suppression, cover detection, and vehicle combat. The mod operates at the **group** level rather than the individual unit level for both correctness and performance.

CBA_A3 is optional (enables in-game settings UI). ACE Medical and Enhanced Movement are also optionally supported.

## Installation / Deployment

There is no build step. Drop the `vcom/` folder into a mission's root directory and add to `description.ext`:

```cpp
#include "vcom\cfgFunctions.hpp"
```

Alternatively, package as a PBO addon. Test via the included `VcomTest.Stratis/` mission.

## Configuration

Three methods (pick one):

1. **Userconfig file**: `\userconfig\VCOM_AI\AISettingsV3.4.1.hpp`
2. **Direct edit**: `VcomTest.Stratis/vcom/Functions/VcomAI_DefaultSettings.sqf` — 160+ settings including AI skill levels per difficulty, side-specific overrides, and feature toggles (artillery, mines, grenades, smoke, formations)
3. **CBA Settings**: In-game panel when CBA_A3 is loaded (configured in `fn_CBASettings.sqf`)

## Architecture

### Initialization Chain

```
fn_VcomInit (preInit)
  └─ fn_AfterInit (postInit)
       ├─ fn_WeaponDefine     (weapon data tables)
       ├─ fn_Scheduler        (main polling loop — spawned)
       ├─ fn_AIDRIVEBEHAVIOR  (vehicle FSM)
       ├─ fn_IRCHECK          (player IR laser detection)
       ├─ fn_MineMonitor      (onEachFrame mine handler)
       └─ Event handlers: player Fired, Respawn, Hit
```

### Main Loop

`fn_Scheduler` runs every 10 seconds, scans `allGroups`, and for any AI group not already active spawns `fn_SQUADBEH.fsm` — the core squad behavior FSM — and adds the group to `VcmAI_ActiveList`.

### Core FSM (`fn_SQUADBEH.fsm`)

```
Start_Point → Leadership Cycle
  ├─ Hold/Garrison
  ├─ Infantry Combat Brain
  │   ├─ fn_FlankMove, fn_ClearBuilding, fn_ForceMove
  │   ├─ fn_ForceGrenadeFire, fn_ArtyCall
  │   └─ mine/satchel planting, static weapon checks
  ├─ Vehicle Combat Brain
  │   └─ transport and attack orders
  └─ Periodic checks (rearm, medical, formation changes)
→ Exit FSM (cleanup, remove from ActiveList)
```

### Function Categories

All functions are in `VcomTest.Stratis/vcom/Functions/VCM_Functions/` and registered in `cfgFunctions.hpp` under the `VCM` tag, called as `[...] call VCM_fnc_functionName`.

- **Detection**: `fn_EnemyArray`, `fn_FriendlyArray`, `fn_ClstEmy`, `fn_KnowAbout`
- **Movement**: `fn_ForceMove`, `fn_FlankMove`, `fn_FindCover`, `fn_CoverDetect`
- **Combat**: `fn_RangeEngage`, `fn_SniperEngage`, `fn_ForceGrenadeFire`, `fn_AISuppressed`
- **Vehicles**: `fn_VehicleMove`, `fn_VehicleCheck`, `fn_TransportVehicle`, `fn_vehiclecommandeer`
- **Support**: `fn_MedicHeal`, `fn_RearmSelf`, `fn_ArtyCall`, `fn_Garrison`
- **Tactical**: `fn_ClearBuilding`, `fn_MinePlant`, `fn_SatchelPlant`, `fn_FrmChnge`
- **Misc**: `fn_IdleAnimations`, `fn_IRCHECK`, `fn_HearingAids`, `fn_MineMonitor`
