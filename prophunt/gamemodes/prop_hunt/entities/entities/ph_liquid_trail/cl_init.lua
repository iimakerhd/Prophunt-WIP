include("shared.lua")


-- Rendered manually as a glowing green quad on the ground rather than the
-- placeholder model (see init.lua) - a pure engine sprite material, so it
-- has no dependency on any mounted content. This is deliberately visible to
-- everyone (not hidden from Hunters) - a fair, spottable hazard rather than
-- an invisible trap.
local TRAIL_MATERIAL = Material("sprites/glow04_noz")
local QUAD_SIZE = 48

function ENT:Draw()
	local pos = self:GetPos() + Vector(0, 0, 1)

	render.SetMaterial(TRAIL_MATERIAL)
	render.DrawQuadEasy(pos, Vector(0, 0, 1), QUAD_SIZE, QUAD_SIZE, Color(80, 220, 80, 160), 0)
end
