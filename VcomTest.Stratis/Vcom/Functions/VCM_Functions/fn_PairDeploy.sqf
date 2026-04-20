/*
    Author: TDSA

    Description:
        Processes matched static weapon assembly pairs produced by fn_RStatics.
        Called with `call` from fn_SQUADBEH.fsm — accesses FSM-scope variables
        (_leader, _Group) directly. Returns immediately so the FSM thread is not
        blocked; all waiting and animation happens in spawned threads.

        Each pair entry is either:
          (a) invalid  → removed (both dead, or a unit no longer has its backpack)
          (b) out-of-range → kept in the list for the next Full_Check cycle
          (c) dispatched → VCM_InDeployment set on both units, async thread spawned, removed

        Dead-unit handling:
          If one unit has died since the pair was formed, the surviving unit walks to
          the dead body's position and deletes the dropped backpack object so the
          assembled vehicle can be created there cleanly.

    Parameter(s):
        0: ARRAY - _PairList from fn_RStatics:
                   [[weaponUnit, supportUnit, vehicleClass, weaponBagClass, supportBagClass], ...]

    Returns:
        ARRAY - _PairList with invalid/dispatched entries removed
*/

params ["_PairList"];

// Collect indices to remove in a second pass (safe with deleteAt if done descending)
private _toRemove = [];

{
    _x params ["_weaponUnit", "_supportUnit", "_vehicleClass", "_weaponBagClass", "_supportBagClass"];

    private _weaponAlive  = alive _weaponUnit;
    private _supportAlive = alive _supportUnit;

    // --- Validity check 1: both units dead — pair is unrecoverable ---
    if (!_weaponAlive && !_supportAlive) then
    {
        _toRemove pushBack _foreachindex;
    }
    else
    {
        // --- Validity check 2: living unit(s) must still hold expected backpack ---
        // A player, script, or earlier deploy could have swapped/removed the bag.
        private _valid = true;
        if (_weaponAlive  && !(backpack _weaponUnit  isEqualTo _weaponBagClass))  then { _valid = false; };
        if (_supportAlive && !(backpack _supportUnit isEqualTo _supportBagClass)) then { _valid = false; };

        if (!_valid) then
        {
            _toRemove pushBack _foreachindex;
        }
        else
        {
            // --- Range gate: enemy must be 150–800 m from the group leader ---
            // Outside that window the pair waits; re-evaluated on the next Full_Check.
            private _nearestEnemy = _leader findNearestEnemy _leader;
            if (isNull _nearestEnemy) then { _nearestEnemy = _leader call VCM_fnc_ClstEmy; };

            if (!(isNull _nearestEnemy)) then
            {
                private _dist = _leader distance _nearestEnemy;
                if (_dist >= 150 && {_dist <= 800}) then
                {
                    // Mark both units so fn_RStatics won't re-detect them mid-deployment
                    _weaponUnit  setVariable ["VCM_InDeployment", true, false];
                    _supportUnit setVariable ["VCM_InDeployment", true, false];

                    _toRemove pushBack _foreachindex;

                    // DEBUG
                    private _dbgMsg = format ["[VCOM DEBUG] PairDeploy: dispatching pair — weapon: %1 (%2), support: %3 (%4), vehicle: %5, enemy dist: %6m",
                        name _weaponUnit, _weaponBagClass,
                        name _supportUnit, _supportBagClass,
                        _vehicleClass, round _dist];
                    diag_log _dbgMsg;
                    //systemChat _dbgMsg;
                    // END DEBUG

                    // --- Async assembly thread — FSM call returns immediately after this ---
                    [_weaponUnit, _supportUnit, _vehicleClass, _weaponBagClass, _supportBagClass, _nearestEnemy] spawn
                    {
                        params ["_weaponUnit", "_supportUnit", "_vehicleClass",
                                "_weaponBagClass", "_supportBagClass", "_nearestEnemy"];

                        private _weaponAlive  = alive _weaponUnit;
                        private _supportAlive = alive _supportUnit;

                        // Determine which unit walks to which.
                        //   Both alive  : support unit moves to weapon unit's position.
                        //   Weapon dead : support unit walks to the dead body.
                        //   Support dead: weapon unit walks to the dead body.
                        private _mover    = objNull;
                        private _target   = objNull;
                        private _deadUnit = objNull;
                        private _deadBag  = "";

                        if (_weaponAlive && _supportAlive) then
                        {
                            _mover  = _supportUnit;
                            _target = _weaponUnit;
                        }
                        else if (_weaponAlive) then
                        {
                            _mover    = _weaponUnit;
                            _target   = _supportUnit;   // body used as destination
                            _deadUnit = _supportUnit;
                            _deadBag  = _supportBagClass;
                        }
                        else
                        {
                            _mover    = _supportUnit;
                            _target   = _weaponUnit;
                            _deadUnit = _weaponUnit;
                            _deadBag  = _weaponBagClass;
                        };

                        // Begin movement toward the target / body
                        _mover doMove (getPos _target);

                        // Wait up to 30 s for proximity (5 m) with 1-second resolution
                        private _elapsed = 0;
                        private _arrived = false;
                        while {_elapsed < 30 && {!_arrived}} do
                        {
                            sleep 1;
                            _elapsed = _elapsed + 1;
                            if (_mover distance2D _target < 5) then { _arrived = true; };
                        };

                        if (!_arrived) then
                        {
                            // Timeout — release flags so the pair can be retried next cycle
                            // DEBUG
                            private _dbgTimeout = format ["[VCOM DEBUG] PairDeploy: TIMEOUT — %1 did not reach %2 in 30s, resetting flags", name _mover, name _target];
                            diag_log _dbgTimeout;
                            //systemChat _dbgTimeout;
                            // END DEBUG
                            _weaponUnit  setVariable ["VCM_InDeployment", false, false];
                            _supportUnit setVariable ["VCM_InDeployment", false, false];
                        }
                        else
                        {
                            // Arrived — stop both units
                            // DEBUG
                            private _dbgArrive = format ["[VCOM DEBUG] PairDeploy: %1 arrived — assembling %2", name _mover, _vehicleClass];
                            diag_log _dbgArrive;
                            //systemChat _dbgArrive;
                            // END DEBUG
                            _mover doStop true;
                            if (alive _target) then { _target doStop true; };

                            // Remove the dropped backpack object from the dead unit's body
                            // so it doesn't conflict with the spawned vehicle
                            if (!(isNull _deadUnit)) then
                            {
                                private _droppedBag = nearestObject [getPos _deadUnit, _deadBag];
                                if (!(isNull _droppedBag)) then { deleteVehicle _droppedBag; };
                            };

                            // Assembly animation on each alive unit
                            [_mover, "AinvPknlMstpSnonWnonDnon_Putdown_AmovPknlMstpSnonWnonDnon"] remoteExec ["Vcm_PMN", 0];
                            if (alive _target) then
                            {
                                [_target, "AinvPknlMstpSnonWnonDnon_Putdown_AmovPknlMstpSnonWnonDnon"] remoteExec ["Vcm_PMN", 0];
                            };
                            sleep 3.5;

                            // Create the assembled static weapon at the assembly position
                            private _assemblyPos = getPos _mover;
                            private _staticCreated = _vehicleClass createVehicle _assemblyPos;
                            _staticCreated allowDamage false;
                            _staticCreated setVelocity [0, 0, 0];
                            _staticCreated setPos _assemblyPos;
                            _staticCreated allowDamage true;

                            // Orient toward nearest enemy (snapshot taken at dispatch time)
                            _staticCreated setDir (_staticCreated getDir _nearestEnemy);

                            // Strip backpacks from alive units
                            if (alive _weaponUnit)  then { removeBackpackGlobal _weaponUnit; };
                            if (alive _supportUnit) then { removeBackpackGlobal _supportUnit; };

                            // Weapon carrier is the preferred gunner; fall back to support unit
                            private _gunner    = if (alive _weaponUnit)  then { _weaponUnit  } else { _supportUnit };
                            private _gunnerBag = if (alive _weaponUnit)  then { _weaponBagClass } else { _supportBagClass };
                            _gunner assignAsGunner _staticCreated;
                            [_gunner] orderGetIn true;
                            _gunner moveInGunner _staticCreated;

                            // Clear deployment flags — units are committed to the gun
                            _weaponUnit  setVariable ["VCM_InDeployment", false, false];
                            _supportUnit setVariable ["VCM_InDeployment", false, false];

                            // Determine the support unit that needs its backpack restored on teardown.
                            // If the support unit is dead, or IS the gunner (weapon unit died), pass objNull.
                            private _packSupportUnit = objNull;
                            private _packSupportBag  = "";
                            if (alive _supportUnit && _gunner != _supportUnit) then
                            {
                                _packSupportUnit = _supportUnit;
                                _packSupportBag  = _supportBagClass;
                            };

                            // Hand off to PackStatic for the 180-second countdown and teardown
                            [_gunner, _gunnerBag, _staticCreated, _packSupportUnit, _packSupportBag] spawn VCM_fnc_PackStatic;
                        };
                    };
                };
            };
        };
    };
} forEach _PairList;

// Remove dispatched/invalid entries; sort descending so each deleteAt doesn't shift remaining indices
_toRemove sort false;
{
    _PairList deleteAt _x;
} forEach _toRemove;

_PairList
