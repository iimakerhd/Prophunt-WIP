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
