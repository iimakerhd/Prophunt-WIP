-- Send required files to client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")


-- Include needed files
include("shared.lua")


-- Called when the entity initializes. Model/skin/angles are set right after
-- creation by whoever spawns the decoy (see PH_DropDecoy in gamemode/init.lua) -
-- this just sets up sane defaults plus the solid/collision configuration.
function ENT:Initialize()
	self:SetModel("models/player/Kleiner.mdl")

	-- Reuses the exact solid/collision setup ph_prop needed many iterations to
	-- get right (see the long comment trail in ph_prop/init.lua):
	--   - SOLID_OBB_YAW (not SOLID_BBOX) so the collision box rotates with the
	--     entity's yaw, matching its always-upright visible orientation.
	--   - COLLISION_GROUP_NONE (not WEAPON/PASSABLE_DOOR) so it's unambiguously
	--     hittable by every weapon/trace type, same as any ordinary world prop.
	--   - MOVETYPE_NONE since this entity never moves once dropped.
	--   - Activate() after SetCollisionBounds, required for non-VPHYSICS solid
	--     types to actually pick up new bounds on a live entity.
	self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 72))
	self:SetSolid(SOLID_OBB_YAW)
	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetMoveType(MOVETYPE_NONE)
	self:Activate()
end


-- Applies the current disguise (model, skin, size, position, angle) to this
-- decoy at the moment it's dropped. Called once, right after ents.Create.
function ENT:SetupFromProp(model, skin, obbmins, obbmaxs, pos, ang)
	self:SetModel(model)
	self:SetSkin(skin)
	self:SetCollisionBounds(obbmins, obbmaxs)
	self:Activate()
	self:SetPos(pos)
	self:SetAngles(ang)
end


-- Any hit at all pops the decoy - it's meant to be a one-time trick, not a
-- durable fake. A brief break effect gives the hunter clear feedback that
-- they hit something (rather than the object just silently vanishing, which
-- would be confusing rather than satisfying).
function ENT:OnTakeDamage(dmg)
	if dmg:GetDamage() <= 0 then return end

	local edata = EffectData()
	edata:SetOrigin(self:GetPos())
	edata:SetModel(self:GetModel())
	util.Effect("BreakModel", edata)

	self:EmitSound("physics/glass/glass_impact_bullet3.wav", 75, 100)

	self:Remove()
end
