-- ===========================================================================
-- Wall climbing for the Props team.
--
-- Hold [Space] while looking at a nearby wall to stick to it; release to drop
-- off. While stuck, W/A/S/D climb up/down/left/right ALONG the wall's own
-- surface, with gravity effectively disabled via MOVETYPE_FLY.
--
-- This is implemented with the "Move" hook (not a net message + flag) on
-- purpose: Move runs identically during client-side prediction AND
-- server-side simulation for the SAME player, using the already-replicated
-- CUserCmd button/movement state - so it stays perfectly smooth with zero
-- added network latency, the same way built-in Source movement (walking,
-- jumping, noclip) works. A net-message-driven "start/stop sticking" flag
-- would introduce a round-trip of latency and prediction mismatches instead.
--
-- CHAMELEON-STYLE MOVEMENT: climbing direction is deliberately decoupled
-- from where you're LOOKING. An earlier version derived its up/right axes
-- from EyeAngles(), which - the moment you're facing the wall closely enough
-- to stick to it in the first place - is nearly PARALLEL to the wall's own
-- normal. Projecting that onto the wall plane left almost no tangential
-- vector, so pressing any movement key barely moved you at all (felt
-- permanently stuck). wallUp/wallRight below instead come from world-up
-- projected onto the wall's own plane, so they always have full magnitude no
-- matter which way you're facing - press up to climb up, down to climb
-- down, left/right to shimmy sideways, exactly like a lizard/chameleon
-- crawling a surface, and you're free to look around while doing it.
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
		if !wasSticking then
			-- Initial grab: aim at a nearby wall and hold [Space] to attach.
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
			-- If no wall found in range, holding the key does nothing
			-- special (falls through to normal jump behaviour).
		else
			-- Already attached: re-probe straight INTO the current wall
			-- normal from the player's own (moving) position, NOT from
			-- wherever the view happens to be pointed. This is what lets
			-- you look around freely while crawling without the trace
			-- suddenly re-targeting a different nearby surface just
			-- because you glanced at it, and it naturally lets go of you
			-- once you've crawled past the edge of the current surface
			-- (the probe simply stops hitting anything).
			local probeStart = mv:GetOrigin() + pl:GetViewOffset()
			local tr = util.TraceLine({
				start = probeStart,
				endpos = probeStart - pl.WallNormal * (WALLCLIMB_MAX_DIST * 0.75),
				filter = pl,
				mask = MASK_PLAYERSOLID_BRUSHONLY
			})

			if tr.Hit and math.abs(tr.HitNormal.z) < WALLCLIMB_MAX_SLOPE then
				pl.WallNormal = tr.HitNormal
			else
				pl.WallSticking = false
			end
		end
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

		local worldUp = Vector(0, 0, 1)
		local wallUp = worldUp - normal * worldUp:Dot(normal)
		if wallUp:Length() < 0.001 then
			-- Only reachable on a near-perfectly flat ceiling/floor, which
			-- WALLCLIMB_MAX_SLOPE already excludes from being climbable in
			-- the first place - kept purely as a safe fallback so
			-- Normalize() below never runs on a zero vector.
			wallUp = Vector(0, 1, 0) - normal * Vector(0, 1, 0):Dot(normal)
		end
		wallUp:Normalize()
		local wallRight = wallUp:Cross(normal)
		wallRight:Normalize()

		-- Capture the player's current forward/side move magnitudes (these
		-- already respect walk/crouch speed modifiers) BEFORE zeroing them.
		-- Zeroing is the second half of the fix: without it, Source's own
		-- built-in fly-movement wishdir/acceleration - computed from these
		-- plus the RAW view angles, not our wall-relative basis - kept
		-- trying to ALSO accelerate the player toward wherever they were
		-- looking (typically straight into the wall) every single tick,
		-- fighting the velocity set below. That fight is what produced
		-- unstable, sometimes-divergent movement simulation: it showed up
		-- as the "stuck" feeling, and - since the disguised prop's position
		-- is a 1:1 per-tick mirror of the player's position
		-- (PH_UpdatePropPosition in gamemode/init.lua) - any resulting
		-- jitter or hard prediction correction on the player showed up as
		-- the prop visibly glitching/teleporting too. Zeroing UpSpeed also
		-- stops holding [Space] from additionally floating you upward via
		-- the engine's own fly-up logic while it's being used to stick.
		local forwardMove = mv:GetForwardSpeed()
		local sideMove = mv:GetSideSpeed()
		mv:SetForwardSpeed(0)
		mv:SetSideSpeed(0)
		mv:SetUpSpeed(0)

		local vel = wallUp * forwardMove + wallRight * sideMove - normal * WALLCLIMB_STICK_PULL
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
