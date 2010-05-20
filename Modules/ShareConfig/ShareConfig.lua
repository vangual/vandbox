if select(6, GetAddOnInfo("PitBull4_" .. (debugstack():match("[o%.][d%.][u%.]les\\(.-)\\") or ""))) ~= "MISSING" then return end

local PitBull4 = _G.PitBull4
if not PitBull4 then
	error("PitBull4_ShareConfig requires PitBull4")
end

local L = PitBull4.L
local clone = PitBull4.Utils.deep_copy
local fmt = string.format
local dump = string.dump
local join = table.concat

local profile

PB4SC = PitBull4:NewModule("ShareConfig", "AceEvent-3.0", "AceComm-3.0","AceSerializer-3.0")
--local self = PB4SC

PB4SC:SetModuleType('custom')
PB4SC:SetName(L['Share config'])
PB4SC:SetDescription(L['Allows the import and export of profiles or individual layouts.'])
PB4SC:SetDefaults({},{})

PB4SC.import_string = nil
PB4SC.profile_to_export = nil -- must default to nil for the option UI hooks!
PB4SC.layouts_to_export = {}
PB4SC.layouts_to_import = {}
PB4SC.layout_states = {}
PB4SC.send_recipient_name = ""
PB4SC.export_mode = "profile" -- or "layouts"
PB4SC.minimalVersion = 1 -- Exports with an older version tag than this will not be imported.
PB4SC.hideComm = true -- Sharing via comm not fully implemented yet. Not sre if I will ever have time for it. No need to get the hope of people up.
PB4SC.disableLayoutfunctions = nil -- Layout importing is still WIP. Until then, these functions are unavailable to users.
PB4SC.debug = nil

-- Globals needed for the static popups. ( :( ) --TODO: Switch to ACEGUI instead of staticpopups
PB4SC_SP_ImportLayoutConfirmText = "Something broke. Please press cancel and file a bug."

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LibCompress = LibStub("LibCompress")
local Base64 = LibStub("LibBase64-1.0")

do
	for i, cmd in ipairs { "/pb4sc" } do
		_G["SLASH_PITBULLFOURSC" .. (i*2 - 1)] = cmd
		_G["SLASH_PITBULLFOURSC" .. (i*2)] = cmd:lower()
	end

	_G.hash_SlashCmdList["PITBULLFOURSC"] = nil
	_G.SlashCmdList["PITBULLFOURSC"] = function()
		return PB4SC.OpenConfig()
	end
end

function PB4SC:Debug(msg)
	if PB4SC.debug then
		print("PB4SC DBG: ".. tostring(msg))
	end
end

function PB4SC:OpenConfig()
	PitBull4.Options.OpenConfig()
	AceConfigDialog:SelectGroup("PitBull4", "modules", "ShareConfig", "main_group")
end


local function global_option_get(key)
	if type(key) == 'table' then
		return PB4SC.db.profile.global[key[#key]]
	else
		return PB4SC.db.profile.global[key]
	end
end
local function global_option_set(key, value)
	if type(key) == 'table' then
		PB4SC.db.profile.global[key[#key]] = value
	else
		PB4SC.db.profile.global[key] = value
	end
end

local function hasNotReadWarning()
	return not global_option_get('intro_acceptwarning')
end

local function inTable(haystack, needle)
	for k,v in pairs(haystack) do
		if v == needle then
			return k
		end
	end
	return nil
end

local function dictCount(dict)
	if type(dict) ~= "table" then return nil end
	local counter = 0
	local k, v
	for k,v in pairs(dict) do
		counter = counter + 1
	end
	return counter
end

function checkProfileExists(checkname)
	for name in pairs(PitBull4.db.profiles) do
		if name == checkname then
			return true
		end
	end
	return nil	-- name doesn't exist
end
function checkLayoutExists(checkname)
	for name in pairs(PitBull4.db.profile.layouts) do
		if name == checkname then
			return true
		end
	end
	return nil	-- name doesn't exist
end


function suggestNewProfileName(requested_name)
	local collision = nil
	collision = checkProfileExists(requested_name)

	if collision then
		-- start trying alternative names	
		local counter = 1
		local name_suggestion = requested_name .. ' (' ..tostring(counter) .. ')'
		while checkProfileExists(name_suggestion) do
			counter = counter + 1
			name_suggestion = requested_name .. ' (' ..tostring(counter) .. ')'
		end
		return name_suggestion
	else
		return requested_name
	end
end

function suggestNewLayoutName(requested_name)
	local collision = nil
	collision = checkLayoutExists(requested_name)

	if collision then
		-- start trying alternative names	
		local counter = 1
		local name_suggestion = requested_name .. ' (' ..tostring(counter) .. ')'
		while checkLayoutExists(name_suggestion) do
			counter = counter + 1
			name_suggestion = requested_name .. ' (' ..tostring(counter) .. ')'
		end
		return name_suggestion
	else
		return requested_name
	end
end

function makeLayoutsUnique(layouttable)
	local l = layouttable
	local result = clone(l)
	wipe(result.layouts)
	result.layouts = {}
	for lname,lcontent in pairs(l.layouts) do
                if type(lname) == "string" and type(lcontent) == "table" then
			result.layouts[suggestNewLayoutName(lname)] = clone(lcontent)
                end
        end
	return result
end

function PB4SC:RefreshProfile() 
	-- needed for the layout-list in the option screen
	profile = self.db.profile

	-- Cleanup leftovers to make sure we don't bleed between profiles.
	if PB4SC.profile_to_import then 
		wipe(PB4SC.profile_to_import)
	end
	PB4SC.profile_name_to_import = nil
end

function PB4SC:OnInitialize()
	profile = PitBull4.db.profile

	-- hook profile changes so we know when to display different layouts.
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshProfile")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshProfile")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshProfile")
	
	self.Compressor = LibStub("LibCompress")
	self.AddonEncodeTable = self.Compressor:GetAddonEncodeTable()
end

function PB4SC:MySerialize(data)
	local output = PB4SC:Serialize(data)
	PB4SC:Debug("Length (Serialized): "..tostring(string.len(output)))
	output = LibCompress:CompressHuffman(output)
	PB4SC:Debug("Length (Serialized+Compressed): "..tostring(string.len(output)))
	output = Base64.Encode(output,80)
	PB4SC:Debug("Length (Serialized+Compressed+Encoded): "..tostring(string.len(output)))
	return output
end

StaticPopupDialogs["PB4ShareConfigImportProfileNameDialog"] = {
	text = "Name the Profile to import",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	hasWideEditBox = 1,
	OnShow = function(self, data)
		local editBox = _G[this:GetName().."WideEditBox"]
		if editBox then
			editBox:SetText(PB4SC.profile_name_to_import)
			editBox:SetFocus()
			editBox:HighlightText(0)
		end
		this:SetFrameStrata("FULLSCREEN_DIALOG") -- needed to be infront of the PB4 config :(
		this:Raise()
	end,
	OnHide = function()
		-- restore normal strata, since popups are reused.
		this:SetFrameStrata("DIALOG")
	end,
	OnAccept = function(self, data, data2)
		local editBox = _G[this:GetName().."WideEditBox"]
		local editBox = self.wideEditBox
		PB4SC.profile_name_to_import = editBox:GetText()
		PB4SC.DoImportPhase2Profile()
	end,
	EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	maxLetters=64, -- this otherwise gets cached from other dialogs which caps it at 10..20..30...
}



local function PB4ShareConfigImportProfileBox()
	StaticPopup_Show("PB4ShareConfigImportProfileNameDialog")
	return
end

local function PB4ShareConfigImportProfileBox_acegui() -- experimental, not properly working yet
	AceGUI = LibStub("AceGUI-3.0")
	local frame = AceGUI:Create("Frame")
	frame:SetTitle(L["Profile Name"])
	frame:SetLayout("Fill")
	frame:SetWidth(200)
	frame:SetHeight(200)
	
	local editBox = AceGUI:Create("EditBox")
	editBox:SetText(PB4SC.profile_name_to_import)
	editBox:SetWidth(100)
	editBox.editbox:HighlightText()
	editBox.editbox:SetAutoFocus(true)
	editBox:SetLabel(L["New name for the profile to import:"])
	frame:AddChild(editBox)
	
	frame:SetCallback("OnEnterPressed", function(widget)
		PB4SC.profile_name_to_import = editBox.editbox:GetText()
		PB4SC.DoImportPhase2Profile()
	end)
	
	frame:SetCallback("OnClose", function(widget) 
		editBox.editbox:SetAutoFocus(false)
		AceGUI:Release(widget) 
	end)
	frame:Show()
	frame.frame:Raise()
end

local function PB4ShareConfigImportLayoutsBox()
	if (type(PB4SC.layouts_to_import) ~= "table") or (type(PB4SC.layouts_to_import.layouts) ~= "table") or (dictCount(PB4SC.layouts_to_import.layouts) == 0) then
		print(L["ERROR: No layout to import found."])
		return false
	end

	local layoutstext = ""
	local first = true
	for key,val in pairs(PB4SC.layouts_to_import.layouts) do
		if first then
			layoutstext = layoutstext .. tostring(key)
			first = nil
		else
			layoutstext = layoutstext .. ", " .. tostring(key)
		end
	end

	-- The following variable is global intentionally due to the use of StaticPopups :(
	PB4SC.SP_ImportLayoutConfirmText = L["Are you sure you want to import the following layouts into the CURRENT profile?\nLayouts: "] .. layoutstext
	
	StaticPopupDialogs["PB4ShareConfigImportLayoutsConfirmDialog"] = {
		text = PB4SC.SP_ImportLayoutConfirmText,
		button1 = OKAY,
		button2 = CANCEL,
		hasEditBox = false,
		OnShow = function()
			this:SetFrameStrata("FULLSCREEN_DIALOG") -- needed to be infront of the PB4 config :(
			this:Raise()
		end,
		OnHide = function()
			-- restore normal strata, since popups are reused.
			this:SetFrameStrata("DIALOG")
		end,
		OnAccept = function()
			PB4SC.DoImportPhase2Layout()
		end,
		EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		maxLetters=64, -- this otherwise gets cached from other dialogs which caps it at 10..20..30...
	}
	StaticPopup_Show("PB4ShareConfigImportLayoutsConfirmDialog")
	return
end


local function PB4ShareConfigExportBox()
	AceGUI = LibStub("AceGUI-3.0")
	local frame = AceGUI:Create("Frame")
	frame:SetTitle(L["Export Data"])
	frame:SetLayout("Fill")
	
	local editBox = AceGUI:Create("MultiLineEditBox")
	editBox:SetText(PB4SC.exported_config_text)
	editBox.editbox:HighlightText()
	editBox.editbox:SetAutoFocus(true)
	editBox:SetLabel(L["Copy this to clipboard. (Ctrl-C to copy)"])
	frame:AddChild(editBox)
	
	frame:SetCallback("OnClose", function(widget) 
		editBox.editbox:SetAutoFocus(false)
		AceGUI:Release(widget) 
	end)
	frame:Show()
	frame.frame:Raise()
end

function PB4SC:DoExport()
	if  PB4SC.export_mode == "profile" then
		local tempprofile = clone(PitBull4.db.profiles[PB4SC.profile_to_export])
		tempprofile.pb4export = true
		tempprofile.pb4exportversion = 1
		tempprofile.pb4exporttype = "profile"
		tempprofile.pb4exportname = tostring(PB4SC.profile_to_export)
		
		PB4SC.exported_config_text = PB4SC:MySerialize(tempprofile)
		--PB4SC_SP_ExportedConfigText = PB4SC.exported_config_text -- Legacy Line for staticpopups
		
		tempprofile = nil
		--PB4ShareConfigExportBox()
	else
		PB4SC:Debug("Reached DoExport's layoutpath")
		local tempprofile = {}
		tempprofile.layouts = {}
		tempprofile.pb4export = true
		tempprofile.pb4exportversion = 1
		tempprofile.pb4exporttype = "layouts"
		--GRMDBGL2E = PB4SC.layouts_to_export -- TODO: Remove me

		for ln,lv in ipairs(PB4SC.layouts_to_export) do
			if lv then
				tempprofile.layouts[lv] = clone(PitBull4.db.profile.layouts[lv])
				PB4SC:Debug(fmt("including layout %s",tostring(lv)))
			end
		end
		
		PB4SC.exported_config_text = PB4SC:MySerialize(tempprofile)
		--PB4SC_SP_ExportedConfigText = PB4SC.exported_config_text -- Legacy Line for staticpopups
		tempprofile = nil
		
		--PB4ShareConfigExportBox()
	end
end

function PB4SC:DoImportPhase1()
	-- Some initial cleanup
	PB4SC.profile_to_import = nil
	PB4SC.profile_name_to_import = nil
	PB4SC.layouts_to_import = nil

	local s = PB4SC.import_string
	if type(s) ~= "string" then 
		PB4SC:Debug(fmt("Importing needs a string. Got type: %s", type(s)))
	end

	-- decode the base64 envelope
	s = Base64.Decode(s)
	-- uncompress the text
	s = LibCompress:Decompress(s)
	
	local success, data = PB4SC:Deserialize(s)
	if not success then 
		PB4SC:Debug(fmt("Error in deserialize. %s", tostring(data)))
		return nil
	end

	local importedTable = data

	if not importedTable or not importedTable.pb4exportversion or not importedTable.pb4exporttype then
		print(L['Importing failed. Supplied data is completely unknown.'])
		return nil
	end

	if importedTable.pb4exportversion < PB4SC.minimalVersion then
		print(L['Importing failed. Supplied export from a too old version. Please request an export of someone with a more up-to-date version of PitBull4.'])
		return nil
	end
	
	if importedTable.pb4exporttype == "profile" then
		PB4SC.profile_to_import = importedTable
		PB4SC.profile_name_to_import = suggestNewProfileName(importedTable.pb4exportname)
		PB4ShareConfigImportProfileBox()
		return true
	elseif importedTable.pb4exporttype == "layouts" then
		--print(L["Error importing config: Importing layouts not yet supported."])
		PB4SC.layouts_to_import = makeLayoutsUnique(importedTable) --this function also clones its input
		PB4ShareConfigImportLayoutsBox()
	else
		print(L["Error importing config: Unknown profile type."])
	end

	--grmdbgimported = importedTable
	return nil
end

function PB4SC:DoImportPhase2Layout()
	if (type(PB4SC.layouts_to_import) ~= "table") or (type(PB4SC.layouts_to_import.layouts) ~= "table") or (dictCount(PB4SC.layouts_to_import.layouts) == 0) then
		print(L["ERROR: No layout to import found."])
		return false
	end

	for lname,lcontent in pairs(PB4SC.layouts_to_import.layouts) do
		if type(lname) == "string" and type(lcontent) == "table" then
			print(fmt(L["Importing %s"], tostring(lname)))
			PitBull4.db.profile.layouts[lname] = clone(lcontent)
			PB4SC:Debug("Imported layout "..tostring(lname))
		else
			print(string.format(L["ERROR: Layout %s is corrupt. Aborted import of this layout."], tostring(lname)))
		end
	end
end

function PB4SC:DoImportPhase2Profile()
	local importname = tostring(PB4SC.profile_name_to_import)
	if importname == "" or importname == nil then
		print(L["Error importing. Illegal profile name specified."])
		return nil
	end
	PB4SC:Debug(fmt("Would import a new profile called %s now.", importname))
	local prof = PB4SC.profile_to_import
	-- cleanup the profile before importing
	prof.pb4export = nil
	prof.pb4exportname = nil
	prof.pb4exporttype = nil
	prof.pb4exportversion = nil

	PitBull4.db.profiles[importname] = clone(prof)
	print(fmt(L["Profile %s imported successfully. You may now select it in the profile selection."], importname))
	-- Cleanup 
	wipe(PB4SC.profile_to_import)
	PB4SC.profile_name_to_import = nil
end

function PB4SC:DoSend()
	PB4SC:Debug("Sending is not yet implemented.")
end



function PB4SC:OptionsLayoutValues()
	if PB4SC.last_active_profile_seen ~= PitBull4.db.profile then
		PB4SC:Debug("Profile switch noticed. Rebuilding list of layouts.")
		-- Profile changed or first run, need to populate our array now..
		if PB4SC.layouts_to_export then
			wipe(PB4SC.layouts_to_export)
		end
		PB4SC.layouts_to_export = {} -- recreate
		
		if PB4SC.layouts_list then
			wipe(PB4SC.layouts_list)
		end
		PB4SC.layouts_list = {} -- recreate it
		
		for name in pairs(PitBull4.db.profile.layouts) do
			--PB4SC.layouts_to_export[name] = true
			table.insert(PB4SC.layouts_to_export, name)
			PB4SC.layouts_list[name] = name
		end
		PB4SC.last_active_profile_seen = PitBull4.db.profile
	end
	return PB4SC.layouts_list
end

function PB4SC:OptionsLayoutValueToggle(v)
	if not PB4SC.layouts_list[v] then return nil end
	PB4SC.layouts_to_export[v] = not PB4SC.layouts_to_export[v]
end

function PB4SC:OptionsLayoutValueSet(keyname,value)
	if not PB4SC.layouts_list[keyname] then return nil end
	--PB4SC.layouts_to_export[keyname] = value
	if value then
		-- we must add it
		if inTable(PB4SC.layouts_to_export, keyname) then
			return true	-- already added
		else
			return table.insert(PB4SC.layouts_to_export, keyname)
		end
	else
		-- we must remove it
		local position = inTable(PB4SC.layouts_to_export, keyname)
		if not position then
			return true	-- already removed
		else
			return table.remove(PB4SC.layouts_to_export, position)
		end
	end
	return nil
end
function PB4SC:OptionsLayoutValueGet(keyname)
	if inTable(PB4SC.layouts_to_export, keyname) then
		return true
	else
		return false
	end
end

----
-- User Interface

function PB4SC:GetImportOptionGroup()
	local function get(info)
		local id = info[#info]
		return self.db.profile.global[id]
	end
	local function set(info, value)
		local id = info[#info]
		self.db.profile.global[id] = value
		
		self:UpdateFrames()
	end
	local function hidden(info)
		return not self:IsEnabled()
	end
	return { 
		import_hint = {
			type = 'description',
			name = L["Use Copy (CTRL-C) and Paste (CTRL-V) to copy the encoded config data into the field below."],
			order = 1,				
			width = 'full',
		},
		import_text = {
			type = 'input',
			name = L["Encoded config"],
			desc = L["Enter the encoded config string."],
			order = 10,
			get = function(info)
				return ""
			end,
			set = function(info, value)
				PB4SC.import_string = string.gsub(tostring(value), "\n", "")
				PB4SC.DoImportPhase1()
			end,
			multiline = true,
			width = 'full',
		},
	}
end

function PB4SC:GetExportProfileOptionGroup()
	local function get(info)
		local id = info[#info]
		return self.db.profile.global[id]
	end
	local function set(info, value)
		local id = info[#info]
		self.db.profile.global[id] = value
		
		self:UpdateFrames()
	end
	local function hidden(info)
		return not self:IsEnabled()
	end
	return	{
		export_profile_select = {
			type = 'select',
			name = L["Profiles"],
			desc = L["Select which profile to export."],
			order = 31,
			get = function(info)
				return PB4SC.profile_to_export
			end,
			set = function(info, value)
				PB4SC.profile_to_export = value
				PB4SC.export_mode = "profile"
				PB4SC.DoExport()
			end,
			values = function(info)
				local t = {}
				for name in pairs(PitBull4.db.profiles) do
					t[name] = name
				end
				return t
			end,
			width = 'double',
		},
		export_profile_button = {
			type = 'execute',
			name = L['Export'],
			desc = L['Export'],
			order = 32,
			func = function(info)
				PB4ShareConfigExportBox()
			end,
		},
	}
end


function PB4SC:GetExportLayoutOptionGroup()
return {
	export_layout_select = {
		type = 'multiselect',
		dialogControl = 'Dropdown',
		name = L["Layouts"],
		desc = L["Select which layouts to export."],
		order = 41,
		get = function(info, keyname)
			--return PB4SC.layouts_to_export[keyname] or nil
			return PB4SC:OptionsLayoutValueGet(keyname)
		end,
		set = function(info,keyname,state)
			--PB4SC.layouts_to_export[keyname] = state
			PB4SC:OptionsLayoutValueSet(keyname, state)
			PB4SC.export_mode = "layout"
			PB4SC:Debug(fmt("Value of layouts_to_export[%s] is now %s.", tostring(keyname), tostring(state)))
			PB4SC.DoExport()
		end,
		width = 'double',
		values = function(info)
			return PB4SC.OptionsLayoutValues()
		end,
	},
	export_layout_button = {
		type = 'execute',
		name = L['Export'],
		desc = L['Export'],
		order = 42,
		func = function(info)
			PB4ShareConfigExportBox()
		end,
	},
	export_layout_warning = {
		type = 'description',
		name = fmt(L["WARNING: WoW can crash if you don't properly CLOSE the dropdown before hitting the %s button. This is an Ace3- or Blizzard-bug."],L['Export']),
		order = 40,
	}
	}
end

function PB4SC:GetSendOptions()
	local function hidden(info)
		return not self:IsEnabled()
	end
	return { intro_header = {
		type = 'header',
		name = L["Send In-Game"],
		order = 10,
	},
	intro_description = {
		type = 'description',
		name = L["Send your profile or individual layouts to other players using in-game communication.\n\nTHIS IS CURRENTLY WORK IN PROGRESS AND DOESNT WORK!"],
		order = 11,
	},
	group_send_profile_tochar = {
		type = 'group',
		name = L["Send profile to other player"],
		desc = L["Send profile to other player"],
		inline = true,
		order = 20,
		disabled = hidden,
		args = {
			target_person = {
				type = 'input',
				name = L['Recipient'],
				desc = L['Enter the name of the person you want to send your profile to.'],
				get = function(info)
					return PB4SC.send_recipient_name
				end,
				set = function(info, value)
					PB4SC.send_recipient_name = value
				end,
				width = 'double',
				order = 10,
			},
			export_profile_select = {
				type = 'select',
				name = L["Profiles"],
				desc = L["Select which profile to send."],
				order = 20,
				get = function(info)
					return PB4SC.profile_to_export
				end,
				set = function(info, value)
					PB4SC.profile_to_export = value
					PB4SC.export_mode = "profile"
					PB4SC.DoExport()
				end,
				values = function(info)
					local t = {}
					for name in pairs(PitBull4.db.profiles) do
						t[name] = name
					end
					return t
				end,
				width = 'double',
			},
			export_profile_button = {
				type = 'execute',
				name = L['Send profile'],
				desc = L['Send profile'],
				order = 90,
				func = function(info)
					PB4SC.DoSend()
				end,
			},
		},
	},
	group_send_layouts_tochar = {
		type = 'group',
		name = L["Send layout(s) to other player"],
		desc = L["Send layout(s) to other player"],
		inline = true,
		order = 30,
		disabled = hidden,
		args = {
			target_person = {
				type = 'input',
				name = L["Recipient"],
				desc = L["Enter the name of the person you want to send your layout(s) to."],
				get = function(info)
					return PB4SC.send_recipient_name
				end,
				set = function(info, value)
					PB4SC.send_recipient_name = value
				end,
				order = 10,
				width = 'double',
			},
			export_layout_select = {
				type = 'multiselect',
				dialogControl = 'Dropdown',
				name = L["Layouts"],
				desc = L["Select which layout(s) to send."],
				order = 40,
				get = function(info, keyname)
					return PB4SC.layouts_to_export[keyname] or nil
				end,
				set = function(info,keyname,state)
					PB4SC.layouts_to_export[keyname] = state
					PB4SC.export_mode = "layout"
					PB4SC.DoExport()
				end,
				width = 'double',
				values = function(info)
					return PB4SC.OptionsLayoutValues()
				end,
			},
			export_layout_button = {
				type = 'execute',
				name = L["Send layout(s)"],
				desc = L["Send layout(s)"],
				order = 90,
				func = function(info)
					PB4SC.DoSend()
				end,
			},
		},
	}}
end

function PB4SC:GetReceiveOptions()
	local function hidden(info)
		return not self:IsEnabled()
	end
	return { intro_header = {
		type = 'header',
		name = L["Receive Options"],
		order = 10,
	},
	intro_description = {
		type = 'description',
		name = L["Placeholder"],
		order = 11,
	}}
end


PB4SC:SetGlobalOptionsFunction(function(self)
	return 'main_group', {
		type = 'group',
		childGroups = 'tab',
		name = L['Tools'],
		desc = L['Tools'],
		args = { 
			intro_group = {
				type = 'group',
				childGroups = 'tab',
				name = L['Intro'],
				desc = L['Intro'],
				order = 1,
				args = {
					intro_header = {
						type = 'header',
						name = L['Read Me'],
						order = 10,
					},
					intro_description = {
						type = 'description',
						name = L["This module allows you to import and export profiles and individual layouts.\n\nWARNING: This module is EXPERIMENTAL!\n\nYou *WILL* screw your configuration. Shutdown your client and make backups of your SavedVariables before using this! I'm not kidding.."],
						order = 11,
					},
					intro_acceptwarning = {
						type = 'toggle',
						name = L['I have read above warning and accept that this may destroy my PB4 config.'],
						order = 20,
						width = 'full',
						set = global_option_set,
						get = global_option_get,
					},
				},
			},
			group_import = {
				type = 'group',
				name = L["Import profile or layout(s)"],
				desc = L["Import profile or layout(s)"],
				childGroups = 'tab',
				--inline = true,
				order = 20,
				disabled = hasNotReadWarning,
				args = PB4SC:GetImportOptionGroup(),
			},
			group_export_profile = {
				type = 'group',
				name = L["Export profile"],
				desc = L["Export an entire profile"],
				--inline = true,
				order = 30,
				disabled = hasNotReadWarning,
				args = PB4SC:GetExportProfileOptionGroup(),
			},
			group_export_layout = {
				type = 'group',
				name = L["Export layouts"],
				desc = L["Export one or more layouts of the current profile."],
				--inline = true,
				order = 40,
				disabled = hasNotReadWarning,
				hidden = PB4SC.disableLayoutfunctions,
				args = PB4SC:GetExportLayoutOptionGroup(),
			},
			send_group = {
				type = 'group',
				childGroups = 'tab',
				name = L['Send'],
				desc = L['Send your configuration to other PitBull4 users in-game.'],
				args = PB4SC:GetSendOptions(),
				hidden = PB4SC.hideComm,
				disabled = true,
				order = 30,
			},
			receive_group = {
				type = 'group',
				childGroups = 'tab',
				name = L['Receive'],
				desc = L['Options related to receiving the configurations from other people in-game.'],
				args = PB4SC:GetReceiveOptions(),
				order = 40,
				hidden = PB4SC.hideComm,
				disabled = true, -- this is mostly a placeholder for now
			},
		},
	}
end)
