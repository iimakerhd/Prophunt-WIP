-- ===========================================================================
-- Wall climbing for the Props team.
--
-- Hold [Space] while looking at a nearby wall to stick to it; release to drop
-- off. While stuck, movement is redirected along the wall's own surface
-- (using its hit normal) instead of normal ground movement, with gravity
-- effectively disabled via MOVETYPE_FLY.
--
-- This is implemented with the "Move" hook (not a net message + flag) on
-- purpose: Move runs identically during client-side prediction AND
-- server-side simulation for the SAME player, using the already-replicated
-- CUserCmd button/movement state - so it stays perfectly smooth with zero
-- added network latency, the same way built-in Source movement (walking,
-- jumping, noclip) works. A net-message-driven "start/stop sticking" flag
-- would introduce a round-trip of latency and prediction mismatches instead.
-- ===========================================================================

local WALLCLIMB_MAX_DIST = 42    -- how close to a wall (units) before you can stick to it
local WALLCLIMB_MAX_SLOPE = 0.4  -- how vertical a surface must be to count as a "wall" (0 = perfectly vertical, 1 = flat floor/ceiling)
local WALLCLIMB_STICK_PULL = 24  -- gentle constant velocity into the wall, to stay glued against small surface irregularities
local WALLCLIMB_DETACH_PUSH = 80 -- push-away speed when letting go, so you don't immediately re-trace back into the wall

hook.Add("Move", "PH_WallClimbMove", function(pl, mv)
	if !IsValid(pl) or !pl:Alive() then return end

	local isProp = pl:Team() == TEAM_PROPS
	local holdingStick = isProp and (bit.band(mv:GetButtons(), IN_JUMP) != 0)
	local wasSticking = pl.WallSticking

	if holdingStick then
		local eyePos = mv:GetOrigin() + pl:GetViewOffset()
		local forward = pl:EyeAngles():Forward()

		local tr = util.TraceLine({
			start = eyePos,
			endpos = eyePos + forward * WALLCLIMB_MAX_DIST,
			filter = pl,
			mask = MASK_PLAYERSOLID_BRUSHONLY
		})

		if tr.Hit and math.abs(tr.HitNormal.z) < WALLCLIMB_MAX_SLOPE then
			pl.WallSticking = true
			pl.WallNormal = tr.HitNormal
		end
		-- If not currently stuck and no wall found in range, holding the key
		-- does nothing special (falls through to normal jump behaviour).
	else
		pl.WallSticking = false
	end

	if pl.WallSticking != wasSticking then
		-- MoveType must only ever be changed authoritatively on the server -
		-- letting client-side prediction change it too would fight the
		-- server's own state and cause a visible correction/snap.
		if SERVER then
			pl:SetMoveType(pl.WallSticking and MOVETYPE_FLY or MOVETYPE_WALK)
			pl:SetNWBool("PH_WallSticking", pl.WallSticking)
			if pl.WallNormal then
				pl:SetNWVector("PH_WallNormal", pl.WallNormal)
			end
		end

		if !pl.WallSticking and pl.WallNormal then
			mv:SetVelocity(pl.WallNormal * WALLCLIMB_DETACH_PUSH)
			pl.WallNormal = nil
			return
		end
	end

	if pl.WallSticking and pl.WallNormal then
		local normal = pl.WallNormal
		local ang = pl:EyeAngles()
		local fwd = ang:Forward()
		local right = ang:Right()

		-- Project the player's look-based forward/right onto the wall's own
		-- surface plane (remove the component pointing into/out of the wall),
		-- so WASD input moves you ALONG the wall rather than trying to walk
		-- through or away from it.
		fwd = fwd - normal * fwd:Dot(normal)
		if fwd:Length() > 0.001 then fwd:Normalize() else fwd = Vector(0, 0, 0) end
		right = right - normal * right:Dot(normal)
		if right:Length() > 0.001 then right:Normalize() else right = Vector(0, 0, 0) end

		local vel = fwd * mv:GetForwardSpeed() + right * mv:GetSideSpeed()
		vel = vel - normal * WALLCLIMB_STICK_PULL

		mv:SetVelocity(vel)
	end
end)

-- Clean up wall-stick state (and force movement back to normal) whenever a
-- Prop stops being relevant to it - death, respawn, disconnect - so a player
-- can never get stuck in MOVETYPE_FLY with no way back to walking normally.
local function PH_ClearWallStick(pl)
	if !IsValid(pl) then return end
	pl.WallSticking = false
	pl.WallNormal = nil
	if SERVER then
		pl:SetMoveType(MOVETYPE_WALK)
		pl:SetNWBool("PH_WallSticking", false)
	end
end

hook.Add("PlayerDeath", "PH_WallClimbClearOnDeath", PH_ClearWallStick)
hook.Add("PlayerDisconnected", "PH_WallClimbClearOnDisconnect", PH_ClearWallStick)
hook.Add("PlayerSpawn", "PH_WallClimbClearOnSpawn", PH_ClearWallStick)
