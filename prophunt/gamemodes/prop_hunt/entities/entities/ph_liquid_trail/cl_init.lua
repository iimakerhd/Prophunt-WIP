include("shared.lua")


-- Rendered manually rather than the placeholder model (see init.lua) - pure
-- engine sprite/beam materials, so there's no dependency on any mounted
-- content. Deliberately visible to everyone (not hidden from Hunters) - a
-- fair, spottable hazard rather than an invisible trap.
--
-- Two things combine into an actual continuous spill look, rather than a
-- chain of separate glowing dots:
--   1. A BEAM connecting this segment back to the previous one it was
--      spawned after (PH_PrevPos/PH_HasPrev, set server-side in
--      gamemode/init.lua right when each segment is created) - this is what
--      makes it read as one continuous stream rather than isolated blobs no
--      matter how far apart consecutive drops land.
--   2. A small glow "puddle" at each drop point on top of that, so the path
--      still has some visual thickness/pooling at each step rather than
--      being a perfectly uniform ribbon.
-- Both pulse gently over time (offset by EntIndex so segments don't all
-- pulse in lockstep) for a faint shimmer rather than a static, obviously-a-
-- sprite look.
local BEAM_MATERIAL = Material("sprites/glow04_noz")
local POOL_MATERIAL = Material("sprites/glow04_noz")
local BEAM_WIDTH = 30
local POOL_SIZE = 40
local BEAM_COLOR = Color(255, 220, 40, 180)
local POOL_COLOR = Color(255, 235, 90, 210)

function ENT:Draw()
	local pos = self:GetPos() + Vector(0, 0, 1)
	local pulse = 1 + math.sin(CurTime() * 3 + self:EntIndex()) * 0.08

	if self:GetNWBool("PH_HasPrev", false) then
		local prevPos = self:GetNWVector("PH_PrevPos", pos) + Vector(0, 0, 1)

		render.SetMaterial(BEAM_MATERIAL)
		render.DrawBeam(prevPos, pos, BEAM_WIDTH * pulse, 0, 1, BEAM_COLOR)
	end

	render.SetMaterial(POOL_MATERIAL)
	render.DrawQuadEasy(pos, Vector(0, 0, 1), POOL_SIZE * pulse, POOL_SIZE * pulse, POOL_COLOR, 0)
end
