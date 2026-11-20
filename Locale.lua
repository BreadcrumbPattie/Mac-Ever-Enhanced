local _, ns = ...

-- Translations (fork addition). Texts are written in English in the code and looked up by
-- their English text: ns.L("Open Mac-ever") gives the chosen language's version, or the
-- English text itself when there isn't one. Format strings are translated whole, with their
-- %d / %s placeholders kept in the same order.
--
-- The language lives in a custom CVar (Config.wtf) rather than in MaceverDB, because saved
-- variables only load after this addon's files have run, and many texts are read as the
-- files load. Changing the language reloads the interface.
local Locale = { tables = {}, callbacks = {} }
ns.Locale = Locale

Locale.CVAR = "maceverLanguage"
-- id, label (each language's own name)
Locale.LANGUAGES = {
	{ id = "en", label = "English" },
	{ id = "sr", label = "Srpski (latinica)" },
}

local function ReadLanguage()
	local register = (C_CVar and C_CVar.RegisterCVar) or RegisterCVar
	if register then
		pcall(register, Locale.CVAR, "en")
	end
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local ok, value = pcall(get, Locale.CVAR)
	return ok and type(value) == "string" and value or "en"
end

Locale.lang = ReadLanguage()

-- Called by language files: Locale.Register("sr", { ["English text"] = "Translation" })
function Locale.Register(id, strings)
	Locale.tables[id] = strings
end

function ns.L(text)
	local strings = Locale.tables[Locale.lang]
	return strings and strings[text] or text
end

function Locale.Set(id)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	pcall(set, Locale.CVAR, id)
end

-- Code that captured texts early registers here to redo them.
function Locale.OnReady(fn)
	Locale.callbacks[#Locale.callbacks + 1] = fn
end

-- Once the saved data has loaded: pick up a language the CVar didn't give early, then redo
-- anything captured before it was known.
function Locale.Ready()
	Locale.lang = ReadLanguage()
	for _, fn in ipairs(Locale.callbacks) do
		pcall(fn)
	end
end
