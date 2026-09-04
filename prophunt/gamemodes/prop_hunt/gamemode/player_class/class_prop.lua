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
	-- Flashbang is the only power-up delivered as an actual weapon (the
	-- other three are keybind abilities) - only give/ammo it if flashbang
	-- is this round's single random pick (GetGlobalString("PH_RoundPowerUp"),
	-- set in gamemode/init.lua:GM:OnPreRoundStart). Otherwise the prop
	-- simply doesn't get the weapon this round.
	if GetGlobalString("PH_RoundPowerUp", "") == "flashbang" then
		pl:Give("weapon_ph_flashbang")

		-- SetAmmo (not GiveAmmo) so a leftover partial charge count from a
		-- previous life never carries over - always exactly
		-- FLASHBANG_CHARGES_PER_LIFE at the start of a new life.
		pl:SetAmmo(FLASHBANG_CHARGES_PER_LIFE, "PHFlashbang")
	end
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

	-- Prop team gets exactly ONE power-up per round (PROP_POWERUPS in
	-- sh_config.lua), picked once for the whole team in
	-- gamemode/init.lua:GM:OnPreRoundStart and shared here via
	-- GetGlobalString("PH_RoundPowerUp") - NOT re-rolled per player/life.
	-- Only the matching charge pool gets refilled; the other three are
	-- explicitly zeroed so their keybinds/HUD naturally do nothing this
	-- round (and the server-side net handlers in gamemode/init.lua also
	-- gate on the same global, so this isn't just a UI-level restriction).
	local roundPowerUp = GetGlobalString("PH_RoundPowerUp", "")

	pl.ph_decoy_charges = (roundPowerUp == "decoy") and DECOY_CHARGES_PER_LIFE or 0
	pl:SetNWInt("PH_DecoyCharges", pl.ph_decoy_charges)

	pl.ph_liquid_charges = (roundPowerUp == "liquid_trail") and LIQUID_TRAIL_CHARGES_PER_LIFE or 0
	pl:SetNWInt("PH_LiquidCharges", pl.ph_liquid_charges)
	pl.ph_liquid_trail_active = false
	pl:SetNWFloat("PH_LiquidTrailEndTime", 0)

	pl.ph_shockwave_charges = (roundPowerUp == "shockwave") and SHOCKWAVE_CHARGES_PER_LIFE or 0
	pl:SetNWInt("PH_ShockwaveCharges", pl.ph_shockwave_charges)
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
