-- Include needed files
include("shared.lua")


function ENT:Initialize()
	-- Enable a per-frame client think so this entity's visible position can be
	-- smoothed independently of its normal networked updates (see Think below).
	self:SetNextClientThink(CurTime())
end


-- Purely cosmetic position smoothing. ph_prop's real, authoritative position is
-- still set server-side every tick (PH_UpdatePropPosition in gamemode/init.lua) -
-- that copy is what bullet traces/collision actually use, so hit registration is
-- unaffected by anything here. The problem this fixes is visual only: a plain
-- networked entity gets standard interpolation smoothing on top of its already
-- slightly-delayed server updates, so it visibly trails behind its owner while
-- moving. Actual players get more specialized movement networking that doesn't
-- have this same lag. Re-snapping the client's own copy of ph_prop's position to
-- match its owner every single rendered frame - rather than waiting on ph_prop's
-- own network updates - makes it track the owner exactly as smoothly as the
-- owner itself appears to move on screen.
function ENT:Think()
	local owner = self:GetOwner()
	if IsValid(owner) then
		local mins = self:OBBMins()
		local z = mins.z
		if z > 0 then z = 0 end
		self:SetPos(owner:GetPos() - Vector(0, 0, z))
	end

	self:SetNextClientThink(CurTime())
	return true
end


-- Called every frame?
function ENT:Draw()
	self.Entity:DrawModel()
end 
