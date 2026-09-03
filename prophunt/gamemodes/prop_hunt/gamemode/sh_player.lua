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


-- Removes any decoys this player currently has placed. A player can hold
-- multiple live decoys at once (one per drop, up to DECOY_CHARGES_PER_LIFE),
-- so this tracks them as a list rather than a single entity like ph_prop -
-- otherwise dropping a second decoy would orphan the first one instead of
-- cleaning it up here.
function meta:RemoveDecoy()
	if CLIENT || !self:IsValid() then return end

	if !self.ph_decoys then return end

	for _, decoy in ipairs(self.ph_decoys) do
		if IsValid(decoy) then
			decoy:Remove()
		end
	end

	self.ph_decoys = {}
end


-- Neither players nor disguised props should physically shove each other around
-- (a hunter walking into a hiding prop shouldn't push it out of place), but this
-- MUST be done via GM:ShouldCollide rather than SetCollisionGroup. Two collision
-- group choices were already tried and rejected here for the same underlying
-- reason - some collision groups are specifically defined to be invisible to
-- weapon damage traces, not just physics push resolution, which silently broke
-- bullet hit registration on ph_prop entirely:
--   - COLLISION_GROUP_PASSABLE_DOOR: meant for doors mid-swing so gunfire isn't
--     blocked by an opening door - exempts the entity from hitscan traces too.
--   - COLLISION_GROUP_WEAPON: meant for dropped weapons not blocking foot
--     traffic - could not be confirmed safe against every weapon/trace type.
-- ph_prop now uses COLLISION_GROUP_NONE (the same group as an ordinary shootable
-- world prop - guaranteed hittable by anything), and "walk through it" is
-- achieved purely through ShouldCollide below, which only affects physics
-- collision RESPONSE (pushing/blocking), never bullet trace hit DETECTION.
hook.Add("ShouldCollide", "PH_PlayersDontPhysicallyCollide", function(ent1, ent2)
	if ent1:IsPlayer() and ent2:IsPlayer() then
		return false
	end

	if (ent1:IsPlayer() and IsValid(ent2) and ent2:GetClass() == "ph_prop")
	or (ent2:IsPlayer() and IsValid(ent1) and ent1:GetClass() == "ph_prop") then
		return false
	end
end)
