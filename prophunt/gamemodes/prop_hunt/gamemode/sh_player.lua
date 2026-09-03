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


-- Stops this player's active liquid trail (see PH_ActivateLiquidTrail in
-- gamemode/init.lua), if they have one running. Safe to call unconditionally.
function meta:StopLiquidTrail()
	if CLIENT || !self:IsValid() then return end

	timer.Remove("PH_LiquidTrail_" .. self:EntIndex())
	self.ph_liquid_trail_active = false
end


-- Puts a Hunter into a temporary physics ragdoll for `duration` seconds.
--
-- IMPORTANT CAVEAT: this is an approximation, not true player-to-ragdoll
-- possession. GMod has no built-in way to hand a live player's actual body
-- over to physics simulation. What this does instead: freeze the real player
-- (meta:Lock(), same freeze already used for the round-start hunter blindlock)
-- and hide them (SetNoDraw), then spawn a SEPARATE prop_ragdoll using their
-- model at their current position/angles and give it a shove so it flops
-- believably. The player's own hitbox/collision stays exactly where they were
-- frozen - it does NOT follow the ragdoll around as it settles - and on
-- recovery the player is teleported to wherever the ragdoll ended up, so they
-- don't feel disconnected from what they just watched happen. Client view
-- during this is hijacked in gamemode/cl_init.lua (GM:CalcView) to hover over
-- the ragdoll rather than stay at the frozen, hidden real body.
function meta:BecomeRagdoll(duration)
	if CLIENT || !self:IsValid() || !self:Alive() then return end
	if self.ph_ragdolled then return end -- already down, don't restack/duplicate

	self.ph_ragdolled = true
	self:Lock()
	self:SetNoDraw(true)

	local rag = ents.Create("prop_ragdoll")
	rag:SetModel(self:GetModel())
	rag:SetPos(self:GetPos())
	rag:SetAngles(self:GetAngles())
	rag:Spawn()
	rag:Activate()

	local phys = rag:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(self:GetVelocity())
	end

	self.ph_ragdoll_ent = rag
	self:SetNWBool("PH_Ragdolled", true)
	self:SetNWEntity("PH_RagdollEnt", rag)

	local victim = self
	timer.Simple(duration, function()
		if !IsValid(victim) then
			if IsValid(rag) then rag:Remove() end
			return
		end

		victim:ClearRagdoll()
	end)
end


-- Restores a player from BecomeRagdoll(), early or after its timer expires.
-- Safe to call even if the player was never ragdolled (used defensively on
-- death/disconnect for both teams) - it's a no-op unless ph_ragdolled is set.
function meta:ClearRagdoll()
	if CLIENT || !self:IsValid() then return end
	if !self.ph_ragdolled then return end

	local rag = self.ph_ragdoll_ent
	if IsValid(rag) then
		self:SetPos(rag:GetPos())
		rag:Remove()
	end

	self.ph_ragdolled = false
	self.ph_ragdoll_ent = nil
	self:SetNoDraw(false)
	self:UnLock()
	self:SetNWBool("PH_Ragdolled", false)
	self:SetNWEntity("PH_RagdollEnt", NULL)
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
