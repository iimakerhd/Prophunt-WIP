-- Send the required lua files to the client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_prop_taunts.lua")
AddCSLuaFile("sh_config.lua")
AddCSLuaFile("sh_init.lua")
AddCSLuaFile("sh_player.lua")


-- If there is a mapfile send it to the client (sometimes servers want to change settings for certain maps)
if file.Exists("../gamemodes/prop_hunt/gamemode/maps/"..game.GetMap()..".lua", "LUA") then
	AddCSLuaFile("maps/"..game.GetMap()..".lua")
end


-- Include the required lua files
include("sh_init.lua")


-- Server only constants
EXPLOITABLE_DOORS = {
	"func_door",
	"prop_door_rotating", 
	"func_door_rotating"
}
USABLE_PROP_ENTITIES = {
	"prop_physics",
	"prop_physics_multiplayer"
}


-- Send the required resources to the client
for _, taunt in pairs(HUNTER_TAUNTS) do resource.AddFile("sound/"..taunt) end
for _, taunt in pairs(PROP_TAUNTS) do resource.AddFile("sound/"..taunt) end

-- Auto-discover taunt files from our own addon-unique folder (see PROP_TAUNT_FOLDER
-- in sh_config.lua) and push them to clients. Because the folder name is unique to
-- this addon, this scan can't pick up files from other installed addons.
local propTauntFiles = file.Find("sound/" .. PROP_TAUNT_FOLDER .. "*.*", "GAME")
for _, filename in ipairs(propTauntFiles) do
	local ext = string.GetExtensionFromFilename(filename):lower()
	if ext == "wav" or ext == "mp3" or ext == "ogg" then
		resource.AddFile("sound/" .. PROP_TAUNT_FOLDER .. filename)
	end
end

-- Network support for prop rotation control from props
util.AddNetworkString("PH_RotateProp")
util.AddNetworkString("PH_TogglePropRotateLock")
util.AddNetworkString("PH_PlayTaunt")
util.AddNetworkString("PH_RequestPropTaunts")
util.AddNetworkString("PH_PropTauntList")
util.AddNetworkString("PlayerKilledByPlayer")
util.AddNetworkString("PH_SetHunterModel")
net.Receive("PH_RotateProp", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_PROPS then return end
	if pl:GetNWBool("PH_RotateLocked", false) then return end
	if !pl.ph_prop || !pl.ph_prop:IsValid() then return end

	local yaw = net.ReadFloat()
	if !yaw then return end

	local ang = pl.ph_prop:GetAngles()
	ang.y = ang.y + yaw
	pl.ph_prop:SetAngles(ang)
	pl:SetNWFloat("PH_PropYaw", ang.y)
end)

net.Receive("PH_TogglePropRotateLock", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_PROPS then return end
	if !pl.ph_prop || !pl.ph_prop:IsValid() then return end

	local locked = !pl:GetNWBool("PH_RotateLocked", false)
	pl:SetNWBool("PH_RotateLocked", locked)
end)

net.Receive("PH_PlayTaunt", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_PROPS then return end
	if !GAMEMODE:InRound() then return end
	if pl.last_taunt_time + TAUNT_DELAY > CurTime() then return end

	local taunt = net.ReadString()
	if !taunt or taunt == "" then return end
	if not string.StartWith(taunt, PROP_TAUNT_FOLDER) then return end
	if !file.Exists("sound/" .. taunt, "GAME") then return end

	local ext = string.GetExtensionFromFilename(taunt):lower()
	if ext != "wav" && ext != "mp3" && ext != "ogg" then return end

	pl.last_taunt_time = CurTime()
	pl.last_taunt = taunt
	pl:EmitSound(taunt, 100)
end)


net.Receive("PH_RequestPropTaunts", function(len, pl)
	if !IsValid(pl) then return end
	local files = file.Find("sound/" .. PROP_TAUNT_FOLDER .. "*.*", "GAME")
	local entries = {}
	for _, filename in ipairs(files) do
		local ext = string.GetExtensionFromFilename(filename):lower()
		if ext == "wav" or ext == "mp3" or ext == "ogg" then
			table.insert(entries, filename)
		end
	end

	net.Start("PH_PropTauntList")
		net.WriteTable(entries)
	net.Send(pl)
end)

-- Rebuilds a player's first-person view hands to match a given player model key
-- (from player_manager.AllValidModels()). Shared between initial spawn and a live
-- hunter model change so the hands never end up mismatched with the body model.
local function UTIL_RefreshPlayerHands(pl, modelKey)
	local oldhands = pl:GetHands()
	if ( IsValid( oldhands ) ) then oldhands:Remove() end

	local hands = ents.Create( "gmod_hands" )
	if ( IsValid( hands ) ) then
		pl:SetHands( hands )
		hands:SetOwner( pl )

		local handsKey = modelKey or pl:GetInfo( "cl_playermodel" )
		local info = player_manager.TranslatePlayerHands( handsKey )
		if ( info ) then
			hands:SetModel( info.model )
			hands:SetSkin( info.skin )
			hands:SetBodyGroups( info.body )
		end

		-- Attach them to the viewmodel
		local vm = pl:GetViewModel( 0 )
		hands:AttachToViewmodel( vm )

		vm:DeleteOnRemove( hands )
		pl:DeleteOnRemove( hands )

		hands:Spawn()
	end
end

-- Applies a hunter player model immediately, live, with no respawn required:
-- updates the visible body model, the networked key (so it persists across
-- spawns/rounds and matches on reconnect), and the first-person hands to match.
local function UTIL_ApplyHunterModel(pl, modelKey)
	local models = player_manager.AllValidModels()
	local modelPath = models[modelKey]
	if !modelPath then return false end

	pl:SetNWString("PH_HunterModel", modelKey)
	util.PrecacheModel(modelPath)
	pl:SetModel(modelPath)
	UTIL_RefreshPlayerHands(pl, modelKey)
	return true
end

net.Receive("PH_SetHunterModel", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_HUNTERS then return end

	local modelKey = net.ReadString()
	if !modelKey or modelKey == "" then return end

	UTIL_ApplyHunterModel(pl, modelKey)
end)

-- Called alot
function GM:CheckPlayerDeathRoundEnd()
	if !GAMEMODE.RoundBased || !GAMEMODE:InRound() then 
		return
	end

	local Teams = GAMEMODE:GetTeamAliveCounts()

	if table.Count(Teams) == 0 then
		GAMEMODE:RoundEndWithResult(1001, "Draw, everyone loses!")
		return
	end

	if table.Count(Teams) == 1 then
		local TeamID = table.GetFirstKey(Teams)
		GAMEMODE:RoundEndWithResult(TeamID, team.GetName(1).." win!")
		return
	end
	
end


-- Called when an entity takes damage
function EntityTakeDamage(ent, dmginfo)
    local att = dmginfo:GetAttacker()
	if GAMEMODE:InRound() && ent && ent:GetClass() != "ph_prop" && !ent:IsPlayer() && att && att:IsPlayer() && att:Team() == TEAM_HUNTERS && att:Alive() then
		att:SetHealth(att:Health() - HUNTER_FIRE_PENALTY)
		if att:Health() <= 0 then
			MsgAll(att:Name() .. " felt guilty for hurting so many innocent props and committed suicide\n")
			att:Kill()
		end
	end
end
hook.Add("EntityTakeDamage", "PH_EntityTakeDamage", EntityTakeDamage)


-- Called when player tries to pickup a weapon
function GM:PlayerCanPickupWeapon(pl, ent)
 	if pl:Team() != TEAM_HUNTERS then
		return false
	end
	
	return true
end

function GM:PlayerSetModel(pl)
	-- set antlion gib small for Prop model. Do not change into others because this might purposed as a hitbox.
	local player_model = "models/Gibs/Antlion_gib_small_3.mdl"

	if pl:Team() == TEAM_HUNTERS then
		local models = player_manager.AllValidModels()
		local selectedKey = pl:GetNWString("PH_HunterModel", "combine")
		player_model = models[selectedKey] or models["combine"] or "models/police.mdl"
	end
	
	-- Precache it
	util.PrecacheModel(player_model)
	pl:SetModel(player_model)
end
	
-- Called when a player tries to use an object
function GM:PlayerUse(pl, ent)
	if !pl:Alive() || pl:Team() == TEAM_SPECTATOR then return false end
	
	if pl:Team() == TEAM_PROPS && pl:IsOnGround() && !pl:Crouching() && table.HasValue(USABLE_PROP_ENTITIES, ent:GetClass()) && ent:GetModel() then
		if not pl.ph_prop or not pl.ph_prop:IsValid() then
			return false
		end

		if table.HasValue(BANNED_PROP_MODELS, ent:GetModel()) then
			pl:ChatPrint("That prop has been banned by the server.")
		elseif ent:GetPhysicsObject():IsValid() && pl.ph_prop:GetModel() != ent:GetModel() then
			local obbmins = ent:OBBMins()
			local obbmaxs = ent:OBBMaxs()

			-- Fit check: make sure the new prop's shape actually has room to exist
			-- where the player is standing before we commit to the switch. Without
			-- this, grabbing a large/awkward prop in a corner or tight nook would
			-- just silently clip the visual mesh underground or into walls.
			local footZ = obbmins.z
			if footZ > 0 then footZ = 0 end
			local fitOrigin = pl:GetPos() - Vector(0, 0, footZ)
			local fitTrace = util.TraceHull({
				start = fitOrigin,
				endpos = fitOrigin,
				mins = obbmins,
				maxs = obbmaxs,
				filter = {pl, pl.ph_prop, ent},
				mask = MASK_PLAYERSOLID_BRUSHONLY
			})

			if fitTrace.StartSolid then
				pl:ChatPrint("There isn't enough room to become that prop here.")
				return true
			end

			local currentHealth = pl.ph_prop.health or 100
			local currentMaxHealth = pl.ph_prop.max_health or 100
			local ent_health = math.Clamp(ent:GetPhysicsObject():GetVolume() / 250, 1, 200)
			local new_health = math.Clamp((currentHealth / currentMaxHealth) * ent_health, 1, 200)
			local per = currentHealth / currentMaxHealth
			pl.ph_prop.health = new_health
			
			pl.ph_prop.max_health = ent_health
			pl.ph_prop:SetModel(ent:GetModel())
			pl.ph_prop:SetSkin(ent:GetSkin())
			pl.ph_prop:SetNotSolid(true)
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

			-- Always stand the prop upright (yaw only). Physics settling can leave a
			-- ground prop tipped/on its side (e.g. a knocked-over cup) - copying that
			-- exact world angle made the disguise inherit the same awkward tilt. Only
			-- the facing direction carries over; pitch/roll reset to a natural pose.
			local ang = Angle(0, ent:GetAngles().y, 0)
			pl.ph_prop:SetAngles(ang)
			pl:SetNWBool("PH_RotateLocked", false)
			pl:SetNWFloat("PH_PropYaw", ang.y)
			
			local width = math.max(1, math.Round(math.abs(obbmins.x) + math.abs(obbmaxs.x)))
			local depth = math.max(1, math.Round(math.abs(obbmins.y) + math.abs(obbmaxs.y)))
			local hullz = math.max(1, math.Round(math.abs(obbmins.z) + math.abs(obbmaxs.z)))
			
			local hullxmin = -math.ceil(width * 0.5)
			local hullxmax = math.ceil(width * 0.5)
			local hullymin = -math.ceil(depth * 0.5)
			local hullymax = math.ceil(depth * 0.5)
			
			-- Small props get a tighter centered player hull so they can hug walls more closely.
			if width <= 16 and depth <= 16 then
				hullxmin, hullxmax = -1, 1
				hullymin, hullymax = -1, 1
			else
				local shrink = math.max(3, math.Round(math.min(width, depth) * 0.15))
				hullxmin = math.min(hullxmin + shrink, -1)
				hullymin = math.min(hullymin + shrink, -1)
				hullxmax = math.max(hullxmax - shrink, 1)
				hullymax = math.max(hullymax - shrink, 1)
			end
			
			pl:SetHull(Vector(hullxmin, hullymin, 0), Vector(hullxmax, hullymax, hullz))
			pl:SetHullDuck(Vector(hullxmin, hullymin, 0), Vector(hullxmax, hullymax, hullz))
			pl:SetHealth(new_health)
			
			umsg.Start("SetHull", pl)
				umsg.Long(hullxmin)
				umsg.Long(hullxmax)
				umsg.Long(hullymin)
				umsg.Long(hullymax)
				umsg.Long(hullz)
				umsg.Short(new_health)
			umsg.End()
		end
	end
	
	-- Prevent the door exploit
	if table.HasValue(EXPLOITABLE_DOORS, ent:GetClass()) && pl.last_door_time && pl.last_door_time + 1 > CurTime() then
		return false
	end
	
	pl.last_door_time = CurTime()
	return true
end

-- Called when player presses [F3]. Plays a taunt for their team
function GM:ShowSpare1(pl)
	if GAMEMODE:InRound() && pl:Alive() && (pl:Team() == TEAM_HUNTERS || pl:Team() == TEAM_PROPS) && pl.last_taunt_time + TAUNT_DELAY <= CurTime() && #PROP_TAUNTS > 1 && #HUNTER_TAUNTS > 1 then
		repeat
			if pl:Team() == TEAM_HUNTERS then
				rand_taunt = table.Random(HUNTER_TAUNTS)
			else
				rand_taunt = table.Random(PROP_TAUNTS)
			end
		until rand_taunt != pl.last_taunt
		
		pl.last_taunt_time = CurTime()
		pl.last_taunt = rand_taunt
		
		pl:EmitSound(rand_taunt, 100)
	end	
end

--[[
-- Called when the gamemode is initialized -- This does not even working since the command is blocked.
function Initialize()
	game.ConsoleCommand("mp_flashlight 1\n")
end
hook.Add("Initialize", "PH_Initialize", Initialize)
]]--

-- Called when a player leaves
function PlayerDisconnected(pl)
	pl:RemoveProp()
end
hook.Add("PlayerDisconnected", "PH_PlayerDisconnected", PlayerDisconnected)

hook.Add("PlayerTick", "PH_UpdatePropPosition", function(pl, mv)
	if !IsValid(pl) or pl:Team() != TEAM_PROPS or !pl:Alive() then return end
	if !pl.ph_prop or !IsValid(pl.ph_prop) then return end

	local z = pl.ph_prop:OBBMins().z
	if z > 0 then z = 0 end
	pl.ph_prop:SetPos(pl:GetPos() - Vector(0, 0, z))
end)


-- Called when the players spawns
function PlayerSpawn(pl)

	local handsKey = nil
	if pl:Team() == TEAM_HUNTERS then
		handsKey = pl:GetNWString("PH_HunterModel", "combine")
	end
	UTIL_RefreshPlayerHands(pl, handsKey)

	pl:Blind(false)
	pl:RemoveProp()
	pl:SetColor( Color(255, 255, 255, 255))
	pl:SetRenderMode( RENDERMODE_TRANSALPHA )
	pl:UnLock()
	pl:ResetHull()
	pl.last_taunt_time = 0
	
	umsg.Start("ResetHull", pl)
	umsg.End()
	
	pl:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
end
hook.Add("PlayerSpawn", "PH_PlayerSpawn", PlayerSpawn)


-- Removes all weapons on a map
function RemoveWeaponsAndItems()
	for _, wep in pairs(ents.FindByClass("weapon_*")) do
		wep:Remove()
	end
	
	for _, item in pairs(ents.FindByClass("item_*")) do
		item:Remove()
	end
end
hook.Add("InitPostEntity", "PH_RemoveWeaponsAndItems", RemoveWeaponsAndItems)


-- Called when round ends
function RoundEnd()
	for _, pl in pairs(team.GetPlayers(TEAM_HUNTERS)) do
		pl:Blind(false)
		pl:UnLock()
	end
end
hook.Add("RoundEnd", "PH_RoundEnd", RoundEnd)


-- This is called when the round time ends (props win)
function GM:RoundTimerEnd()
	if !GAMEMODE:InRound() then
		return
	end
   
	GAMEMODE:RoundEndWithResult(TEAM_PROPS, "Props win!")
end


-- Called before start of round
function GM:OnPreRoundStart(num)
	game.CleanUpMap()
	
		if GetGlobalInt("RoundNumber") != 1 && (SWAP_TEAMS_EVERY_ROUND == 1 || ((team.GetScore(TEAM_PROPS) + team.GetScore(TEAM_HUNTERS)) > 0 || SWAP_TEAMS_POINTS_ZERO==1)) then
		for _, pl in pairs(player.GetAll()) do
				if pl:Team() == TEAM_PROPS || pl:Team() == TEAM_HUNTERS then
				if pl:Team() == TEAM_PROPS then
					pl:SetTeam(TEAM_HUNTERS)
				else
					pl:SetTeam(TEAM_PROPS)
				end
				
				pl:ChatPrint("Teams have been swapped!")

			end
		end
	end
	
	UTIL_StripAllPlayers()
	UTIL_SpawnAllPlayers()
	UTIL_FreezeAllPlayers()
end