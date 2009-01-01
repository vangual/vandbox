if select(6, GetAddOnInfo("PitBull4_" .. (debugstack():match("[o%.][d%.][u%.]les\\(.-)\\") or ""))) ~= "MISSING" then return end

if select(2, UnitClass("player")) ~= "DRUID" then return end

local PitBull4 = _G.PitBull4
if not PitBull4 then
	error("PitBull4_DruidManaBar requires PitBull4")
end

local PitBull4_DruidManaBar = PitBull4:NewModule("DruidManaBar", "AceEvent-3.0", "AceTimer-3.0")

PitBull4_DruidManaBar:SetModuleType("status_bar")
PitBull4_DruidManaBar:SetName("Druid Mana Bar")
PitBull4_DruidManaBar:SetDescription("Show the mana bar when a druid is in cat or bear form.")
PitBull4_DruidManaBar:SetDefaults({
	size = 1,
	position = 6,
})

-- constants
local MANA_TYPE = 0

function PitBull4_DruidManaBar:OnEnable()
		PitBull4_DruidManaBar:RegisterEvent("UNIT_MANA")
		PitBull4_DruidManaBar:RegisterEvent("UNIT_DISPLAYPOWER")
		PitBull4_DruidManaBar:RegisterEvent("UNIT_MAXMANA")
end

function PitBull4_DruidManaBar:GetValue(frame)
	if frame.unit ~= "player" then
		return
	end
    
	if UnitPowerType("player") ~= 0 then
		return UnitPower(frame.unit, MANA_TYPE) / UnitPowerMax(frame.unit, MANA_TYPE)
	else
		return nil
	end
end

function PitBull4_DruidManaBar:GetColor(frame, value)
	local color = PowerBarColor[MANA_TYPE]
	return color.r, color.g, color.b
end

function PitBull4_DruidManaBar:UNIT_MANA(event, arg1)
	if arg1 ~= "player" then
		return
	else
		self:UpdateForUnitID("player")
	end
end

function PitBull4_DruidManaBar:UNIT_DISPLAYPOWER(event, arg1)
	-- return if its not the player.
	if arg1 ~= "player" then
		return
	end
    
	self:UpdateForUnitID("player")
	
end

PitBull4_DruidManaBar.UNIT_MAXMANA = PitBull4_DruidManaBar.UNIT_MANA