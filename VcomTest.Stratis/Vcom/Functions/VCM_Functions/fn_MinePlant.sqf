/*
	Author: Genesis

	Description:
		Plants a mine

	Parameter(s):
		0: OBJECT - Unit to plant a mine
		1: ARRAY - ???

	Returns:
		NOTHING
*/

{

if (VCM_MINECHANCE > (round (random 100)) || {!(isPlayer _x)}) then
{

	private _Unit = _x;
	private _nearestEnemy = _unit call VCM_fnc_ClstEmy;
	if (_nearestEnemy isEqualTo [] || {isNil "_nearestEnemy"}) exitWith {};

	private _mine = "";

	private _magsAmmo = magazinesAmmo _Unit;
	{
		private _mag = _x select 0;
		private _Index = (VCM_MineList findif {_mag isEqualTo _x#1});
		if (_Index > -1) exitWith
		{
			private _Mine = VCM_MineList#_Index;
			private _roadPreferred = _Mine#4;

			// DEBUG
			private _dbgMsg = format ["[VCOM DEBUG] MinePlant: %1 planting %2 (mag: %3, road: %4)", name _Unit, (_Mine#2), (_Mine#1), (_Mine#4)];
			diag_log _dbgMsg;
			systemChat _dbgMsg;
			// END DEBUG

			_Unit fire [(_Mine#3),(_Mine#3),(_Mine#1)];

			if (_nearestEnemy distance2D _unit < 100) then
			{
				// Enemy within 100m - panic/defensive plant, mine stays where it fell
				[_Unit,(_Mine#2)] spawn
				{
					params ["_Unit","_Mine"];
					private _Pos = getpos _Unit;
					sleep 3;
					private _NrstMine = nearestObjects [_Pos,[],1];
					{
						if (_Mine isEqualTo (typeof _x)) then
						{
							_unitSide = (side _unit);
							VCOM_mineArray pushBack [_x,_unitSide];
						};
					} foreach _NrstMine;
				};
			}
			else if (_roadPreferred) then
			{
				// AT or SLAM mine - attempt road placement
				private _nearRoads = _unit nearRoads 50;
				[_unit,"AinvPknlMstpSnonWnonDnon_Putdown_AmovPknlMstpSnonWnonDnon"] remoteExec ["Vcm_PMN",0];
				if (count _nearRoads > 0) then
				{
					private _closestRoad = [_nearRoads,_unit,true] call VCM_fnc_ClstObj;
					[_Unit,(_Mine#2),_closestRoad] spawn
					{
						params ["_Unit","_Mine","_closestRoad"];
						private _Pos = getpos _Unit;
						sleep 3;
						private _NrstMine = nearestObjects [_Pos,[],1];
						{
							if (_Mine isEqualTo (typeof _x)) then
							{
								_x setposATL (getposATL _closestRoad);
								_unitSide = (side _unit);
								VCOM_mineArray pushBack [_x,_unitSide];
							};
						} foreach _NrstMine;
					};
				}
				else
				{
					// No road nearby - mine stays where it fell
					[_Unit,(_Mine#2)] spawn
					{
						params ["_Unit","_Mine"];
						private _Pos = getpos _Unit;
						sleep 3;
						private _NrstMine = nearestObjects [_Pos,[],1];
						{
							if (_Mine isEqualTo (typeof _x)) then
							{
								_unitSide = (side _unit);
								VCOM_mineArray pushBack [_x,_unitSide];
							};
						} foreach _NrstMine;
					};
				};
			}
			else
			{
				// AP mine (APERS, claymore, tripwire, bounding) - field placement
				[_unit,"AinvPknlMstpSnonWnonDnon_Putdown_AmovPknlMstpSnonWnonDnon"] remoteExec ["Vcm_PMN",0];
				[_Unit,(_Mine#2)] spawn
				{
					params ["_Unit","_Mine"];
					private _Pos = getpos _Unit;
					sleep 3;
					private _NrstMine = nearestObjects [_Pos,[],1];
					{
						if (_Mine isEqualTo (typeof _x)) then
						{
							_unitSide = (side _unit);
							VCOM_mineArray pushBack [_x,_unitSide];
						};
					} foreach _NrstMine;
				};
			};
		};
	} foreach _magsAmmo;

};
} foreach (units _this);
