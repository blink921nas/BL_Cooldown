--------------------------------------------------------
-- Library Raid Inspect --
--------------------------------------------------------
local MAJOR, MINOR = "LibRaidInspect-1.0", 90000 + tonumber(("$Rev: 1 $"):match("(%d+)"))
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

if not lib.events then
	lib.events = LibStub("CallbackHandler-1.0"):New(lib)
end

local frame = lib.frame
if (not frame) then
	frame = CreateFrame("Frame", MAJOR .. "_Frame")
	lib.frame = frame
end
--------------------------------------------------------
--[[LibRaidInspectMembers ={['GUID'] = {
													['name']    = Character Name,
													['class']   = Character Class,
													['race']    = Character Race,
													['realm']    = Character Realm,
													['spec']    = Character Specialization,
													['talents'] = {
																	 ['1'] = Talent 1,
																	 ['2'] = Talent 2,
																	 ['3'] = Talent 3,
																	 ['4'] = Talent 4,
																	 ['5'] = Talent 5,
																	 ['6'] = Talent 6,
																	}
													['glyphs'] = {
																	 ['1'] = Glyph 1,
																	 ['2'] = Glyph 2,
																	 ['3'] = Glyph 3,
																	 ['4'] = Glyph 4,
																	 ['5'] = Glyph 5,
																	 ['6'] = Glyph 6,
																	}
													},
									}
]]


--------------------------------------------------------
-- Local Variables--
--------------------------------------------------------

local INSPECTDELAY = 2
local INSPECTTIMEOUT = 5

local specChangers = {}

local enteredWorld = IsLoggedIn()
--------------------------------------------------------


for index,spellid in ipairs(_G.TALENT_ACTIVATION_SPELLS) do
	specChangers[GetSpellInfo(spellid)] = index
end

lib.frame:UnregisterAllEvents()
lib.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
lib.frame:RegisterEvent("INSPECT_READY")
lib.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
lib.frame:RegisterEvent("PLAYER_LEAVING_WORLD")
lib.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
lib.frame:RegisterEvent("ADDON_LOADED")
lib.frame:SetScript("OnEvent", function(this, event, ...)
	return lib[event](lib, ...)
end)

do
	local lastUpdateTime = 0
	frame:SetScript("OnUpdate", function(this, elapsed)
		lastUpdateTime = lastUpdateTime + elapsed
		if lastUpdateTime > INSPECTDELAY then
			lib:CheckInspectQueue()
			lastUpdateTime = 0
			frame:Hide()
		end
	end)
	frame:Hide()
end
--------------------------------------------------------
-- Core Functions --
--------------------------------------------------------

-- return Raid Members
function lib:returnRaidMembers()
	return LibRaidInspectMembers
end

-- Check Inspect Queue
function lib:CheckInspectQueue()
	if (_G.InspectFrame and _G.InspectFrame:IsShown()) then
		return
	end
	
	if (not self.lastInspectTime or lib.lastInspectTime < GetTime() - INSPECTTIMEOUT) then
		lib.lastInspectPending = 0
	end

	if (lib.lastInspectPending > 0 or not enteredWorld) then
		return
	end

	if (lib.lastQueuedInspectReceived and lib.lastQueuedInspectReceived < GetTime() - 60) then
		-- No queued results received for a minute, so purge the queue as invalid and move on with our lives
		lib.lastInspectTime = nil
		lib.lastInspectPending = 0
		lib.queue = {}
		frame:Hide()
		return
	end
	
	for guid,name in pairs(lib.queue)do
		local unit = lib:GuidToUnitID(guid)
		if (not unit) then
			lib.queue[guid] = nil
		else
			if (UnitIsConnected(unit) and not UnitCanAttack("player", unit) and not UnitCanAttack(unit, "player") and CanInspect(unit) and UnitClass(unit)) then
				NotifyInspect(unit)
				lib.lastInspectPending = 1
				lib.lastInspectTime = GetTime()
				break
			else
				lib.queue[guid] = nil
			end
		end		
	end
end
--------------------------------------------------------

--------------------------------------------------------
-- Helper Functions --
--------------------------------------------------------

function lib:print_r ( t )
    local print_r_cache={}
    local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            print(indent.."*"..tostring(t))
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                for pos,val in pairs(t) do
                    if (type(val)=="table") then
                        print(indent.."["..pos.."] => "..tostring(t).." {")
                        sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                        print(indent..string.rep(" ",string.len(pos)+6).."}")
                    else
                        print(indent.."["..pos.."] => "..tostring(val))
                    end
                end
            else
                print(indent..tostring(t))
            end
        end
    end
    sub_print_r(t," ")
end


function lib:GuidToUnitID(guid)
	local prefix, min, max = "raid", 1, GetNumGroupMembers()
	-- Prioritise getting direct units first because other players targets
	-- can change between notify and event which can bugger things up
	for i = min, max do
		local unit = i == 0 and "player" or prefix .. i
		if (UnitGUID(unit) == guid) then
			return unit
		end
	end

	-- This properly detects target units
	if (UnitGUID("target") == guid) then
        return "target"
	elseif (UnitGUID("focus") == guid) then
		return "focus"
	elseif (UnitGUID("mouseover") == guid) then
		return "mouseover"
    end

	for i = min, max + 3 do
		local unit
		if i == 0 then
			unit = "player"
		elseif i == max + 1 then
			unit = "target"
		elseif i == max + 2 then
			unit = "focus"
		elseif i == max + 3 then
			unit = "mouseover"
		else
			unit = prefix .. i
		end
		if (UnitGUID(unit .. "target") == guid) then
			return unit .. "target"
		elseif (i <= max and UnitGUID(unit.."pettarget") == guid) then
			return unit .. "pettarget"
		end
	end
	return nil
end

-- Get Group Type = 0|None, 1|Party, 2|Raid.
function lib:GroupType()
	if(GetNumGroupMembers() > 0) then
		if(IsInRaid()) then
			return 2
		elseif(IsInGroup()) then
			return 1
		end
	else
		return 0
	end
end

-- Reset
function lib:Reset()
	self.lastInspectPending = 0
	self.lastInspectTime = nil
	lib.lastReceived = nil
	lib.queue = {}
	LibRaidInspectMembers = {}
end
--------------------------------------------------------

--------------------------------------------------------
-- Event Functions --
--------------------------------------------------------

-- ADDON LOADED
function lib:ADDON_LOADED(name)
	if(name=="LibRaidInspect-1.0") then
		if(LibRaidInspectMembers==nil) then
			if(next(LibRaidInspectMembers)==nil) then
				LibRaidInspectMembers={}
			end
		end
		lib.queue = {}
	end
end

-- UNIT SPELLCAST SUCCEEDED
function lib:UNIT_SPELLCAST_SUCCEEDED(unit, spell)
	if(UnitInRaid(unit)==1) then
		local newActiveGroup = specChangers[spell]
		if(newActiveGroup) then
			local guid = UnitGUID(unit)
			local name = select(6, GetPlayerInfoByGUID(guid));
			lib.queue[guid] = name
			lib:CheckInspectQueue()
		end
	end
end

-- GROUP ROSTER UPDATE
function lib:GROUP_ROSTER_UPDATE()
	local unit
	local memberMAX
	local class
	local race
	local name
	if(lib:GroupType()==2) then
		if(GetNumGroupMembers() > 25) then
			memberMAX = 25
		else
			memberMAX = GetNumGroupMembers()
		end
		for i=1, memberMAX do
			unit = "Raid"..i
			local guid = UnitGUID(unit)
			LibRaidInspectMembers[guid] = LibRaidInspectMembers[guid] or {}
			if not(LibRaidInspectMembers[guid]['name']) then
				class,_, race,_,_, name = GetPlayerInfoByGUID(guid);
				LibRaidInspectMembers[guid]['name']   = name
				LibRaidInspectMembers[guid]['class']  = class
				LibRaidInspectMembers[guid]['race']   = race
				self.events:Fire("LibRaidInspect_Add", guid, unit, name)
			end
			if not(LibRaidInspectMembers[guid]['spec']) then
				lib.queue[guid] = name
				lib:CheckInspectQueue()
			end 
		end
		
		for i, char in pairs(LibRaidInspectMembers) do
			if(UnitInRaid(char['name'])==nil) then
				LibRaidInspectMembers[i] = nil
				lib.events:Fire("LibRaidInspect_Remove", i, char['name'])
			end
		end
	else
		lib:Reset()
	end
end

-- INSPECT_READY
function lib:INSPECT_READY(guid)
	if(LibRaidInspectMembers[guid]) then
		local unit = lib:GuidToUnitID(guid)
		if (not unit) then
			lib.queue[guid] = nil
			LibRaidInspectMembers[guid] = nil
		else
			local spec = GetInspectSpecialization(unit)
			if(spec ~= nil and spec > 0) then
				local specGroup = GetActiveSpecGroup(unit)
				local specID, specName =  GetSpecializationInfoByID(spec)
				LibRaidInspectMembers[guid]['spec'] = specName
				LibRaidInspectMembers[guid]['talents'] = {}
				LibRaidInspectMembers[guid]['glyphs'] = {}
				for i=1,6 do
					local talentID,tSpellID = GetInspectTalent(unit, i)
					if(talentID and tSpellID) then
						LibRaidInspectMembers[guid]['talents'][talentID+1] = tSpellID
					end
					
					local _,_,_,gSpellID = GetGlyphSocketInfo(i, 1, true, unit)
					if(gSpellID) then
						LibRaidInspectMembers[guid]['glyphs'][i] = gSpellID
					end
				end
				self.events:Fire("LibRaidInspect_Update", guid, unit, UnitName(unit),specName)
				lib.queue[guid] = nil
				lib:CheckInspectQueue()
				lib.lastInspectPending = 0
				lib.lastQueuedInspectReceived = GetTime()
			end
		end
	else
		lib.queue[guid] = nil
	end
	
	frame:Show()
end

-- PLAYER ENTERING WORLD
function lib:PLAYER_ENTERING_WORLD()
	enteredWorld = true
end

--PLAYER LEAVING WORLD
function lib:PLAYER_LEAVING_WORLD()
	enteredWorld = nil
end
--------------------------------------------------------