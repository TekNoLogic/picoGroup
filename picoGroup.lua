
local ldb, ae = LibStub:GetLibrary("LibDataBroker-1.1"), LibStub("AceEvent-3.0")

local loottypes = {freeforall = "FFA", group = "Group", master = "ML", needbeforegreed = "NBG", roundrobin = "RR"}
local raidtypes = {ITEM_QUALITY_COLORS[4].hex.."10", ITEM_QUALITY_COLORS[4].hex.."25", ITEM_QUALITY_COLORS[5].hex.."10H", ITEM_QUALITY_COLORS[5].hex.."25H"}
local dungeontypes = {ITEM_QUALITY_COLORS[2].hex.."5", ITEM_QUALITY_COLORS[3].hex.."5H"}
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
	return GetNumRaidMembers() > 0 and (raidtypes[GetRaidDifficulty()].. "|r - ")
		or GetNumPartyMembers() > 0 and (dungeontypes[GetDungeonDifficulty()].. "|r - ")
		or (ITEM_QUALITY_COLORS[0].hex.."Solo")
end


local function GetLootTypeText()
	return (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0) and (ITEM_QUALITY_COLORS[GetLootThreshold()].hex.. loottypes[GetLootMethod()]) or ""
end


local dataobj = ldb:NewDataObject("picoGroup", {type = "data source", icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", text = GetLootTypeText()})


local function Update() dataobj.text = GetGroupTypeText().. GetLootTypeText() end
ae.RegisterEvent("picoGroup", "RAID_ROSTER_UPDATE", Update)
ae.RegisterEvent("picoGroup", "PARTY_MEMBERS_CHANGED", Update)
ae.RegisterEvent("picoGroup", "PARTY_LOOT_METHOD_CHANGED", Update)


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

	if GetNumRaidMembers() > 0 then
		GameTooltip:AddDoubleLine(RAID_DIFFICULTY, _G["RAID_DIFFICULTY"..GetRaidDifficulty()], nil,nil,nil, 1,1,1)
	elseif GetNumPartyMembers() > 0 then
		GameTooltip:AddDoubleLine(DUNGEON_DIFFICULTY, _G["DUNGEON_DIFFICULTY"..GetDungeonDifficulty()], nil,nil,nil, 1,1,1)
	else
		GameTooltip:AddLine("Not in a group", 1,1,1)
		return GameTooltip:Show()
	end

	GameTooltip:AddDoubleLine("Loot method", GetLootTypeText())

	local _, pML, rML = GetLootMethod()
	if pML or rML then GameTooltip:AddDoubleLine("Master looter", names[UnitName(rML and "raid"..rML or pML == 0 and "player" or "party"..pML)]) end

	if UnitInRaid("player") then
		local officers

		for i=1,GetNumRaidMembers() do
			local name, rank, _, _, _, _, _, _, _, _, isML = GetRaidRosterInfo(i)
			if rank == 1 then officers = true
			elseif rank == 2 then GameTooltip:AddDoubleLine("Leader", names[name]) end
		end

		if officers then
			for i=1,GetNumRaidMembers() do
				local name, rank = GetRaidRosterInfo(i)
				if rank == 1 then
					GameTooltip:AddDoubleLine(officers and "Officers" or "", names[name])
					officers = false
				end
			end
		end
	elseif UnitInParty("player") then
		local i = GetPartyLeaderIndex()
		GameTooltip:AddDoubleLine("Leader", names[UnitName(i == 0 and "player" or "party"..i)])
	end

	GameTooltip:Show()
end


local dropdown, dropdowninit, menuitems
function dataobj:OnClick(button)
	if (GetNumRaidMembers() + GetNumPartyMembers()) == 0 then return end
	if not dropdown then
		dropdown = CreateFrame("Frame", "picoGroupDownFrame", self, "UIDropDownMenuTemplate")

		local function sdd(self) SetDungeonDifficulty(self.value) end
		local function srd(self)
			SetRaidDifficulty(self.value)
			if GetNumRaidMembers() == 0 then ConvertToRaid() end
		end
		local function slm(self) SetLootMethod(self.value, self.value == "master" and UnitName("player") or nil) end
		local function slt(self) SetLootThreshold(self.value) end
		local function gdd(i) return GetNumRaidMembers() == 0 and GetDungeonDifficulty() == i end
		local function grd(i) return GetNumRaidMembers() > 0 and GetRaidDifficulty() == i end
		local function glm(i) return GetLootMethod() == i end
		local function glt(i) return GetLootThreshold() == i end
		menuitems = {
			{text = "Group Mode", isTitle = true, leaderonly = true},
			{text = DUNGEON_DIFFICULTY1, value = 1, func = sdd, checkedfunc = gdd, leaderonly = true},
			{text = DUNGEON_DIFFICULTY2, value = 2, func = sdd, checkedfunc = gdd, leaderonly = true},
			{text = RAID_DIFFICULTY1, value = 1, func = srd, checkedfunc = grd, leaderonly = true},
			{text = RAID_DIFFICULTY2, value = 2, func = srd, checkedfunc = grd, leaderonly = true},
			{text = RAID_DIFFICULTY3, value = 3, func = srd, checkedfunc = grd, leaderonly = true},
			{text = RAID_DIFFICULTY4, value = 4, func = srd, checkedfunc = grd, leaderonly = true},

			{disabled = true, leaderonly = true},
			-- local loottypes = {freeforall = "FFA", group = "Group", master = "ML", needbeforegreed = "NBG", roundrobin = "RR"}
			{text = LOOT_METHOD, isTitle = true, leaderonly = true},
			{text = LOOT_FREE_FOR_ALL,      value = "freeforall",      func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_ROUND_ROBIN,       value = "roundrobin",      func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_MASTER_LOOTER,     value = "master",          func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_GROUP_LOOT,        value = "group",           func = slm, checkedfunc = glm, leaderonly = true},
			{text = LOOT_NEED_BEFORE_GREED, value = "needbeforegreed", func = slm, checkedfunc = glm, leaderonly = true},

			{disabled = true, leaderonly = true},
			{text = LOOT_THRESHOLD, isTitle = true, leaderonly = true},
			{text = ITEM_QUALITY_COLORS[2].hex..ITEM_QUALITY2_DESC, value = 2, func = slt, checkedfunc = glt, leaderonly = true},
			{text = ITEM_QUALITY_COLORS[3].hex..ITEM_QUALITY3_DESC, value = 3, func = slt, checkedfunc = glt, leaderonly = true},
			{text = ITEM_QUALITY_COLORS[4].hex..ITEM_QUALITY4_DESC, value = 4, func = slt, checkedfunc = glt, leaderonly = true},

			{disabled = true, leaderonly = true},
			{text = RESET_INSTANCES, func = function() StaticPopup_Show("CONFIRM_RESET_INSTANCES") end, leaderonly = true},
			{disabled = true, leaderonly = true},
			{text = OPT_OUT_LOOT_TITLE:gsub(":.+$", ""), func = function() SetOptOutOfLoot(not GetOptOutOfLoot()) end, checked = GetOptOutOfLoot},
			{disabled = true},
			{text = PARTY_LEAVE, func = LeaveParty},
		}
		function dropdowninit()
			local isleader = IsRaidLeader() or IsRaidOfficer() or IsPartyLeader()
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
