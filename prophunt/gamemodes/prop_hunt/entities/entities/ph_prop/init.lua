-- Send required files to client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")


-- Include needed files
include("shared.lua")


-- Called when the entity initializes
function ENT:Initialize()
	self:SetModel("models/player/Kleiner.mdl")
	self.health = 100

	-- Solid + hittable by bullet traces, but COLLISION_GROUP_WEAPON means it
	-- won't physically block player movement (same as a dropped weapon on the
	-- ground), and MOVETYPE_NONE keeps it out of the physics simulation since
	-- its position is driven manually every tick (see PH_UpdatePropPosition in
	-- gamemode/init.lua) rather than by vphysics. This entity previously used
	-- SetNotSolid(true), which meant hitscan bullets could never register a hit
	-- on it at all - only explosive/radius damage (grenades, rockets) worked,
	-- since that doesn't rely on a trace actually hitting a solid entity.
	--
	-- SOLID_OBB_YAW (not SOLID_BBOX) matters: SOLID_BBOX is a fixed axis-aligned
	-- box that does NOT rotate with the entity's angle, so a rotated prop's
	-- visible mesh and its actual (frozen, unrotated) collision box would drift
	-- apart, making shots at the visible model miss. SOLID_OBB_YAW rotates with
	-- yaw, matching these props (always upright, yaw-only rotation).
	self:SetSolid(SOLID_OBB_YAW)
	self:SetCollisionBounds(self:OBBMins(), self:OBBMaxs())
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	self:SetMoveType(MOVETYPE_NONE)
end 


-- Called when we take damge
function ENT:OnTakeDamage(dmg)
	local pl = self:GetOwner()
	local attacker = dmg:GetAttacker()
	local inflictor = dmg:GetInflictor()

	-- Health
	if pl && pl:IsValid() && pl:Alive() && pl:IsPlayer() && attacker:IsPlayer() && dmg:GetDamage() > 0 then
		self.health = self.health - dmg:GetDamage()
		pl:SetHealth(self.health)
		
		if self.health <= 0 then
			pl:KillSilent()
			
			if inflictor && inflictor == attacker && inflictor:IsPlayer() then
				inflictor = inflictor:GetActiveWeapon()
				if !inflictor || inflictor == NULL then inflictor = attacker end
			end
			
			net.Start( "PlayerKilledByPlayer" )
		
			net.WriteEntity( pl )
			net.WriteString( inflictor:GetClass() )
			net.WriteEntity( attacker )
		
			net.Broadcast()

	
			MsgAll(attacker:Name() .. " found and killed " .. pl:Name() .. "\n") 
			
			attacker:AddFrags(1)
			pl:AddDeaths(1)
			attacker:SetHealth(math.Clamp(attacker:Health() + HUNTER_KILL_BONUS, 1, 100))
			
			pl:RemoveProp()
		end
	end
end
