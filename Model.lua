local _, ns = ...

local Registry = ns.Registry
local CVars = ns.CVars

-- State behind the Custom tab: the game's current values plus the player's unapplied
-- edits. Changing a quality master updates its per-setting values the way the stock
-- menu does.
local Model = { current = {}, pending = {}, modes = {} }
ns.CustomModel = Model

-- Proxies: rows with no setting of their own, read from and written through real ones,
-- like the stock menu's Anti-Aliasing mode. get(value) reads the mode from the real
-- settings (value(name) gives a setting's value, unapplied edits included); set(mode,
-- change) makes the real settings follow a picked mode (change(name, value) stages one).
local AA = Registry.AA
local PROXIES = {
	aamode = {
		available = function(value) return value("ffxAntiAliasingMode") ~= nil end,
		get = function(value)
			local fxaa = tonumber(value("ffxAntiAliasingMode")) or 0
			local msaa = tonumber(Registry.Normalize("MSAAQuality", value("MSAAQuality"))) or 0
			if fxaa > 0 and msaa > 0 then
				return AA.ADVANCED
			elseif msaa > 0 then
				return AA.MULTISAMPLE
			elseif fxaa > 0 then
				return AA.IMAGE
			end
			return AA.NONE
		end,
		set = function(mode, change)
			if mode == AA.NONE or mode == AA.MULTISAMPLE then
				change("ffxAntiAliasingMode", 0)
			end
			if mode == AA.NONE or mode == AA.IMAGE then
				change("MSAAQuality", 0)
			end
		end,
	},
}

function Model:Load()
	self.current = {}
	self.pending = {}
	self.modes = {}
	for _, entry in ipairs(Registry.entries) do
		if not entry.proxy then
			self.current[Registry.Key(entry.name)] = CVars.Read(entry.name)
		end
	end
end

-- A setting's value by name, unapplied edits included; nil if this client hasn't it.
function Model:ValueOf(name)
	local entry = Registry.Get(name)
	return entry and self:Value(entry)
end

function Model:IsAvailable(entry)
	if entry.proxy then
		return PROXIES[entry.proxy].available(function(name) return self:ValueOf(name) end) and Registry.IsShown(entry)
	end
	return self.current[Registry.Key(entry.name)] ~= nil and Registry.IsShown(entry)
end

function Model:Current(entry)
	if entry.proxy then
		return tostring(PROXIES[entry.proxy].get(function(name)
			local real = Registry.Get(name)
			return real and self.current[Registry.Key(real.name)]
		end))
	end
	return self.current[Registry.Key(entry.name)]
end

function Model:Value(entry)
	local key = Registry.Key(entry.name)
	if entry.proxy then
		-- A mode picked but not yet reflected in the real settings (Image-Based picked while
		-- it's at None) stays picked until applied or discarded, like the stock menu.
		return self.modes[key] or tostring(PROXIES[entry.proxy].get(function(name) return self:ValueOf(name) end))
	end
	local pending = self.pending[key]
	if pending ~= nil then
		return pending
	end
	return self.current[key]
end

function Model:IsModified(entry)
	if entry.proxy then
		return self.modes[Registry.Key(entry.name)] ~= nil
	end
	return self.pending[Registry.Key(entry.name)] ~= nil
end

-- Whether a row can be changed: a row under the Anti-Aliasing mode only in the modes
-- that use it (entry.parentModes), greyed otherwise, like the stock menu.
function Model:IsModifiable(entry)
	if not entry.parentModes then
		return true
	end
	local mode = Registry.Get("PROXY_ANTIALIASING")
	if not (mode and self:IsAvailable(mode)) then
		return true
	end
	return entry.parentModes[tonumber(self:Value(mode))] == true
end

local function SetOne(self, entry, value)
	local key = Registry.Key(entry.name)
	value = tostring(value)
	if CVars.SameValue(value, self.current[key]) then
		self.pending[key] = nil
	else
		self.pending[key] = value
	end
end

function Model:Set(entry, value)
	if entry.proxy then
		local key = Registry.Key(entry.name)
		PROXIES[entry.proxy].set(tonumber(value), function(name, realValue)
			local real = Registry.Get(name)
			if real and self:IsAvailable(real) then
				SetOne(self, real, realValue)
			end
		end)
		-- Kept only while the real settings (edits included) don't already read as it.
		value = tostring(value)
		local reads = tostring(PROXIES[entry.proxy].get(function(name) return self:ValueOf(name) end))
		self.modes[key] = not CVars.SameValue(value, reads) and value or nil
		return
	end
	SetOne(self, entry, value)
	if entry.master then
		for _, change in ipairs(Registry.QualityValues(tonumber(value), entry.raid == true)) do
			local sub = Registry.Get(change.name)
			if self:IsAvailable(sub) then
				SetOne(self, sub, change.value)
			end
		end
	end
end

function Model:Changes()
	local changes = {}
	for _, entry in ipairs(Registry.entries) do
		local pending = self.pending[Registry.Key(entry.name)]
		if pending ~= nil then
			changes[#changes + 1] = { name = entry.name, value = pending }
		end
	end
	return changes
end

function Model:Count()
	local count = 0
	for _ in pairs(self.pending) do
		count = count + 1
	end
	return count
end

function Model:Discard()
	self.pending = {}
	self.modes = {}
end

-- Picks up a change made elsewhere (stock menu, console). Drops a pending edit that
-- the game now already matches.
function Model:Refresh(name)
	local key = Registry.Key(name)
	if not Registry.Get(name) then
		return
	end
	self.current[key] = CVars.Read(name)
	if self.pending[key] ~= nil and CVars.SameValue(self.pending[key], self.current[key]) then
		self.pending[key] = nil
	end
end
