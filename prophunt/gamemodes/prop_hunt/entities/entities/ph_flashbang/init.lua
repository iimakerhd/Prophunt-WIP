-- Send required files to client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")


-- Include needed files
include("shared.lua")


-- Fixed time-to-detonate after being thrown, regardless of whether it's hit
-- anything yet - simpler and more predictable than trying to detect a "first
-- bounce" like a real flashbang, and avoids edge cases where a throw down a
-- vent or into open space would never register an impact at all.
local FUSE_TIME = 1.5


function ENT:Initialize()
	self:SetModel("models/Weapons/w_grenade.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
		phys:SetMass(5)
	end

	self.DetonateAt = CurTime() + FUSE_TIME
	self:NextThink(CurTime())
end


function ENT:Think()
	if CurTime() >= self.DetonateAt then
		self:Detonate()
		return
	end

	self:NextThink(CurTime())
	return true
end


-- Blinds every Hunter within FLASHBANG_RADIUS that has a clear line of sight
-- to the pop, on a linear falloff from FLASHBANG_DURATION (point-blank) down
-- to a 1-second floor (edge of radius). Only calls pl:Blind() - deliberately
-- never pl:Lock() (the same function used for the round-start blindlock,
-- which also freezes movement) - this is meant to disorient a Hunter's view,
-- not stun-lock them in place. Line of sight is a straight world/brush trace
-- from the pop to the Hunter's eyes; anything solid between them (a wall, a
-- door) blocks the effect entirely rather than reducing it.
--
-- This runs on the SERVER (init.lua) - the effect/sound/gameplay logic below
-- is all server-safe, but DynamicLight() is a CLIENT-ONLY function and was
-- being called unconditionally, crashing this on dedicated/listen servers
-- the instant a flashbang detonated. util.Effect() networks itself to
-- nearby clients automatically, so a lightweight PH_FlashbangPop broadcast
-- is used just to trigger the actual light client-side.
function ENT:Detonate()
	local origin = self:GetPos()

	local edata = EffectData()
	edata:SetOrigin(origin)
	edata:SetMagnitude(1)
	edata:SetScale(1)
	util.Effect("Sparks", edata)

	net.Start("PH_FlashbangPop")
		net.WriteVector(origin)
	net.Broadcast()

	-- Stock HL2 sound - placeholder "pop" until/unless a dedicated flashbang
	-- sound is added to the addon's own content folder.
	self:EmitSound("ambient/explosions/explode_5.wav", 110, 180)
	util.ScreenShake(origin, 4, 4, 0.5, FLASHBANG_RADIUS)

	for _, pl in pairs(team.GetPlayers(TEAM_HUNTERS)) do
		if !IsValid(pl) or !pl:Alive() then continue end

		local dist = origin:Distance(pl:EyePos())
		if dist > FLASHBANG_RADIUS then continue end

		local tr = util.TraceLine({
			start = origin,
			endpos = pl:EyePos(),
			filter = self,
			mask = MASK_SOLID_BRUSHONLY
		})
		if tr.Hit then continue end -- blocked by a wall/door - no line of sight, no effect

		local falloff = 1 - (dist / FLASHBANG_RADIUS)
		local duration = math.max(1, FLASHBANG_DURATION * falloff)

		pl:Blind(true)
		timer.Simple(duration, function()
			if IsValid(pl) then
				pl:Blind(false)
			end
		end)
	end

	self:Remove()
end
