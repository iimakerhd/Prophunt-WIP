include("shared.lua")


-- Decoys are static dressed-up props - draw them exactly like their real
-- model, no special effects needed while they're standing (OnTakeDamage in
-- init.lua handles the break effect for when they get shot).
function ENT:Draw()
	self:DrawModel()
end
