-- Send required files to client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")


-- Include needed files
include("shared.lua")


local BOUNDS_MIN = Vector(-24, -24, -4)
local BOUNDS_MAX = Vector(24, 24, 12)


-- Called when the entity initializes. Position is set right after creation
-- by whoever spawns it (see PH_ActivateLiquidTrail in gamemode/init.lua).
function ENT:Initialize()
	-- Never actually drawn - see cl_init.lua's Draw(), which renders a
	-- glowing yellow liquid-puddle sprite instead. Kleiner is reused purely
	-- as a guaranteed-valid, always-present model for collision setup, same
	-- placeholder choice already made in ph_decoy/init.lua.
	self:SetModel("models/player/Kleiner.mdl")
	self:SetCollisionBounds(BOUNDS_MIN, BOUNDS_MAX)
	self:SetSolid(SOLID_BBOX)
	self:SetTrigger(true) -- fires Touch callbacks without physically blocking anyone
	self:SetMoveType(MOVETYPE_NONE)
	self:SetCollisionGroup(COLLISION_GROUP_WORLD)
	self:Activate()

	-- Overriding Draw() (cl_init.lua) only replaces the entity's main
	-- render pass - it does NOT stop the engine's separate dynamic-shadow
	-- pass, which still runs off the underlying model regardless. Without
	-- this, every "invisible" puddle segment was silently casting a
	-- Kleiner-shaped shadow on the ground underneath it.
	self:DrawShadow(false)

	-- Self-removes once its lifetime is up, regardless of whether it's ever
	-- touched - a trap that's still sitting there minutes later would be
	-- more clutter than hazard.
	SafeRemoveEntityDelayed(self, LIQUID_TRAIL_SEGMENT_LIFETIME)
end


-- Ragdolls any Hunter that steps into this puddle. Fires once per entry
-- (StartTouch, not the continuous Touch) so standing in a lingering puddle
-- doesn't re-trigger every tick - and in practice it can't anyway, since the
-- Hunter is frozen/hidden the instant this fires (meta:BecomeRagdoll).
function ENT:StartTouch(other)
	if !IsValid(other) or !other:IsPlayer() then return end
	if other:Team() != TEAM_HUNTERS or !other:Alive() then return end
	if other.ph_ragdolled then return end

	other:BecomeRagdoll(LIQUID_TRAIL_RAGDOLL_TIME)
end
