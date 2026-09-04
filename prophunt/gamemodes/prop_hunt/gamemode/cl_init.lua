include("sh_init.lua")
include("cl_prop_taunts.lua")

-- Decides where  the player view should be (forces third person for props)
function GM:CalcView(pl, origin, angles, fov)
	local view = {} 
	
	if blind then
		view.origin = Vector(20000, 0, 0)
		view.angles = Angle(0, 0, 0)
		view.fov = fov
		
		return view
	end

	-- Ragdolled Hunters (liquid trail power-up, see meta:BecomeRagdoll in
	-- sh_player.lua) have their real body frozen and hidden - hover the
	-- camera over the stand-in prop_ragdoll instead of leaving them staring
	-- from the frozen, invisible body's original position.
	if pl:Team() == TEAM_HUNTERS && pl:GetNWBool("PH_Ragdolled", false) then
		local rag = pl:GetNWEntity("PH_RagdollEnt", NULL)
		if IsValid(rag) then
			view.origin = rag:GetPos() + Vector(0, 0, 60)
			view.angles = Angle(70, angles.y, 0)
			view.fov = fov

			return view
		end
	end
	
 	view.origin = origin 
 	view.angles	= angles 
 	view.fov = fov 
 	
 	-- Give the active weapon a go at changing the viewmodel position 
	if pl:Team() == TEAM_PROPS && pl:Alive() then
		view.origin = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
	else
	 	local wep = pl:GetActiveWeapon() 
	 	if wep && wep != NULL then 
	 		local func = wep.GetViewModelPosition 
	 		if func then 
	 			view.vm_origin, view.vm_angles = func(wep, origin*1, angles*1) -- Note: *1 to copy the object so the child function can't edit it. 
	 		end
	 		 
	 		local func = wep.CalcView 
	 		if func then 
	 			view.origin, view.angles, view.fov = func(wep, pl, origin*1, angles*1, fov) -- Note: *1 to copy the object so the child function can't edit it. 
	 		end 
	 	end
	end
 	
 	return view 
end

-- Display names for the round's random power-up pick (PH_RoundPowerUp
-- global, PROP_POWERUPS in sh_config.lua) - used by the HUD hint below.
local POWERUP_DISPLAY_NAMES = {
	decoy = "Decoy",
	flashbang = "Flashbang",
	liquid_trail = "Liquid Trail",
	shockwave = "Shockwave"
}


-- Draw round timeleft and hunter release timeleft
function HUDPaint()
	if GetGlobalBool("InRound", false) then
		local blindlock_time_left = (HUNTER_BLINDLOCK_TIME - (CurTime() - GetGlobalFloat("RoundStartTime", 0))) + 1
		
		if blindlock_time_left < 1 && blindlock_time_left > -6 then
			blindlock_time_left_msg = "Ready or not, here we come!"
		elseif blindlock_time_left > 0 then
			blindlock_time_left_msg = "Hunters will be unblinded and released in "..string.ToMinutesSeconds(blindlock_time_left)
		else
			blindlock_time_left_msg = nil
		end
		
		if blindlock_time_left_msg then
			surface.SetFont("MyFont")
			local tw, th = surface.GetTextSize(blindlock_time_left_msg)
			
			draw.RoundedBox(8, 20, 20, tw + 20, 26, Color(0, 0, 0, 75))
			draw.DrawText(blindlock_time_left_msg, "MyFont", 31, 26, Color(255, 255, 0, 255), TEXT_ALIGN_LEFT)
		end
	
		local lp = LocalPlayer()
		if lp && lp:Team() == TEAM_PROPS && lp:Alive() then
			surface.SetFont("MyFont")
			draw.DrawText("Hold [R] and move the mouse to rotate your selected prop.", "MyFont", 20, 60, Color(255, 255, 255, 255), TEXT_ALIGN_LEFT)
			if lp:GetNWBool("PH_RotateLocked", false) then
				draw.DrawText("Rotation locked: press [L] to unlock.", "MyFont", 20, 80, Color(255, 100, 100, 255), TEXT_ALIGN_LEFT)
			else
				draw.DrawText("Rotation unlocked: hold [R] to rotate.", "MyFont", 20, 80, Color(100, 255, 100, 255), TEXT_ALIGN_LEFT)
			end

			if lp:GetNWBool("PH_WallSticking", false) then
				draw.DrawText("Stuck to the wall - release [Space] to drop.", "MyFont", 20, 100, Color(100, 200, 255, 255), TEXT_ALIGN_LEFT)
			else
				draw.DrawText("Hold [Space] near a wall to climb and stick to it.", "MyFont", 20, 100, Color(255, 255, 255, 255), TEXT_ALIGN_LEFT)
			end

			-- Only ONE power-up is live this round (see PROP_POWERUPS in
			-- sh_config.lua and GM:OnPreRoundStart in gamemode/init.lua),
			-- and all four are now triggered by the SAME key [G] (single
			-- PH_UsePowerUp net message, server dispatches by round pick -
			-- see gamemode/init.lua). Show which power-up it is, then only
			-- that power-up's specific hint line.
			local roundPowerUp = GetGlobalString("PH_RoundPowerUp", "")
			draw.DrawText("This round's power-up: "..(POWERUP_DISPLAY_NAMES[roundPowerUp] or "none"), "MyFont", 20, 120, Color(255, 255, 255, 255), TEXT_ALIGN_LEFT)

			if roundPowerUp == "decoy" then
				local decoyCharges = lp:GetNWInt("PH_DecoyCharges", 0)
				local decoyColor = decoyCharges > 0 and Color(255, 220, 100, 255) or Color(150, 150, 150, 255)
				draw.DrawText("Press [G] to drop a decoy. Charges left: "..decoyCharges, "MyFont", 20, 140, decoyColor, TEXT_ALIGN_LEFT)
			elseif roundPowerUp == "flashbang" then
				local flashCharges = lp:GetNWInt("PH_FlashbangCharges", 0)
				local flashColor = flashCharges > 0 and Color(255, 220, 100, 255) or Color(150, 150, 150, 255)
				draw.DrawText("Press [G] to throw a flashbang. Charges left: "..flashCharges, "MyFont", 20, 140, flashColor, TEXT_ALIGN_LEFT)
			elseif roundPowerUp == "liquid_trail" then
				local liquidCharges = lp:GetNWInt("PH_LiquidCharges", 0)
				local liquidTrailEnd = lp:GetNWFloat("PH_LiquidTrailEndTime", 0)
				if liquidTrailEnd > CurTime() then
					draw.DrawText("Liquid trail active! ("..math.ceil(liquidTrailEnd - CurTime()).."s left)", "MyFont", 20, 140, Color(120, 255, 120, 255), TEXT_ALIGN_LEFT)
				else
					local liquidColor = liquidCharges > 0 and Color(120, 255, 120, 255) or Color(150, 150, 150, 255)
					draw.DrawText("Press [G] to leave a ragdoll-trap trail. Charges left: "..liquidCharges, "MyFont", 20, 140, liquidColor, TEXT_ALIGN_LEFT)
				end
			elseif roundPowerUp == "shockwave" then
				local shockwaveCharges = lp:GetNWInt("PH_ShockwaveCharges", 0)
				local shockwaveColor = shockwaveCharges > 0 and Color(150, 200, 255, 255) or Color(150, 150, 150, 255)
				draw.DrawText("Press [G] for a shockwave - stuns nearby Hunters through walls. Charges left: "..shockwaveCharges, "MyFont", 20, 140, shockwaveColor, TEXT_ALIGN_LEFT)
			end
		end

		-- Purely client-side "you're stunned" feedback for the affected
		-- Hunter - a translucent electric-blue screen tint plus a
		-- countdown. This does NOT affect their view/aim, only overlays it -
		-- the actual inability to move/act comes from the server-side
		-- meta:Lock() inside meta:Stun() (sh_player.lua).
		if lp && lp:Team() == TEAM_HUNTERS && lp:GetNWBool("PH_Stunned", false) then
			local scrW, scrH = ScrW(), ScrH()
			draw.RoundedBox(0, 0, 0, scrW, scrH, Color(80, 140, 255, 70))

			surface.SetFont("MyFont")
			local msg = "STUNNED"
			local tw, th = surface.GetTextSize(msg)
			draw.DrawText(msg, "MyFont", scrW / 2 - tw / 2, scrH / 2 - th / 2, Color(255, 255, 255, 220), TEXT_ALIGN_LEFT)
		end
	end
end
hook.Add("HUDPaint", "PH_HUDPaint", HUDPaint)

local lastLockKey = false
hook.Add("Think", "PH_PropRotateLockThink", function()
	local lp = LocalPlayer()
	if !IsValid(lp) or lp:Team() != TEAM_PROPS or !lp:Alive() then
		lastLockKey = false
		return
	end

	local down = input.IsKeyDown(KEY_L)
	if down and not lastLockKey then
		net.Start("PH_TogglePropRotateLock")
		net.SendToServer()
	end

	lastLockKey = down
end)

-- Sends a single PH_UsePowerUp request to the server on the rising edge of
-- [G] (down this tick, not down last tick) so holding the key doesn't spam
-- requests every frame. One key for all four power-ups now (previously
-- separate G/H/V keys plus a left-click weapon for flashbang) - the server
-- looks up which power-up is actually live this round and dispatches
-- accordingly (gamemode/init.lua: net.Receive("PH_UsePowerUp")). This client
-- code doesn't need to know or care which power-up it is.
local lastPowerUpKey = false
hook.Add("Think", "PH_UsePowerUpThink", function()
	local lp = LocalPlayer()
	if !IsValid(lp) or lp:Team() != TEAM_PROPS or !lp:Alive() then
		lastPowerUpKey = false
		return
	end

	local down = input.IsKeyDown(KEY_G)
	if down and not lastPowerUpKey then
		net.Start("PH_UsePowerUp")
		net.SendToServer()
	end

	lastPowerUpKey = down
end)


-- Called immediately after starting the gamemode 
function Initialize()
	hullz = 80
	--surface.CreateFont("Arial", 14, 1200, true, false, "ph_arial")
	surface.CreateFont( "MyFont",
	{
		font	= "Arial",
		size	= 14,
		weight	= 1200,
		antialias = true,
		underline = false
	})
end
hook.Add("Initialize", "PH_Initialize", Initialize)


-- Resets the player hull
function ResetHull(um)
	if LocalPlayer() && LocalPlayer():IsValid() then
		LocalPlayer():ResetHull()
		hullz = 80
	end
end
usermessage.Hook("ResetHull", ResetHull)

-- Show hands!
function GM:PostDrawViewModel( vm, pl, weapon )
   if weapon.UseHands or (not weapon:IsScripted()) then
      local hands = LocalPlayer():GetHands()
      if IsValid(hands) then hands:DrawModel() end
   end
end

-- Sets the local blind variable to be used in CalcView
function SetBlind(um)
	blind = um:ReadBool()
end
usermessage.Hook("SetBlind", SetBlind)


-- Sets the player hull
function SetHull(um)
	local hullxmin = um:ReadLong()
	local hullxmax = um:ReadLong()
	local hullymin = um:ReadLong()
	local hullymax = um:ReadLong()
	hullz = um:ReadLong()
	new_health = um:ReadLong()

	LocalPlayer():SetHull(Vector(hullxmin, hullymin, 0), Vector(hullxmax, hullymax, hullz))
	LocalPlayer():SetHullDuck(Vector(hullxmin, hullymin, 0), Vector(hullxmax, hullymax, hullz))
	LocalPlayer():SetHealth(new_health)
end
usermessage.Hook("SetHull", SetHull)
