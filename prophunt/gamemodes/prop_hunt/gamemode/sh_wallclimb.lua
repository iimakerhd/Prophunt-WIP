-- ===========================================================================
-- Wall climbing for the Props team.
--
-- Hold [Space] while looking at a nearby wall to stick to it; release to drop
-- off. While stuck, W/A/S/D (any combination, including diagonals) move you
-- freely across the wall's own surface - spider-style - decoupled from
-- gravity via MOVETYPE_FLY.
--
-- This is implemented with the "Move" hook (not a net message + flag) on
-- purpose: Move runs identically during client-side prediction AND
-- server-side simulation for the SAME player, using the already-replicated
-- CUserCmd button/movement state - so it stays perfectly smooth with zero
-- added network latency, the same way built-in Source movement (walking,
-- jumping, noclip) works. A net-message-driven "start/stop sticking" flag
-- would introduce a round-trip of latency and prediction mismatches instead.
--
-- MANUAL POSITION INTEGRATION: an earlier version tried to cooperate with
-- Source's own MOVETYPE_FLY physics - setting a wall-relative velocity via
-- mv:SetVelocity() and zeroing forward/side/up wish-speed, hoping the
-- engine's built-in fly-movement code would then just apply that velocity
-- cleanly. In practice that wasn't reliably translating into actual
-- on-screen movement - the built-in fly-movement processing that runs AFTER
-- this hook has its own friction/acceleration behavior derived from the RAW
-- view angles that isn't fully neutralized just by zeroing wish-speed, so it
-- kept fighting/absorbing the injected velocity and produced little to no
-- net movement. This version sidesteps that uncertainty completely: it sets
-- the player's ORIGIN directly (mv:SetOrigin()) each tick, using
-- engine.TickInterval() - a FIXED timestep identical between client-side
-- prediction and server-side simulation - rather than FrameTime(), which
-- varies with client FPS and would make the two disagree (that kind of
-- prediction/server divergence is exactly what produces a hard correction,
-- i.e. a visible "teleport", once the two get reconciled - which is also
-- what was making the mirrored ph_prop position glitch). A short TraceHull
-- sweep checks the destination is clear of solid geometry before committing
-- to it, so this still can't clip you through a wall.
-- ===========================================================================

local WALLCLIMB_MAX_DIST = 42    -- how close to a wall (units) before you can stick to it
local WALLCLIMB_MAX_SLOPE = 0.4  -- how vertical a surface must be to count as a "wall" (0 = perfectly vertical, 1 = flat floor/ceiling)
local WALLCLIMB_STICK_PULL = 24  -- gentle constant velocity into the wall, to stay glued against small surface irregularities
local WALLCLIMB_DETACH_PUSH = 80 -- push-away speed when letting go, so you don't immediately re-trace back into the wall
local WALLCLIMB_SPEED = 200      -- units/sec while crawling across a wall - a fixed speed, not derived from mv:GetForwardSpeed()/GetSideSpeed()

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
			-- wherever the view happens to be pointed - lets you look
			-- around freely while crawling without the trace suddenly
			-- re-targeting a different nearby surface, and naturally lets
			-- go once you've crawled past the edge of the current surface.
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

		-- Wall-local up/right axes, decoupled from view angle - see the
		-- top-of-file note on why (view-based axes go near-zero exactly
		-- when facing the wall closely enough to stick to it).
		local worldUp = Vector(0, 0, 1)
		local wallUp = worldUp - normal * worldUp:Dot(normal)
		if wallUp:Length() < 0.001 then
			-- Only reachable on a near-perfectly flat ceiling/floor, which
			-- WALLCLIMB_MAX_SLOPE already excludes from being climbable -
			-- kept purely as a safe fallback so Normalize() never runs on
			-- a zero vector.
			wallUp = Vector(0, 1, 0) - normal * Vector(0, 1, 0):Dot(normal)
		end
		wallUp:Normalize()
		local wallRight = wallUp:Cross(normal)
		wallRight:Normalize()

		-- Spider-style free movement: raw button state (not
		-- mv:GetForwardSpeed()/GetSideSpeed(), and not view angle) so any
		-- combination of W/A/S/D - including diagonals - moves you in that
		-- combined direction across the surface at a flat, predictable
		-- speed.
		local moveDir = Vector(0, 0, 0)
		local buttons = mv:GetButtons()
		if bit.band(buttons, IN_FORWARD) != 0 then moveDir = moveDir + wallUp end
		if bit.band(buttons, IN_BACK) != 0 then moveDir = moveDir - wallUp end
		if bit.band(buttons, IN_MOVERIGHT) != 0 then moveDir = moveDir + wallRight end
		if bit.band(buttons, IN_MOVELEFT) != 0 then moveDir = moveDir - wallRight end

		if moveDir:Length() > 0.001 then
			moveDir:Normalize()
		end

		local vel = moveDir * WALLCLIMB_SPEED - normal * WALLCLIMB_STICK_PULL

		-- Stop the engine's own fly-movement wishdir/acceleration from
		-- doing anything further with this tick - we're integrating
		-- position ourselves below, so any additional built-in movement on
		-- top of that would only reintroduce the exact fighting/divergence
		-- this rewrite is trying to eliminate.
		mv:SetForwardSpeed(0)
		mv:SetSideSpeed(0)
		mv:SetUpSpeed(0)

		local destination = mv:GetOrigin() + vel * engine.TickInterval()

		local tr = util.TraceHull({
			start = mv:GetOrigin(),
			endpos = destination,
			mins = pl:OBBMins(),
			maxs = pl:OBBMaxs(),
			filter = pl,
			mask = MASK_PLAYERSOLID
		})

		mv:SetOrigin(tr.HitPos)
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
