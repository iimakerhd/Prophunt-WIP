include("shared.lua")


function ENT:Draw()
	self:DrawModel()
end


-- DynamicLight() is client-only, so the actual light flash is created here,
-- triggered by a small broadcast from ENT:Detonate() (init.lua, server-side)
-- rather than being created directly inside Detonate() itself - that used
-- to crash the server the instant a flashbang went off.
net.Receive("PH_FlashbangPop", function()
	local origin = net.ReadVector()

	local dlight = DynamicLight(LocalPlayer():EntIndex())
	if dlight then
		dlight.pos = origin
		dlight.r = 255
		dlight.g = 255
		dlight.b = 255
		dlight.brightness = 6
		dlight.decay = 1000
		dlight.size = 500
		dlight.dietime = CurTime() + 0.6
	end
end)
