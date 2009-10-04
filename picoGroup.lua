
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
