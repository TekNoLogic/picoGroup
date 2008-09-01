-- Broker_Group : A Data Broker port of "GroupFu" (Rabbit)
-- Embed & stuff, create DO etc...
local BRGroup = CreateFrame("Frame", "Broker_Group")
local deformatter = AceLibrary("Deformat-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Broker_Group", true)
BRGroup.obj = LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject("Broker Group", {label = "Broker Group", icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", text = "|cff9d9d9d" .. L["Solo"].."|r"})
LibStub("AceTimer-3.0"):Embed(BRGroup)

BRGroup:RegisterEvent("VARIABLES_LOADED")
BRGroup:RegisterEvent("CHAT_MSG_SYSTEM")
BRGroup:RegisterEvent("RAID_ROSTER_UPDATE")
BRGroup:RegisterEvent("PARTY_MEMBERS_CHANGED")
BRGroup:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")

BRGroup:SetScript("OnEvent", function(_, event, ...)
	BRGroup[event](BRGroup, ...)
end)

-- local variables go here
local hexColors = { WTF = "|cffa0a0a0" }
for k, v in pairs(RAID_CLASS_COLORS) do
	hexColors[k] = "|cff" .. string.format("%02x%02x%02x", v.r * 255, v.g * 255, v.b * 255)
end
local coloredName = setmetatable({}, {__index =
	function(self, key)
		if type(key) == "nil" then return nil end
		local class = select(2, UnitClass(key)) or "WTF"
		self[key] = hexColors[class]  .. key .. "|r"
		return self[key]
	end
})

local _G = getfenv(0)

local rollers = nil
local lastAnnouncement = nil

local currentMin = 0
local currentMax = 0
local BRAnnounce = nil
local BRTimeout = nil

-- Ace config table

local options = {
	name = "Broker Group",
	type = "group",
	args = {
	confdesc = {
			order = 1,
			type = "description",
			name = L["Minimalistic LDB plugin to track down rolls and perform group functions."].."\n",
			cmdHidden = true
		},
		standard = {
			order = 6, type = "toggle", width = "full",
			name = L["Only accept 1-100"],
			desc = L["Accept standard (1-100) rolls only."],
			get = function() return Broker_GroupConfig.StandardRollsOnly end,
			set = function(_,v) Broker_GroupConfig.StandardRollsOnly = v end,
		},
		click = {
			order = 7, type = "toggle", width = "full",
			name = L["Perform roll when clicked"],
			desc = L["Perform a standard 1-100 roll when the plugin is clicked."],
			get = function() return Broker_GroupConfig.RollOnClick end,
			set = function(_,v) Broker_GroupConfig.RollOnClick = v end,
		},
		announcelocation = {
			order = 2, type = "select",
			name = L["Announce"],
			desc = L["Where to output roll results."],
			get = function() return Broker_GroupConfig.OutputChannel end,
			set = function(_,v) Broker_GroupConfig.OutputChannel = v end,
			values = {
				["AUTO"] = L["Auto (based on group)"],
				["LOCAL"] = L["Local"],
				["SAY"] = L["Say"],
				["PARTY"] = L["Party"],
				["RAID"] = L["Raid"],
				["GUILD"] = L["Guild"],
				["OFF"] = L["Don't announce"],
			}
		},
		rollclearing = {
			order = 3, type = "select",
			name = L["Roll clearing"],
			desc = L["When to clear the rolls."],
			get = function() return Broker_GroupConfig.ClearTimer end,
			set = function(_,v) Broker_GroupConfig.ClearTimer = v end,
			values = {
				["0"] = L["Never"],
				["10"] = L["10 seconds"],
				["15"] = L["15 seconds"],
				["30"] = L["30 seconds"],
				["45"] = L["45 seconds"],
				["60"] = L["60 seconds"]
			},
		},
		loottype = {
			order = 4, type = "select",
			name = L["Loot type"],
			desc = L["Set the loot type."],
			get = GetLootMethod,
			set = function(_,v)
				if v == "master" then
					SetLootMethod(v, UnitName("player"))
				else
					SetLootMethod(v)
				end
				BRGroup:Update()
			end,
			values = {
				["group"] = L["group"],
				["master"] = L["master"],
				["freeforall"] = L["freeforall"],
				["roundrobin"] = L["roundrobin"],
				["needbeforegreed"] = L["needbeforegreed"],
			},
			disabled = function()
				if UnitExists("party1") or UnitInRaid("player") and IsPartyLeader() or IsRaidLeader() then
					return false
				end
				return true
			end,
		},
		lootthreshold = {
			order = 5, type = "select",
			name = L["Loot threshold"],
			desc = L["Set the loot threshold."],
			get = function() return tostring(GetLootThreshold()) end,
			set = function(_,v)
				SetLootThreshold(tonumber(v))
				BRGroup:Update()
			end,
			values = {
				["2"] = select(4, GetItemQualityColor(2)).._G["ITEM_QUALITY2_DESC"].."|r",
				["3"] = select(4, GetItemQualityColor(3)).._G["ITEM_QUALITY3_DESC"].."|r",
				["4"] = select(4, GetItemQualityColor(4)).._G["ITEM_QUALITY4_DESC"].."|r",
				["5"] = select(4, GetItemQualityColor(5)).._G["ITEM_QUALITY5_DESC"].."|r",
				["6"] = select(4, GetItemQualityColor(6)).._G["ITEM_QUALITY6_DESC"].."|r",
			},
			disabled = function()
				if UnitExists("party1") or UnitInRaid("player") and IsPartyLeader() or IsRaidLeader() then
					return false
				end
				return true
			end,
		},
		leaveparty = {
			order = 8, type = "execute",
			name = L["Leave Party"],
			desc = L["Leave your current party or raid."],
			disabled = function()
				if UnitExists("party1") or UnitInRaid("player") then
					local inInstance, instanceType = IsInInstance()
					if instanceType == "arena" or instanceType == "pvp" then
						return true
					end
					return false
				end
				return true
			end,
			func = LeaveParty,
		},
		resetinstance = {
			order = 9, type = "execute",
			name = L["Reset Instances"],
			desc = L["Reset all available instance the group leader has active."],
			disabled = function()
				return not CanShowResetInstances()
			end,
			func = ResetInstances,
		},
	}
}

-- Add config to Blizzard menu
LibStub("AceConfig-3.0"):RegisterOptionsTable("Broker Group", options)
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Broker Group")


function BRGroup:VARIABLES_LOADED()
	if not Broker_GroupConfig then 
  -- initialize default configuration
    Broker_GroupConfig = { 
		RollOnClick = true,
		OutputChannel = "LOCAL",
		ClearTimer = "30",
		StandardRollsOnly = true,
        	}
  end
end


function BRGroup:GetHighestRoller()
	local highestPlayer = nil
	for i, v in ipairs(rollers) do
		if not highestPlayer and not v.pass then
			highestPlayer = i
		else
			if not v.pass and v.roll > rollers[highestPlayer].roll then
				highestPlayer = i
			end
		end
	end
	return highestPlayer
end


function BRGroup:Update()
if rollers then
	local num = UnitInRaid("player") and GetNumRaidMembers() or GetNumPartyMembers() + 1
		local highest = self:GetHighestRoller()
		if highest ~= nil then
			local playerText = string.format(L["%s [%s]"], rollers[highest].player, "|cffff8c00"..rollers[highest].roll.."|r")
			self.obj.text = string.format(L["%s (%d/%d)"], playerText, #rollers, num)
			return
		end
	end
	self.obj.text = self:GetLootTypeText()
end

local function RollSorter(a, b)
	if a.pass then return false
	elseif b.pass then return true
	else return a.roll > b.roll end
end


function BRGroup.obj.OnTooltipShow(tooltip)
	tooltip:AddLine(HIGHLIGHT_FONT_COLOR_CODE.."Broker Group")
	local inRaid = UnitInRaid("player")
	tooltip:AddDoubleLine(L["Loot method"], BRGroup:GetLootTypeText())
	if inRaid then
		local officers = nil
		local ML = nil
		local leader = nil
		for i = 1, GetNumRaidMembers() do
			local name, rank, _, _, _, _, _, _, _, _, isML = GetRaidRosterInfo(i)
			if rank == 1 then
				if officers then officers = officers .. ", " else officers = "" end
				officers = officers .. coloredName[name]
			elseif rank == 2 then
				leader = name
			elseif isML then
				ML = name
			end
		end
		if ML then
			tooltip:AddDoubleLine(L["Master looter"], coloredName[ML])
		end
		if leader then
			tooltip:AddDoubleLine(L["Leader"], coloredName[leader])
		end
		if officers then
			tooltip:AddDoubleLine(L["Officers"], officers)
		end
	end

	if rollers and #rollers > 0 then
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine(L["Player"], L["Roll"])
		table.sort(rollers, RollSorter)
		for i, v in ipairs(rollers) do
			if v.pass then
				tooltip:AddDoubleLine(
					string.format("%s (%d %s)", coloredName[v.player], v.level, v.class),
					"|cff696969" .. L["Pass"] .. "|r"
				)
			else
				tooltip:AddDoubleLine(
					string.format("%s (%d %s)", coloredName[v.player], v.level, v.class),
					GREEN_FONT_COLOR_CODE..v.roll.."|r"
				)
			end
		end
		local num = inRaid and GetNumRaidMembers() or GetNumPartyMembers() + 1
		tooltip:AddLine(" ")
		tooltip:AddLine(string.format(L["%d of expected %d rolls recorded."], #rollers, num))
	end
	tooltip:AddLine(" ")
	if Broker_GroupConfig.RollOnClick then
		tooltip:AddLine(L["|cffeda55fClick|r to roll, |cffeda55fCtrl-Click|r to output winner, |cffeda55fShift-Click|r to clear the list."], 0.2, 1, 0.2, 1)
	else
		tooltip:AddLine(L["|cffeda55fCtrl-Click|r to output winner, |cffeda55fShift-Click|r to clear the list."], 0.2, 1, 0.2, 1)
	end
end


function BRGroup:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end


function BRGroup.obj.OnClick(self, button)
	if IsControlKeyDown() and button == "LeftButton" then
		BRGroup:AnnounceWinner()
	elseif IsShiftKeyDown() and button == "LeftButton" then
		BRGroup:ClearRolls(true)
	elseif Broker_GroupConfig.RollOnClick and button == "LeftButton" then
		RandomRoll("1", "100")
	elseif button == "RightButton" then
		InterfaceOptionsFrame_OpenToFrame("Broker Group")
	end
end

function BRGroup:CHAT_MSG_SYSTEM(msg)
	-- Trap rolls
	local player, roll, minRoll, maxRoll = deformatter(msg, RANDOM_ROLL_RESULT)
	if player then
		
		roll = tonumber(roll)
		minRoll = tonumber(minRoll)
		maxRoll = tonumber(maxRoll)

		if not roll or not minRoll or not maxRoll
		or Broker_GroupConfig.StandardRollsOnly and (minRoll ~= 1 or maxRoll ~= 100) then
			return
		elseif not Broker_GroupConfig.StandardRollsOnly and rollers then
			-- If someone else has already rolled, and we accept rolls other
			-- than 1-100, assume that everyone should roll on the same premises
			-- and only accept rolls that have the same range as the first roll.
			if maxRoll ~= currentMax or minRoll ~= currentMin then
				return
			end
		end

		if not rollers then
			currentMin = minRoll
			currentMax = maxRoll
			rollers = {}

			self:RegisterEvent("CHAT_MSG_PARTY")
			self:RegisterEvent("CHAT_MSG_RAID")
		end

		-- Ignore duplicate rolls.
		for i, v in ipairs(rollers) do
			if v.player == player then return end
		end

		if player == UnitName("player") then
			table.insert(rollers, {
				player = player,
				roll = roll,
				class = UnitClass("player") or "Unknown",
				level = UnitLevel("player") or -1,
			})
		else
			table.insert(rollers, {
				player = player,
				roll = roll,
				class = UnitClass(player) or "Unknown",
				level = UnitLevel(player) or -1,
			})
		end

		self:CheckForWinner()
		self:Update()
	end
end

function BRGroup:CheckForWinner()
	if Broker_GroupConfig.OutputChannel ~= "OFF" or tonumber(Broker_GroupConfig.ClearTimer) > 0 then
		local num = UnitInRaid("player") and GetNumRaidMembers() or GetNumPartyMembers() + 1
		-- If everyone has rolled, just output the winner.
		if num == #rollers and Broker_GroupConfig.OutputChannel ~= "OFF" then
			self:CancelTimer(BRAnnounce, true)
			self:CancelTimer(BRTimeout, true)
			self:AnnounceWinner()
		else
			self:CancelTimer(BRAnnounce, true)
			BRTimeout = self:ScheduleTimer(self.RollTimeout, tonumber(Broker_GroupConfig.ClearTimer) - 5 or 5, self)
		end
	end
end

function BRGroup:CheckForPassers(msg, author)
	if type(msg) ~= "string" then return end
	if type(rollers) ~= "table" then return end

	if msg:lower():find(string.lower(L["Pass"])) then
		local found = nil
		for i, v in ipairs(rollers) do
			if v.player == author then
				v.pass = true
				v.roll = nil
				found = true
				break
			end
		end
		if not found then
			table.insert(rollers, {
				player = author,
				class = UnitClass(author) or "Unknown",
				level = UnitLevel(author) or -1,
				pass = true,
			})
		end
		self:CheckForWinner()
		self:Update()
	end
end


function BRGroup:ClearRolls(override)
	self:CancelTimer(BRTimeout, true)
	self:CancelTimer(BRAnnounce, true)

	if self:IsEventRegistered("CHAT_MSG_PARTY") then
		self:UnregisterEvent("CHAT_MSG_PARTY")
		self:UnregisterEvent("CHAT_MSG_RAID")
	end

	if tonumber(Broker_GroupConfig.ClearTimer) > 0 or override then
		if type(rollers) == "table" then
			for i, v in ipairs(rollers) do
				for k in pairs(v) do
					v[k] = nil
				end
				rollers[i] = nil
			end
		end
		rollers = nil
	end
	self:Update()
end


function BRGroup:GetLootTypeText()
	if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
		return ITEM_QUALITY_COLORS[GetLootThreshold()].hex .. L[GetLootMethod()]
	else
		return "|cff9d9d9d" .. L["Solo"]
	end
end


function BRGroup:RollTimeout()
	if not rollers then return end

	if Broker_GroupConfig.OutputChannel ~= "OFF" then
		local num = UnitInRaid("player") and GetNumRaidMembers() or GetNumPartyMembers() + 1
		self:AnnounceOutput(string.format(L["Roll ending in 5 seconds, recorded %d of %d rolls."], #rollers, num))
	end
	BRAnnounce = self:ScheduleTimer(self.AnnounceWinner, 5, self)
end


function BRGroup:AnnounceWinner()
	if Broker_GroupConfig.OutputChannel ~= "OFF" then
		if rollers then
			local highest = self:GetHighestRoller()
			if highest then
				local tiedRollers = nil
				for i, v in ipairs(rollers) do
					if not v.pass and i ~= highest and v.roll == rollers[highest].roll then
						if not tiedRollers then tiedRollers = {} end
						table.insert(tiedRollers, i)
					end
				end
				if tiedRollers then
					table.insert(tiedRollers, highest)
					local playerNames = ""
					for i, v in ipairs(tiedRollers) do
						if playerNames == "" then
							playerNames = rollers[v].player
						else
							playerNames = playerNames .. L[", "] .. rollers[v].player
						end
					end
					lastAnnouncement = string.format(L["Tie: %s are tied at %d."], playerNames, rollers[highest].roll)
				else
					lastAnnouncement = string.format(L["Winner: %s."], string.format(L["%s [%s]"], rollers[highest].player, rollers[highest].roll))
				end
			else
				lastAnnouncement = L["Everyone passed."]
			end
		end
		if lastAnnouncement then
			self:AnnounceOutput(lastAnnouncement)
		end
	end
	self:ClearRolls()
end


function BRGroup:AnnounceOutput(msg)
	if Broker_GroupConfig.OutputChannel == "LOCAL" then
		self:Print(msg)
	elseif Broker_GroupConfig.OutputChannel == "AUTO" then
		if GetNumRaidMembers() > 0 then
			SendChatMessage(msg, "RAID")
		elseif GetNumPartyMembers() > 0 then
			SendChatMessage(msg, "PARTY")
		else
			self:Print(msg)
		end
	else
		SendChatMessage(msg, Broker_GroupConfig.OutputChannel)
	end
end


function BRGroup:RAID_ROSTER_UPDATE()
	self:Update()
end

function BRGroup:PARTY_MEMBERS_CHANGED()
	self:Update()
end

function BRGroup:PARTY_LOOT_METHOD_CHANGED()
	self:Update()
end

function BRGroup:CHAT_MSG_PARTY(msg, author, lang)
	self:CheckForPassers(msg, author)
end

function BRGroup:CHAT_MSG_RAID(msg, author, lang)
	self:CheckForPassers(msg, author)
end