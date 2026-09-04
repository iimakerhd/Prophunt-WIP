include("shared.lua")


-- Rendered manually rather than the placeholder model (see init.lua) - pure
-- engine sprite materials, so there's no dependency on any mounted content.
-- Deliberately visible to everyone (not hidden from Hunters) - a fair,
-- spottable hazard rather than an invisible trap.
--
-- Two overlapping layers give it a wet/liquid look rather than a flat
-- colored dot: a larger, soft, low-opacity OUTER glow (the puddle's spread)
-- plus a smaller, brighter, more opaque INNER core (where the liquid is
-- thickest) - and each segment's size subtly pulses over time (offset by
-- its EntIndex, so segments don't all pulse in lockstep) for a faint shimmer
-- rather than a static, obviously-a-sprite look. Segments are also spawned
-- closer together than they are wide (LIQUID_TRAIL_SEGMENT_INTERVAL in
-- sh_config.lua), so consecutive ones overlap into a continuous trail rather
-- than a line of separate dots.
local OUTER_MATERIAL = Material("sprites/glow04_noz")
local INNER_MATERIAL = Material("sprites/glow04_noz")
local OUTER_SIZE = 72
local INNER_SIZE = 34
local OUTER_COLOR = Color(235, 200, 30, 110)
local INNER_COLOR = Color(255, 235, 90, 200)

function ENT:Draw()
	local pos = self:GetPos() + Vector(0, 0, 1)
	local pulse = 1 + math.sin(CurTime() * 3 + self:EntIndex()) * 0.08

	render.SetMaterial(OUTER_MATERIAL)
	render.DrawQuadEasy(pos, Vector(0, 0, 1), OUTER_SIZE * pulse, OUTER_SIZE * pulse, OUTER_COLOR, 0)

	render.SetMaterial(INNER_MATERIAL)
	render.DrawQuadEasy(pos + Vector(0, 0, 0.1), Vector(0, 0, 1), INNER_SIZE * pulse, INNER_SIZE * pulse, INNER_COLOR, 0)
end
