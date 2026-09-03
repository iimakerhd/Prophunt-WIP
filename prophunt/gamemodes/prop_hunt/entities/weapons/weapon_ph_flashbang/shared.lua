-- Custom ammo type for this weapon's charge pool. Registered here (rather
-- than in gamemode/init.lua) so this weapon file is the single source of
-- truth for it - it must be added identically on both realms for ammo
-- counts to stay in sync, which is guaranteed here since this shared.lua is
-- included by both init.lua (server) and cl_init.lua (client).
if game.GetAmmoID("PHFlashbang") <= 0 then
	game.AddAmmoType({
		name = "PHFlashbang",
		dmgtype = DMG_GENERIC,
		tracer = 0,
		plydmg = 0,
		npcdmg = 0,
		force = 0,
		minsplash = 0,
		maxsplash = 0
	})
end


SWEP.PrintName = "Flashbang"
SWEP.Author = "Prop Hunt"
SWEP.Category = "Prop Hunt"
SWEP.Purpose = "Throw to blind nearby Hunters in line of sight for a few seconds. Doesn't affect their movement."
SWEP.Spawnable = false
SWEP.AdminOnly = false

SWEP.Base = "weapon_base"
SWEP.HoldType = "grenade"

SWEP.ViewModel = "models/weapons/v_grenade.mdl"
SWEP.WorldModel = "models/Weapons/w_grenade.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = 0
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "PHFlashbang"
SWEP.Primary.Delay = 1

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 5
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = true


function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end


-- No prediction - server is the sole authority on spawning the projectile
-- and consuming ammo, matching the "no net prediction" approach already used
-- elsewhere in this addon (e.g. PH_DropDecoy) rather than fighting GMod's
-- weapon prediction system for a low-frequency, non-twitch action.
function SWEP:PrimaryAttack()
	local owner = self:GetOwner()

	-- Prop-only. Loadout (class_prop.lua) is the primary gate - this is a
	-- second line of defense in case a Hunter somehow ends up holding one
	-- (e.g. a console give command).
	if !IsValid(owner) or !owner:IsPlayer() or owner:Team() != TEAM_PROPS then
		return
	end

	if owner:GetAmmoCount(self.Primary.Ammo) <= 0 then
		self:EmitSound("weapons/pistol/pistol_empty.wav")
		return
	end

	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	if CLIENT then return end

	owner:RemoveAmmo(1, self.Primary.Ammo)

	local proj = ents.Create("ph_flashbang")
	if !IsValid(proj) then return end

	local eyeAng = owner:EyeAngles()
	local throwFrom = owner:EyePos() + eyeAng:Forward() * 16

	proj:SetPos(throwFrom)
	proj:SetAngles(eyeAng)
	proj:SetOwner(owner)
	proj:Spawn()

	local phys = proj:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(eyeAng:Forward() * 900 + eyeAng:Up() * 150)
	end

	owner:ViewPunch(Angle(-2, 0, 0))
end


function SWEP:SecondaryAttack()
	-- No secondary function - a flashbang only does one thing.
end


function SWEP:Reload()
	-- No reload - ammo comes straight from the per-life charge pool
	-- (FLASHBANG_CHARGES_PER_LIFE, set via SetAmmo in class_prop.lua:Loadout).
end
