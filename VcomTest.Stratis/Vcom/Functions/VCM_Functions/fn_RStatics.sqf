
/*
    Author: Genesis
    Modified: TDSA — added pair-matching logic using VCM_AssemblyPairList,
                     player exclusion, and VCM_InDeployment flag checks.

    Description:
        Scans all group units for static weapon backpacks, satchels, and mines.

        Backpack classification (TDSA addition):
            Bags found in VCM_AssemblyPairList as weapon bags (primary=1) go into
            _weaponCarriers. Bags found as support/tripod bags (primary=0) go into
            _supportCarriers. After the scan, weapon carriers are matched with
            available support carriers to form _pairedList entries.
            Pair-required bags with no available partner are excluded from _staticList —
            they wait until a partner is detected in a future Full_Check cycle.
            Bags not found in VCM_AssemblyPairList fall through to the original
            parent-class check for solo-deploy handling.

    Parameter(s):
        0: GROUP - Group to check for statics.

    Returns:
        ARRAY - [staticList, pairedList, satchelList, mineList]
            staticList  - solo-deploy units     : [[unit, backpackClass, isUAV], ...]
            pairedList  - matched assembly pairs: [[weaponUnit, supportUnit, vehicleClass,
                                                    weaponBagClass, supportBagClass], ...]
            satchelList - units with satchels   : [[unit, satchelArray], ...]
            mineList    - units with mines      : [[unit, mineObject], ...]

        NOTE: return format extended from the original [staticList, satchelList, mineList]
        to [staticList, pairedList, satchelList, mineList]. The FSM unpacks index 0
        (_StaticList) and index 1 (_PairList); indices 2-3 are currently unused by the FSM.
*/

private _staticList   = [];
private _pairedList   = [];
private _satchelList  = [];
private _mineList     = [];

// --- TDSA CHANGE: Intermediate staging arrays for pair matching.
// Populated during the scan loop; matched into _pairedList afterward.
//   _weaponCarriers  : [[unit, weaponBagClass, vehicleClass, requiredSupportBagClass], ...]
//   _supportCarriers : [[unit, supportBagClass], ...]
private _weaponCarriers  = [];
private _supportCarriers = [];
// --- END TDSA CHANGE ---

{
    // Process only on-foot units.
    // --- TDSA CHANGE: also skip players and units already mid-deployment.
    //     Players must never be involuntarily pulled into a static weapon sequence.
    //     VCM_InDeployment is set by fn_PairDeploy to prevent re-detection of a pair
    //     while their assembly thread is still running.
    if (isNull objectParent _x
        && !(isPlayer _x)
        && !(_x getVariable ["VCM_InDeployment", false])) then
    // --- END TDSA CHANGE ---
    {
        // ---------- Static weapon backpack classification ----------

        private _currentBackPack = backpack _x;

        if !(_currentBackPack isEqualTo "") then
        {
            // --- TDSA CHANGE: Check VCM_AssemblyPairList before falling through to original logic.
            //
            // Three outcomes:
            //   (a) Bag is a weapon bag in a known pair → _weaponCarriers
            //   (b) Bag is a support bag in a known pair → _supportCarriers
            //   (c) Bag is not in any pair → original parent-class check for solo deploy

            // Check if this bag is the weapon (primary) half of any entry
            private _weaponIdx = VCM_AssemblyPairList findIf {(_x select 0) isEqualTo _currentBackPack};

            // Check if this bag is the support (tripod) half of any entry
            private _supportIdx = VCM_AssemblyPairList findIf {(_x select 1) isEqualTo _currentBackPack};

            if (_weaponIdx > -1) then
            {
                // (a) Weapon bag — requires a partner before it can be deployed.
                //     Store the required support bag class so matching is O(1) later.
                private _entry = VCM_AssemblyPairList select _weaponIdx;
                // [unit, weaponBagClass, vehicleClass, requiredSupportBagClass]
                _weaponCarriers pushBack [_x, _currentBackPack, (_entry select 2), (_entry select 1)];
            }
            else if (_supportIdx > -1) then
            {
                // (b) Support/tripod bag — passive half of a pair.
                // [unit, supportBagClass]
                _supportCarriers pushBack [_x, _currentBackPack];
            }
            else
            {
                // (c) Not in VCM_AssemblyPairList — apply original parent-class logic.
                //     This covers solo-deploy bags (empty base[]) and any bag type not
                //     recognised by the pair system (e.g. from unlisted mods).
                // --- END TDSA CHANGE (else falls through to original logic below) ---

                private _class   = [_currentBackPack] call VCM_fnc_Classname;
                private _parents = [_class, true] call BIS_fnc_returnParents;

                if (!(isNil "_parents")) then
                {
                    if (("StaticWeapon" in _parents) || {"Weapon_Bag_Base" in _parents}) then
                    {
                        // UAV detection — unchanged from original
                        private _VCOM_HASUAV = false;
                        if (["UAV", _currentBackPack, false] call BIS_fnc_inString) then
                        {
                            _VCOM_HASUAV = true;
                        };
                        _staticList pushBack [_x, _currentBackPack, _VCOM_HASUAV];
                    };
                };

            // --- TDSA CHANGE: close the else block opened above ---
            };
            // --- END TDSA CHANGE ---
        };

        // ---------- Satchel and mine detection — unchanged from original ----------

        private _mineArray    = _x call VCM_fnc_HasMine;
        private _hasSatchel   = _mineArray select 0;
        private _mineObject   = _mineArray select 1;
        private _hasMine      = _mineArray select 2;
        private _satchelArray = _mineArray select 3;

        if (_hasMine)    then { _mineList    pushback [_x, (_mineObject select 0)]; };
        if (_hasSatchel) then { _satchelList pushback [_x, (_satchelArray select 0)]; };

        if (VCM_ARTYENABLE) then { _x call VCM_fnc_CheckArty; };
    };
} forEach (units _this);

// --- TDSA CHANGE: Pair matching pass.
// For each weapon carrier, find a support carrier holding the required partner bag.
// A support carrier that is matched is removed from consideration so it cannot be
// double-assigned. Unmatched weapon carriers are silently dropped — they will be
// re-detected on the next Full_Check cycle once a partner becomes available.
{
    _x params ["_weaponUnit", "_weaponBagClass", "_vehicleClass", "_requiredSupportBag"];

    // Find a support carrier whose bag class matches what this weapon bag requires
    private _matchIdx = _supportCarriers findIf {(_x select 1) isEqualTo _requiredSupportBag};

    if (_matchIdx > -1) then
    {
        private _supportEntry    = _supportCarriers select _matchIdx;
        private _supportUnit     = _supportEntry select 0;
        private _supportBagClass = _supportEntry select 1;

        // [weaponUnit, supportUnit, vehicleClass, weaponBagClass, supportBagClass]
        _pairedList pushBack [_weaponUnit, _supportUnit, _vehicleClass, _weaponBagClass, _supportBagClass];

        // Remove the matched support carrier so it cannot be used in a second pair
        _supportCarriers deleteAt _matchIdx;
    };
    // No match found: weapon carrier is not added to _staticList.
    // Pair-required bags without a partner simply wait for the next Full_Check.
} forEach _weaponCarriers;
// --- END TDSA CHANGE ---

[_staticList, _pairedList, _satchelList, _mineList]
