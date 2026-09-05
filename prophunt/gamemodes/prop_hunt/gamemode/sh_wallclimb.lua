-- ===========================================================================
-- Wall climbing for the Props team.
--
-- Hold [Space] while looking at a nearby wall to stick to it; release to
-- drop off. While stuck, W/A/S/D (any combination, including diagonals)
-- move you freely across the wall's own surface, decoupled from view angle.
--
-- FULLY SERVER-AUTHORITATIVE - NO CLIENT PREDICTION.
--
-- Two earlier versions of this tried to make wall-climbing work through
-- GMod's client-prediction system (the "Move" hook: first cooperating with
-- Source's built-in MOVETYPE_FLY physics via mv:SetVelocity(), then trying
-- to fully replace it with manual mv:SetOrigin() calls inside that same
-- hook). Both still produced visible position correction - because the
-- disguised ph_prop entity is positioned every tick from the SERVER's
-- pl:GetPos() (see PH_UpdatePropPosition in gamemode/init.lua), while the
-- LOCAL player was busy predicting its OWN position client-side in
-- parallel. Any disagreement between those two - and the "Move" hook is a
-- notoriously easy place to introduce one without realizing it - shows up
-- exactly like this: your own view looks fine (it trusts its own
-- prediction), but the prop mirroring your "real" server position visibly
-- snaps to catch up whenever the server's tally disagrees.
--
-- This version removes prediction from the equation entirely: it doesn't
-- use the "Move" hook at all. Instead, a plain server-side "Tick" hook
-- computes and sets position directly, once per server tick, for every
-- Prop currently sticking to a wall. There is exactly ONE authoritative
-- position - the server's - and nothing for a client to mispredict and
-- then get corrected from. The trade-off is that wall-climbing now feels
-- like ordinary networked movement (the same slight softness as watching
-- any other player move) rather than the zero-latency feel of predicted
-- movement - a deliberate trade for guaranteed correctness after two
-- prediction-based attempts both failed in ways I had no way to verify
-- without actually running the game.
-- ===========================================================================

local WALLCLIMB_MAX_DIST = 42    -- how close to a wall (units) before you can stick to it
local WALLCLIMB_MAX_SLOPE = 0.4  -- how vertical a surface must be to count as a "wall" (0 = perfectly vertical, 1 = flat floor/ceiling)
local WALLCLIMB_SPEED = 200      -- units/sec while crawling across a wall
local WALLCLIMB_DETACH_PUSH = 80 -- push-away speed when letting go normally (not by crawling off an edge), so you don't immediately fall back against the wall

-- Wall-local up/right axes, decoupled from view angle. An even earlier
-- version derived these from EyeAngles(), which - the moment you're facing
-- the wall closely enough to stick to it in the first place - is nearly
-- PARALLEL to the wall's own normal, leaving almost no tangential movement
-- after projection. These instead come from world-up projected onto the
-- wall's own plane, so they always have full magnitude no matter which way
-- you're facing, and you're free to look anywhere while crawling.
local function ComputeWallAxes(normal)
	local worldUp = Vector(0, 0, 1)
	local wallUp = worldUp - normal * worldUp:Dot(normal)
	if wallUp:Length() < 0.001 then
		-- Only reachable on a near-perfectly flat ceiling/floor, which
		-- WALLCLIMB_MAX_SLOPE already excludes from being climbable -
		-- kept purely as a safe fallback so Normalize() never runs on a
		-- zero vector.
		wallUp = Vector(0, 1, 0) - normal * Vector(0, 1, 0):Dot(normal)
	end
	wallUp:Normalize()

	local wallRight = wallUp:Cross(normal)
	wallRight:Normalize()

	return wallUp, wallRight
end

if SERVER then
	local function StopClimb(pl, pushOff)
		local normal = pl.WallNormal

		pl.WallSticking = false
		pl.WallNormal = nil
		pl:SetMoveType(MOVETYPE_WALK)
		pl:SetNWBool("PH_WallSticking", false)

		if pushOff and normal then
			pl:SetVelocity(normal * WALLCLIMB_DETACH_PUSH)
		end
	end

	local function StartClimb(pl, normal)
		pl.WallSticking = true
		pl.WallNormal = normal
		pl:SetMoveType(MOVETYPE_NONE) -- fully server-driven position while stuck; no gravity, no built-in input movement to fight
		pl:SetNWBool("PH_WallSticking", true)
		pl:SetNWVector("PH_WallNormal", normal)
	end

	local function TickClimb(pl)
		-- Re-probe straight INTO the current wall normal from the player's
		-- own position (not their view) each tick - lets them look around
		-- freely while climbing without the trace re-targeting a different
		-- nearby surface, and naturally lets go once they've crawled past
		-- the edge of the current surface (the probe just stops hitting
		-- anything, so this "release" is not a pushOff - there's no wall
		-- left to push away from).
		local probeStart = pl:EyePos()
		local tr = util.TraceLine({
			start = probeStart,
			endpos = probeStart - pl.WallNormal * (WALLCLIMB_MAX_DIST * 0.75),
			filter = pl,
			mask = MASK_PLAYERSOLID_BRUSHONLY
		})

		if tr.Hit and math.abs(tr.HitNormal.z) < WALLCLIMB_MAX_SLOPE then
			pl.WallNormal = tr.HitNormal
			pl:SetNWVector("PH_WallNormal", pl.WallNormal)
		else
			StopClimb(pl, false)
			return
		end

		local wallUp, wallRight = ComputeWallAxes(pl.WallNormal)

		-- Spider-style free movement: any combination of W/A/S/D - including
		-- diagonals - moves in that combined direction across the surface.
		local moveDir = Vector(0, 0, 0)
		if pl:KeyDown(IN_FORWARD) then moveDir = moveDir + wallUp end
		if pl:KeyDown(IN_BACK) then moveDir = moveDir - wallUp end
		if pl:KeyDown(IN_MOVERIGHT) then moveDir = moveDir + wallRight end
		if pl:KeyDown(IN_MOVELEFT) then moveDir = moveDir - wallRight end

		if moveDir:Length() > 0.001 then
			moveDir:Normalize()
		end

		local vel = moveDir * WALLCLIMB_SPEED
		local origin = pl:GetPos()
		local destination = origin + vel * engine.TickInterval()

		-- Basic collision safety - stops the sweep at the first solid hit
		-- instead of tunnelling through geometry - without going through
		-- any velocity/wishdir/friction system at all. tr.HitPos is either
		-- the full destination (nothing in the way) or the clipped point
		-- along the sweep (something was).
		local tr2 = util.TraceHull({
			start = origin,
			endpos = destination,
			mins = pl:OBBMins(),
			maxs = pl:OBBMaxs(),
			filter = pl,
			mask = MASK_PLAYERSOLID
		})

		pl:SetPos(tr2.HitPos)
		pl:SetVelocity(vector_origin) -- MOVETYPE_NONE ignores this anyway, but keep it clean for when they detach
	end

	hook.Add("Tick", "PH_WallClimbTick", function()
		for _, pl in pairs(player.GetAll()) do
			if !IsValid(pl) then continue end

			if !pl:Alive() or pl:Team() != TEAM_PROPS then
				if pl.WallSticking then StopClimb(pl, false) end
				continue
			end

			local holdingStick = pl:KeyDown(IN_JUMP)

			if pl.WallSticking then
				if holdingStick then
					TickClimb(pl)
				else
					StopClimb(pl, true)
				end
			elseif holdingStick then
				local eyePos = pl:EyePos()
				local forward = pl:EyeAngles():Forward()

				local tr = util.TraceLine({
					start = eyePos,
					endpos = eyePos + forward * WALLCLIMB_MAX_DIST,
					filter = pl,
					mask = MASK_PLAYERSOLID_BRUSHONLY
				})

				if tr.Hit and math.abs(tr.HitNormal.z) < WALLCLIMB_MAX_SLOPE then
					StartClimb(pl, tr.HitNormal)
				end
				-- If no wall found in range, holding the key does nothing
				-- special (falls through to normal jump behaviour).
			end
		end
	end)

	-- Clean up wall-stick state (and force movement back to normal) whenever
	-- a Prop stops being relevant to it - death, respawn, disconnect - so a
	-- player can never get stuck in MOVETYPE_NONE with no way back to
	-- walking normally.
	local function PH_ClearWallStick(pl)
		if !IsValid(pl) then return end
		if pl.WallSticking then
			StopClimb(pl, false)
		end
	end

	hook.Add("PlayerDeath", "PH_WallClimbClearOnDeath", PH_ClearWallStick)
	hook.Add("PlayerDisconnected", "PH_WallClimbClearOnDisconnect", PH_ClearWallStick)
	hook.Add("PlayerSpawn", "PH_WallClimbClearOnSpawn", PH_ClearWallStick)
end
