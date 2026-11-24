-- Velocity Self Buff Highlights: picks the client implementation for the running game and
-- binds it onto VSBH.Client. Loads after Client.lua and every Client_*.lua.
local ADDON, VSBH = ...
local Client = VSBH.Client

VSBH.loadWarnings = {}
function VSBH.WarnOnce(key, msg)
	if VSBH.loadWarnings[key] then return end
	VSBH.loadWarnings[key] = msg
	print("|cff80c0ffVelocitySelfBuffHighlights|r: " .. msg)
end

local function SelectFlavour()
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
		return "classic_era"
	end
	return "forever"
end

Client.flavour = SelectFlavour()
local impl = VSBH.ClientFlavours[Client.flavour]
if not impl then
	VSBH.WarnOnce("client", "no client implementation for flavour " .. tostring(Client.flavour))
	impl = {}
end

for _, name in ipairs(Client.INTERFACE) do
	if type(impl[name]) == "function" then
		Client[name] = impl[name]
	else
		VSBH.WarnOnce("client:" .. name, Client.flavour .. " client is missing " .. name)
		Client[name] = function() return nil end
	end
end

for flavour, table_ in pairs(VSBH.ClientFlavours) do
	for name in pairs(table_) do
		local listed = false
		for _, n in ipairs(Client.INTERFACE) do if n == name then listed = true break end end
		if not listed then VSBH.WarnOnce("client-extra:" .. flavour .. ":" .. name, flavour .. " client defines " .. name .. " which is not in Client.INTERFACE") end
	end
end