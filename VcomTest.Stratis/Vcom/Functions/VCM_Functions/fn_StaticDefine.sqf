/*
    Author: TDSA

    Description:
        Scans all loaded CfgVehicles once at mission start to build
        VCM_AssemblyPairList — a global lookup table that maps each weapon bag
        class to its required support/tripod bag class and the resulting assembled
        vehicle class.

        Runs once via fn_AfterInit (called after fn_WeaponDefine).
        Works automatically for any loaded mods (vanilla, RHS, CUP, etc.)
        without manual maintenance.

        How Arma 3 assembly config works:
            Each deployable backpack has an "assembleInfo" sub-class in CfgVehicles.
            "primary = 1" marks the weapon bag (the initiating half).
            "primary = 0" marks the support/tripod bag (the passive half).
            "assembleTo"  is the vehicle class created when the pair is assembled.
            "base[]"      lists the required partner bag class(es).
            Bags with an empty base[] are solo-deploy and are NOT stored here —
            they continue to be handled by the existing fn_StaticCheck path.

        VCM_AssemblyPairList format:
            [ [weaponBagClass, supportBagClass, assembledVehicleClass], ... ]

    Parameter(s):
        none

    Returns:
        nothing
*/

// Reset global in case this runs more than once
VCM_AssemblyPairList = [];

private _allVehicleClasses = (configfile >> "CfgVehicles") call BIS_fnc_getCfgSubClasses;

{
    private _className    = _x;
    private _assembleInfo = configfile >> "CfgVehicles" >> _className >> "assembleInfo";

    // Only process classes that define an assembleInfo sub-class
    if (isClass _assembleInfo) then
    {
        // primary = 1 identifies the weapon bag (the one that initiates the assembly action).
        // Support/tripod bags (primary = 0) are found indirectly through the weapon bag's base[].
        private _primary = getNumber (_assembleInfo >> "primary");

        if (_primary isEqualTo 1) then
        {
            private _assembleTo = getText (_assembleInfo >> "assembleTo");
            private _base       = getArray (_assembleInfo >> "base");

            // Only store entries where:
            //   (a) a valid target vehicle class exists
            //   (b) a partner bag is required (base[] is non-empty)
            // Solo-deploy bags (empty base[]) remain in the existing fn_StaticCheck path.
            if (!(_assembleTo isEqualTo "") && {count _base > 0}) then
            {
                // [weaponBagClass, supportBagClass, assembledVehicleClass]
                VCM_AssemblyPairList pushBack [_className, (_base select 0), _assembleTo];
            };
        };
    };
} forEach _allVehicleClasses;
