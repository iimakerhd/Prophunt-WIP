-- Finds the player meta table or terminates
local meta = FindMetaTable("Player")
if !meta then return end


-- Blinds the player by setting view out into the void
function meta:Blind(bool)
	if !self:IsValid() then return end
	
	if SERVER then
		umsg.Start("SetBlind", self)
		if bool then
			umsg.Bool(true)
		else
			umsg.Bool(false)
		end
		umsg.End()
	elseif CLIENT then
		blind = bool
	end
end


-- Blinds the player by setting view out into the void
function meta:RemoveProp()
	if CLIENT || !self:IsValid() then return end
	
	if self.ph_prop && self.ph_prop:IsValid() then
		self.ph_prop:Remove()
		self.ph_prop = nil
	end
end


-- Players shouldn't physically shove each other around (a hunter walking into a
-- hiding prop, or two props overlapping, shouldn't push either one out of place),
-- but this MUST be done via GM:ShouldCollide rather than SetCollisionGroup. An
-- earlier version used pl:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) for
-- this - that group is meant for doors mid-swing so gunfire isn't blocked by an
-- opening door, and it has the side effect of making hitscan bullet traces pass
-- straight through the entity entirely. That meant hunters' bullets never
-- registered damage on props at all, while explosives (grenades/rockets) still
-- worked since blast/radius damage doesn't use the same trace-based hit check.
-- ShouldCollide only affects physics collision resolution, not bullet traces, so
-- it gets the "walk through each other" behaviour without breaking gunfire.
hook.Add("ShouldCollide", "PH_PlayersDontPhysicallyCollide", function(ent1, ent2)
	if ent1:IsPlayer() and ent2:IsPlayer() then
		return false
	end
end)
