-- Send required files to client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")


-- Include needed files
include("shared.lua")


-- Called when the entity initializes
function ENT:Initialize()
	self:SetModel("models/player/Kleiner.mdl")
	self.health = 100

	-- Solid + hittable by bullet traces. This entity previously used
	-- SetNotSolid(true), which meant hitscan bullets could never register a hit
	-- on it at all - only explosive/radius damage (grenades, rockets) worked,
	-- since that doesn't rely on a trace actually hitting a solid entity.
	--
	-- SOLID_OBB_YAW (not SOLID_BBOX) matters: SOLID_BBOX is a fixed axis-aligned
	-- box that does NOT rotate with the entity's angle, so a rotated prop's
	-- visible mesh and its actual (frozen, unrotated) collision box would drift
	-- apart, making shots at the visible model miss. SOLID_OBB_YAW rotates with
	-- yaw, matching these props (always upright, yaw-only rotation).
	--
	-- COLLISION_GROUP_NONE (not WEAPON/PASSABLE_DOOR) matters too: several
	-- "special" collision groups are specifically defined to be invisible to
	-- weapon damage traces, not just physics push resolution - two were already
	-- tried here and silently broke bullet hit registration. NONE is the same
	-- group an ordinary shootable world prop uses, so it's unambiguously
	-- hittable by everything. "Don't physically block player movement" is
	-- instead handled entirely via GM:ShouldCollide in sh_player.lua, which only
	-- affects physics collision response, never trace-based hit detection.
	self:SetSolid(SOLID_OBB_YAW)
	self:SetCollisionBounds(self:OBBMins(), self:OBBMaxs())
	self:SetCollisionGroup(COLLISION_GROUP_NONE)
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
