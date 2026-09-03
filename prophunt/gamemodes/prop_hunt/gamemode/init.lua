-- Send the required lua files to the client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_prop_taunts.lua")
AddCSLuaFile("sh_config.lua")
AddCSLuaFile("sh_init.lua")
AddCSLuaFile("sh_player.lua")
AddCSLuaFile("sh_wallclimb.lua")


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
util.AddNetworkString("PH_DropDecoy")
util.AddNetworkString("PH_ActivateLiquidTrail")
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

-- Drops a decoy at the player's current disguised position/model - a fake
-- copy of their prop meant to bait a hunter into wasting a shot. Prop-only,
-- gated on the player's remaining per-life charges (DECOY_CHARGES_PER_LIFE,
-- refilled in class_prop.lua:OnSpawn). Decoys are tracked per-player in
-- pl.ph_decoys so meta:RemoveDecoy() (sh_player.lua) can clean them all up
-- on death/disconnect, and they're hard-cleared map-wide at round start below.
net.Receive("PH_DropDecoy", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_PROPS then return end
	if !GAMEMODE:InRound() then return end
	if !pl.ph_prop || !pl.ph_prop:IsValid() then return end

	local charges = pl.ph_decoy_charges or 0
	if charges <= 0 then return end

	local decoy = ents.Create("ph_decoy")
	if !IsValid(decoy) then return end

	decoy:Spawn()
	decoy:SetupFromProp(
		pl.ph_prop:GetModel(),
		pl.ph_prop:GetSkin(),
		pl.ph_prop:OBBMins(),
		pl.ph_prop:OBBMaxs(),
		pl.ph_prop:GetPos(),
		pl.ph_prop:GetAngles()
	)

	pl.ph_decoys = pl.ph_decoys or {}
	table.insert(pl.ph_decoys, decoy)

	pl.ph_decoy_charges = charges - 1
	pl:SetNWInt("PH_DecoyCharges", pl.ph_decoy_charges)
end)

-- Activates the liquid trail power-up: for LIQUID_TRAIL_ACTIVE_TIME seconds,
-- drops a ph_liquid_trail puddle segment at the player's position every
-- LIQUID_TRAIL_SEGMENT_INTERVAL seconds. Any Hunter that steps in a segment
-- gets ragdolled (see ph_liquid_trail/init.lua and meta:BecomeRagdoll in
-- sh_player.lua). One repeating timer per player, keyed by EntIndex so it
-- can't collide with another player's - stopped early via
-- meta:StopLiquidTrail() on death/disconnect, or naturally once the active
-- window ends.
net.Receive("PH_ActivateLiquidTrail", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_PROPS then return end
	if !GAMEMODE:InRound() then return end
	if pl.ph_liquid_trail_active then return end -- already trailing, ignore repeat presses

	local charges = pl.ph_liquid_charges or 0
	if charges <= 0 then return end

	pl.ph_liquid_charges = charges - 1
	pl:SetNWInt("PH_LiquidCharges", pl.ph_liquid_charges)

	pl.ph_liquid_trail_active = true
	local endTime = CurTime() + LIQUID_TRAIL_ACTIVE_TIME
	pl:SetNWFloat("PH_LiquidTrailEndTime", endTime)

	timer.Create("PH_LiquidTrail_" .. pl:EntIndex(), LIQUID_TRAIL_SEGMENT_INTERVAL, 0, function()
		if !IsValid(pl) or !pl:Alive() or CurTime() >= endTime then
			timer.Remove("PH_LiquidTrail_" .. pl:EntIndex())
			if IsValid(pl) then pl.ph_liquid_trail_active = false end
			return
		end

		local segment = ents.Create("ph_liquid_trail")
		if IsValid(segment) then
			segment:SetPos(pl:GetPos())
			segment:SetOwner(pl)
			segment:Spawn()
		end
	end)
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

-- ===========================================================================
-- Hunter player model handling
--
-- The hunter model menu (client) sends the model's actual file path rather
-- than a short registry key - this lets it cover BOTH officially registered
-- models (player_manager.AllValidModels(), used for default GMod models and
-- well-behaved workshop packs) AND workshop playermodel packs that just drop
-- .mdl files under models/player/ without registering themselves. A path is
-- validated directly against the server's own mounted content instead.
-- ===========================================================================

local DEFAULT_HUNTER_MODEL = player_manager.AllValidModels()["combine"] or "models/police.mdl"

local function IsValidHunterModelPath(modelPath)
	if !modelPath or modelPath == "" then return false end
	if not string.StartWith(modelPath, "models/") then return false end
	if not string.EndsWith(string.lower(modelPath), ".mdl") then return false end
	if not file.Exists(modelPath, "GAME") then return false end
	return true
end

-- Registered models are keyed by short name -> path; hand models/skins are only
-- resolvable via that same short name, so if a chosen path happens to match a
-- registered model, resolve its key for correct matching hands. Anything found
-- only via filesystem scan (unregistered workshop packs) falls back to generic
-- hands rather than erroring out.
local function FindRegisteredKeyForPath(modelPath)
	local models = player_manager.AllValidModels()
	for key, path in pairs(models) do
		if path == modelPath then return key end
	end
	return nil
end

-- Rebuilds a player's first-person view hands to match a given player model
-- path. Shared between initial spawn and a live hunter model change so the
-- hands never end up mismatched with the body model.
local function UTIL_RefreshPlayerHands(pl, modelPath)
	local oldhands = pl:GetHands()
	if ( IsValid( oldhands ) ) then oldhands:Remove() end

	local hands = ents.Create( "gmod_hands" )
	if ( IsValid( hands ) ) then
		pl:SetHands( hands )
		hands:SetOwner( pl )

		local handsKey = modelPath and (FindRegisteredKeyForPath(modelPath) or "citizen_male") or pl:GetInfo( "cl_playermodel" )
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
-- updates the visible body model, the networked path (so it persists across
-- spawns/rounds and matches on reconnect), and the first-person hands to match.
local function UTIL_ApplyHunterModel(pl, modelPath)
	if !IsValidHunterModelPath(modelPath) then return false end

	pl:SetNWString("PH_HunterModel", modelPath)
	util.PrecacheModel(modelPath)
	pl:SetModel(modelPath)
	UTIL_RefreshPlayerHands(pl, modelPath)
	return true
end

net.Receive("PH_SetHunterModel", function(len, pl)
	if !IsValid(pl) || !pl:Alive() || pl:Team() != TEAM_HUNTERS then return end

	local modelPath = net.ReadString()
	if !modelPath or modelPath == "" then return end

	UTIL_ApplyHunterModel(pl, modelPath)
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
		local stored = pl:GetNWString("PH_HunterModel", "")
		if IsValidHunterModelPath(stored) then
			player_model = stored
		else
			player_model = DEFAULT_HUNTER_MODEL
		end
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

			-- Solid + hittable by bullet traces. COLLISION_GROUP_NONE (the same
			-- group an ordinary shootable world prop uses) rather than a "special"
			-- collision group - PASSABLE_DOOR and WEAPON were both tried here
			-- previously and neither could be confirmed safe against every weapon/
			-- trace type; some collision groups are specifically defined to be
			-- invisible to damage traces, not just physics push resolution. Not
			-- physically blocking player movement is instead handled entirely via
			-- GM:ShouldCollide in sh_player.lua, which only affects physics
			-- collision response, never trace-based hit detection.
			--
			-- SOLID_OBB_YAW (not SOLID_BBOX!) matters here too: SOLID_BBOX is a
			-- fixed axis-aligned box that does NOT rotate with the entity's angle,
			-- so once a prop got rotated (either the "stand upright" facing fix,
			-- or the player-controlled hold-R rotation), the visible mesh would
			-- turn but the invisible collision box stayed frozen at its original
			-- orientation - shots at the visible model would miss the misaligned
			-- hitbox entirely. SOLID_OBB_YAW rotates with yaw, which matches these
			-- props exactly (always upright, yaw-only rotation).
			--
			-- IMPORTANT: SetCollisionBounds() on a solid type other than
			-- SOLID_VPHYSICS does not reliably force the engine to recompute the
			-- collision shape actually used by traces on a LIVE entity - without
			-- calling Activate() afterward, the entity kept using whatever bounds
			-- were set at creation (the small default placeholder hull) even after
			-- SetCollisionBounds was called again here with the new prop's real
			-- size, so the hitbox stayed feet-sized no matter what was picked up.
			pl.ph_prop:SetCollisionBounds(obbmins, obbmaxs)
			pl.ph_prop:SetSolid(SOLID_OBB_YAW)
			pl.ph_prop:SetCollisionGroup(COLLISION_GROUP_NONE)
			pl.ph_prop:SetMoveType(MOVETYPE_NONE)
			pl.ph_prop:Activate()

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
	pl:RemoveDecoy()
	pl:StopLiquidTrail()
	pl:ClearRagdoll()
end
hook.Add("PlayerDisconnected", "PH_PlayerDisconnected", PlayerDisconnected)

hook.Add("PlayerTick", "PH_UpdatePropPosition", function(pl, mv)
	if !IsValid(pl) or pl:Team() != TEAM_PROPS or !pl:Alive() then return end
	if !pl.ph_prop or !IsValid(pl.ph_prop) then return end

	if pl.WallSticking and pl.WallNormal then
		-- Flush-mount the disguised prop against the wall it's stuck to: push
		-- it out along the wall's normal by roughly the prop's own depth (so
		-- it sits on the wall surface rather than clipping through it), and
		-- orient it so its "up" faces away from the wall (lying flush against
		-- it, like a wall-mounted decoration).
		local normal = pl.WallNormal
		local mins = pl.ph_prop:OBBMins()
		local maxs = pl.ph_prop:OBBMaxs()
		local depth = math.max(math.abs(mins.x), math.abs(maxs.x), math.abs(mins.y), math.abs(maxs.y))
		pl.ph_prop:SetPos(pl:GetPos() + normal * depth)

		local ang = normal:Angle()
		pl.ph_prop:SetAngles(Angle(ang.p - 90, ang.y, 0))
	else
		local z = pl.ph_prop:OBBMins().z
		if z > 0 then z = 0 end
		pl.ph_prop:SetPos(pl:GetPos() - Vector(0, 0, z))
	end
end)


-- Called when the players spawns
function PlayerSpawn(pl)

	local handsPath = nil
	if pl:Team() == TEAM_HUNTERS then
		local stored = pl:GetNWString("PH_HunterModel", "")
		if not IsValidHunterModelPath(stored) then
			stored = DEFAULT_HUNTER_MODEL
			pl:SetNWString("PH_HunterModel", stored)
		end
		handsPath = stored
	end
	UTIL_RefreshPlayerHands(pl, handsPath)

	pl:Blind(false)
	pl:RemoveProp()
	pl:SetColor( Color(255, 255, 255, 255))
	pl:SetRenderMode( RENDERMODE_TRANSALPHA )
	pl:UnLock()
	pl:ResetHull()
	pl.last_taunt_time = 0
	
	umsg.Start("ResetHull", pl)
	umsg.End()
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

	-- Decoys and liquid trail puddles are per-life and shouldn't survive
	-- into a new round. This is a belt-and-suspenders map-wide sweep on top
	-- of meta:RemoveDecoy()/meta:StopLiquidTrail() (which only catch a
	-- specific player's own stuff on death/disconnect) - it also catches
	-- anything that slipped through, e.g. a mid-round map change.
	for _, decoy in pairs(ents.FindByClass("ph_decoy")) do
		decoy:Remove()
	end
	for _, puddle in pairs(ents.FindByClass("ph_liquid_trail")) do
		puddle:Remove()
	end

	-- Any Hunter still ragdolled from a liquid trail when a new round starts
	-- gets restored immediately rather than staying frozen/hidden into the
	-- next round.
	for _, pl in pairs(team.GetPlayers(TEAM_HUNTERS)) do
		pl:ClearRagdoll()
	end
	
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
