-- Create new class
local CLASS = {}


-- Some settings for the class
CLASS.DisplayName			= "Prop"
CLASS.WalkSpeed 			= 280
CLASS.CrouchedWalkSpeed 	= 0.3
CLASS.RunSpeed				= 300
CLASS.DuckSpeed				= 0.3
CLASS.DrawTeamRing			= false


-- Called by spawn and sets loadout
function CLASS:Loadout(pl)
	pl:Give("weapon_ph_flashbang")

	-- SetAmmo (not GiveAmmo) so a leftover partial charge count from a
	-- previous life never carries over - always exactly
	-- FLASHBANG_CHARGES_PER_LIFE at the start of a new life, same per-life
	-- reset semantics as pl.ph_decoy_charges (sh_config.lua/class_prop.lua).
	pl:SetAmmo(FLASHBANG_CHARGES_PER_LIFE, "PHFlashbang")
end


-- Called when player spawns with this class
function CLASS:OnSpawn(pl)
	pl:SetColor( Color(255, 255, 255, 0))
	
	pl.ph_prop = ents.Create("ph_prop")
	pl.ph_prop:SetPos(pl:GetPos())
	pl.ph_prop:SetAngles(pl:GetAngles())
	pl.ph_prop:Spawn()
	-- Solid/collision-group/movetype are already set correctly by ENT:Initialize
	-- (ph_prop/init.lua) - don't touch them here. This used to call
	-- SetNotSolid(true) immediately after Spawn(), which silently re-undid
	-- Initialize's solid setup right at creation time, right back to being
	-- unhittable by bullet traces.
	pl.ph_prop:SetOwner(pl)

	local propMinZ = pl.ph_prop:OBBMins().z
	if propMinZ > 0 then propMinZ = 0 end
	local targetPos = pl:GetPos() - Vector(0, 0, propMinZ)
	local tr = util.TraceLine({
		start = targetPos + Vector(0, 0, 8),
		endpos = targetPos - Vector(0, 0, 64),
		filter = pl.ph_prop,
		mask = MASK_SOLID_BRUSHONLY
	})
	if tr.Hit then
		targetPos = tr.HitPos - Vector(0, 0, propMinZ)
	end
	pl.ph_prop:SetPos(targetPos)
	
	pl.ph_prop.max_health = 100
	pl:SetNWBool("PH_RotateLocked", false)

	-- Decoys are prop-only and refill each life. Kept here (rather than the
	-- generic PlayerSpawn hook in gamemode/init.lua, which also fires for
	-- hunters) so hunters never carry a charge count that means nothing to
	-- them. PH_DecoyCharges is networked so the drop-decoy HUD hint
	-- (gamemode/cl_init.lua) can show the count without a round trip.
	pl.ph_decoy_charges = DECOY_CHARGES_PER_LIFE
	pl:SetNWInt("PH_DecoyCharges", DECOY_CHARGES_PER_LIFE)

	-- Same per-life refill pattern for the liquid trail power-up.
	pl.ph_liquid_charges = LIQUID_TRAIL_CHARGES_PER_LIFE
	pl:SetNWInt("PH_LiquidCharges", LIQUID_TRAIL_CHARGES_PER_LIFE)
	pl.ph_liquid_trail_active = false
	pl:SetNWFloat("PH_LiquidTrailEndTime", 0)
end

if CLIENT then
	local nextRotateSend = 0

	local function GetLocalProp(pl)
		if pl.ph_prop and IsValid(pl.ph_prop) then
			return pl.ph_prop
		end

		for _, ent in ipairs(ents.FindByClass("ph_prop")) do
			if ent:GetOwner() == pl then
				pl.ph_prop = ent
				return ent
			end
		end

		return nil
	end

	function CLASS:InputMouseApply(pl, cmd, x, y, angle)
		if not pl or pl:Team() ~= TEAM_PROPS or not pl:Alive() then
			return angle
		end

		local prop = GetLocalProp(pl)
		if not prop then
			return angle
		end

		if pl:GetNWBool("PH_RotateLocked", false) then
			return angle
		end

		local reloadHeld = cmd:KeyDown(IN_RELOAD) or input.IsKeyDown(KEY_R)
		if reloadHeld and x ~= 0 and CurTime() >= nextRotateSend then
			nextRotateSend = CurTime() + 0.02
			local yaw = -x * 1.2
			net.Start("PH_RotateProp")
				net.WriteFloat(yaw)
			net.SendToServer()

			-- Apply immediate local feedback so selected prop rotation feels responsive.
			local ang = prop:GetAngles()
			ang.y = ang.y + yaw
			prop:SetAngles(ang)
		end

		return angle
	end

	-- Lock/unlock is handled in client-side input polling to allow KEY_L toggle without conflicting with rotation hold.
end

-- Called when a player dies with this class
function CLASS:OnDeath(pl, attacker, dmginfo)
	pl:RemoveProp()
	pl:RemoveDecoy()
	pl:StopLiquidTrail()
end


-- Register
player_class.Register("Prop", CLASS)
