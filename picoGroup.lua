
local ldb, ae = LibStub:GetLibrary("LibDataBroker-1.1"), LibStub("AceEvent-3.0")

local loottypes = {freeforall = "FFA", group = "Group", master = "ML", needbeforegreed = "NBG", roundrobin = "RR"}
local raidtypes = {ITEM_QUALITY_COLORS[3].hex.."10", ITEM_QUALITY_COLORS[4].hex.."25", ITEM_QUALITY_COLORS[5].hex.."10H", ITEM_QUALITY_COLORS[5].hex.."25H"}
local dungeontypes = {ITEM_QUALITY_COLORS[2].hex.."5", ITEM_QUALITY_COLORS[3].hex.."5H"}
local icons = {
	tank = "|TInterface\\LFGFrame\\LFGRole.blp:0:0:0:0:64:16:32:47:1:16|t",
	heal = "|TInterface\\LFGFrame\\LFGRole.blp:0:0:0:0:64:16:48:63:1:16|t",
	dps  = "|TInterface\\LFGFrame\\LFGRole.blp:0:0:0:0:64:16:16:31:1:16|t",
	none = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady.blp:0|t"
}
local classcolors = {}
for i,v in pairs(RAID_CLASS_COLORS) do classcolors[i] = string.format("|cff%02x%02x%02x", v.r*255, v.g*255, v.b*255) end
local names = setmetatable({}, {__index = function(t, i)
	if not i then return i end
	local _, class = UnitClass(i)
	if not class then return i end
	local v = classcolors[class].. i
	t[i] = v
	return v
end})

local function GetGroupTypeText()
	return UnitInRaid("player") and (raidtypes[GetRaidDifficulty()].. "|r - ")
		or UnitInParty("player") and (dungeontypes[GetDungeonDifficultyID()].. "|r - ")
		or (ITEM_QUALITY_COLORS[0].hex.."Solo")
end


local function GetLootTypeText()
	return (UnitInRaid("player") or UnitInParty("player")) and (ITEM_QUALITY_COLORS[GetLootThreshold()].hex.. loottypes[GetLootMethod()]) or ""
end


local function GetText()
	if GetLFGMode(LE_LFG_CATEGORY_LFD) == "queued" then
		local _, _, tank, healer, dps, _, instance, _, _, _, _, average, elapsed = GetLFGQueueStats()
		dps = dps or 3

		return "LFG ".. (tank == 0 and icons.tank or icons.none)
			..(healer == 0 and icons.heal or icons.none)
			..(dps    <= 2 and icons.dps  or icons.none)
			..(dps    <= 1 and icons.dps  or icons.none)
			..(dps    == 0 and icons.dps  or icons.none)
	else
		return GetGroupTypeText().. GetLootTypeText()
	end
end


local dataobj = ldb:NewDataObject("picoGroup", {type = "data source", icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", text = GetText()})


local function Update() dataobj.text = GetText() end
ae.RegisterEvent("picoGroup", "PARTY_CONVERTED_TO_RAID", Update)
ae.RegisterEvent("picoGroup", "GROUP_ROSTER_UPDATE", Update)
ae.RegisterEvent("picoGroup", "PARTY_MEMBERS_CHANGED", Update)
ae.RegisterEvent("picoGroup", "PARTY_LOOT_METHOD_CHANGED", Update)
ae.RegisterEvent("picoGroup", "LFG_UPDATE", Update)
ae.RegisterEvent("picoGroup", "LFG_QUEUE_STATUS_UPDATE", Update)


------------------------
--      Tooltip!      --
------------------------

local function GetTipAnchor(frame)
	local x,y = frame:GetCenter()
	if not x or not y then return "TOPLEFT", "BOTTOMLEFT" end
	local hhalf = (x > UIParent:GetWidth()*2/3) and "RIGHT" or (x < UIParent:GetWidth()/3) and "LEFT" or ""
	local vhalf = (y > UIParent:GetHeight()/2) and "TOP" or "BOTTOM"
	return vhalf..hhalf, frame, (vhalf == "TOP" and "BOTTOM" or "TOP")..hhalf
end


function dataobj.OnLeave() GameTooltip:Hide() end
function dataobj:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:SetPoint(GetTipAnchor(self))
	GameTooltip:ClearLines()

	GameTooltip:AddLine("picoGroup")

	if UnitInRaid("player") then
		GameTooltip:AddDoubleLine(RAID_DIFFICULTY, _G["RAID_DIFFICULTY"..GetRaidDifficulty()], nil,nil,nil, 1,1,1)
	elseif UnitInParty("player") then
		GameTooltip:AddDoubleLine(DUNGEON_DIFFICULTY, _G["DUNGEON_DIFFICULTY"..GetDungeonDifficultyID()], nil,nil,nil, 1,1,1)
	elseif GetLFGMode(LE_LFG_CATEGORY_LFD) == "queued" then
		GameTooltip:AddLine("Looking for group", 0.75,1,0.75)
	else
		GameTooltip:AddLine("Not in a group", 1,1,1)
	end

	if GetLFGMode(LE_LFG_CATEGORY_LFD) == "queued" then
		local _, _, _, _, _, _, instance, _, _, _, _, mywait, elapsed = GetLFGQueueStats()
		average = average or 0
		mywait  = mywait  or 0

		if instance then GameTooltip:AddLine(instance, 1,1,1) end
		if mywait > 0 then GameTooltip:AddDoubleLine(AVERAGE_WAIT_TIME, SecondsToTime(mywait), nil,nil,nil, 1,1,1) end
		if elapsed then GameTooltip:AddDoubleLine(TIME_IN_QUEUE:gsub(": %%s", ""), SecondsToTime(GetTime() - elapsed), nil,nil,nil, 1,1,1) end
	end

	if GetNumGroupMembers() == 0 then return GameTooltip:Show() end

	GameTooltip:AddDoubleLine("Loot method", GetLootTypeText())

	local _, pML, rML = GetLootMethod()
	if pML or rML then GameTooltip:AddDoubleLine("Master looter", names[UnitName(rML and "raid"..rML or pML == 0 and "player" or "party"..pML)]) end

	if UnitInRaid("player") then
		local officers

		for i=1,GetNumGroupMembers() do
			local name, rank, _, _, _, _, _, _, _, _, isML = GetRaidRosterInfo(i)
			if rank == 1 then officers = true
			elseif rank == 2 then GameTooltip:AddDoubleLine("Leader", names[name]) end
		end

		if officers then
			for i=1,GetNumGroupMembers() do
				UnitIsRaidOfficer('player')
				local name, rank = GetRaidRosterInfo(i)
				if rank == 1 then
					GameTooltip:AddDoubleLine(officers and "Officers" or "", names[name])
					officers = false
				end
			end
		end
	elseif UnitInParty("player") then
		for i=1,GetNumGroupMembers() do
			local unit = i == 0 and "player" or "party"..i
			if UnitIsGroupLeader(unit) then
				GameTooltip:AddDoubleLine("Leader", names[UnitName(unit)])
			end
		end
	end

	GameTooltip:Show()
end


local dropdown, dropdowninit, menuitems
function dataobj:OnClick(button)
	if GetNumGroupMembers() == 0 then return end
	if not dropdown then
		dropdown = CreateFrame("Frame", "picoGroupDownFrame", self, "UIDropDownMenuTemplate")

		local function sdd(self)
			SetDungeonDifficultyID(self.value)
			if UnitInRaid("player") then ConvertToParty() end
		end
		local function srd(self)
			SetRaidDifficulty(self.value)
			if not UnitInRaid("player") then ConvertToRaid() end
		end
		local function slm(self) SetLootMethod(self.value, self.value == "master" and UnitName("player") or nil) end
		local function slt(self) SetLootThreshold(self.value) end
		local function gdd(i) return not UnitInRaid("player") and GetDungeonDifficultyID() == i end
		local function grd(i) return UnitInRaid("player") and GetRaidDifficulty() == i end
		local function glm(i) return GetLootMethod() == i end
		local function glt(i) return GetLootThreshold() == i end
		local LEADERSPACE = {disabled = true, leaderonly = true, notCheckable = true}
		menuitems = {
			{text = "Group Mode", isTitle = true, leaderonly = true, notCheckable = true},
			{text = DUNGEON_DIFFICULTY1, value = 1, func = sdd, checkedfunc = gdd, leaderonly = true},
			{text = DUNGEON_DIFFICULTY2, value = 2, func = sdd, checkedfunc = gdd, leaderonly = true},
			{text = RAID_DIFFICULTY1, value = 1, func = srd, checkedfunc = grd, leaderonly = true},
			{text = RAID_DIFFICULTY2, value = 2, func = srd, checkedfunc = grd, leaderonly = true},
			{text = RAID_DIFFICULTY3, value = 3, func = srd, checkedfunc = grd, leaderonly = true},
			{text = RAID_DIFFICULTY4, value = 4, func = srd, checkedfunc = grd, leaderonly = true},

			LEADERSPACE,
			-- local loottypes = {freeforall = "FFA", group = "Group", master = "ML", needbeforegreed = "NBG", roundrobin = "RR"}
			{text = LOOT_METHOD, isTitle = true, leaderonly = true, notCheckable = true},
			{text = LOOT_FREE_FOR_ALL,      value = "freeforall",      func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_ROUND_ROBIN,       value = "roundrobin",      func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_MASTER_LOOTER,     value = "master",          func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_GROUP_LOOT,        value = "group",           func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_NEED_BEFORE_GREED, value = "needbeforegreed", func = slm, checkedfunc = glm, leaderonly = true},

			LEADERSPACE,
			{text = LOOT_THRESHOLD, isTitle = true, leaderonly = true, notCheckable = true},
			{text = ITEM_QUALITY_COLORS[2].hex..ITEM_QUALITY2_DESC, value = 2, func = slt, checkedfunc = glt, leaderonly = true},
			{text = ITEM_QUALITY_COLORS[3].hex..ITEM_QUALITY3_DESC, value = 3, func = slt, checkedfunc = glt, leaderonly = true},
			{text = ITEM_QUALITY_COLORS[4].hex..ITEM_QUALITY4_DESC, value = 4, func = slt, checkedfunc = glt, leaderonly = true},

			{disabled = true, notCheckable = true},
			{text = OPT_OUT_LOOT_TITLE:gsub(":.+$", ""), func = function() SetOptOutOfLoot(not GetOptOutOfLoot()) end, checked = GetOptOutOfLoot, isNotRadio = true},
			LEADERSPACE,
			{text = RESET_INSTANCES, func = function() StaticPopup_Show("CONFIRM_RESET_INSTANCES") end, leaderonly = true, notCheckable = true},
			LEADERSPACE,
			{text = PARTY_LEAVE, func = LeaveParty, notCheckable = true},
		}
		function dropdowninit()
			local isleader = UnitIsRaidOfficer('player') or UnitIsGroupLeader('player')
			for i,v in ipairs(menuitems) do
				if not v.leaderonly or isleader then
					if v.checkedfunc then v.checked = v.checkedfunc(v.value) end
					UIDropDownMenu_AddButton(v, 1)
				end
			end
		end
	end

	GameTooltip:Hide()
	UIDropDownMenu_Initialize(dropdown, dropdowninit, "MENU")
	UIDropDownMenu_SetAnchor(dropdown, 0, 0, GetTipAnchor(self))
	ToggleDropDownMenu(1, "picoGroupDownFrame", dropdown, "meh")
end
