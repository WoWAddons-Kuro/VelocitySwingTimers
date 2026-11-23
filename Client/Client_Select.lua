-- Velocity Weapon Swing Timers: picks the client flavour and binds it onto NS.Client.
-- WOW_PROJECT_ID is WOW_PROJECT_MAINLINE on Forever as well as retail, so the interface number decides:
-- Classic Era/Anniversary = WOW_PROJECT_CLASSIC; Forever = interface in [16000, 20000).
-- Warns on any INTERFACE method a flavour lacks, and on any flavour method not in INTERFACE.
local ADDON_NAME, NS = ...
local Client, Util = NS.Client, NS.Util

local function SelectFlavour()
  if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
    return "classic_era"
  end
  local interface = Util.ClientInfo().Interface
  if interface >= 16000 and interface < 20000 then return "forever" end
  Util.WarnOnce("flavour", string.format("unrecognised client (project %s, interface %s); using the Forever adaptor",
    tostring(WOW_PROJECT_ID), tostring(interface)))
  return "forever"
end

Client.flavour = SelectFlavour()
local impl = NS.ClientFlavours[Client.flavour]
if not impl then
  Util.WarnOnce("client", "no client implementation for flavour " .. tostring(Client.flavour))
  impl = {}
end

for _, name in ipairs(Client.INTERFACE) do
  if type(impl[name]) == "function" then
    Client[name] = impl[name]
  else
    Util.WarnOnce("client:" .. name, Client.flavour .. " client is missing " .. name)
    Client[name] = function() return nil end
  end
end
NS.features["Client." .. Client.flavour] = true

for flavour, t in pairs(NS.ClientFlavours) do
  for name in pairs(t) do
    local listed = false
    for _, n in ipairs(Client.INTERFACE) do if n == name then listed = true break end end
    if not listed then Util.WarnOnce("client-extra:" .. flavour .. ":" .. name, flavour .. " client defines " .. name .. " which is not in Client.INTERFACE") end
  end
end