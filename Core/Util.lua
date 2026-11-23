-- Velocity Weapon Swing Timers: shared helpers. Loads first.
local ADDON_NAME, NS = ...
NS.ADDON_NAME = ADDON_NAME
NS.features = {}

local Util = {}
NS.Util = Util

local PREFIX = "|cffffcf4dVWST|r: "

function Util.Print(fmt, ...)
  if select("#", ...) > 0 then fmt = string.format(fmt, ...) end
  print(PREFIX .. tostring(fmt))
end

function Util.DumpHeader(title) print("|cffffcf4d====== " .. tostring(title) .. " ======|r") end
function Util.DumpFooter(title) print("|cffffcf4d====== end " .. tostring(title) .. " ======|r") end

local warned = {}
function Util.WarnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  Util.Print("|cffff4040warning|r " .. tostring(msg))
end

-- Report a caught error through the client's error handler (BugSack etc.) without unwinding the caller.
function Util.Raise(context, err)
  local msg = string.format("%s: %s: %s", ADDON_NAME, tostring(context), tostring(err))
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(msg) else error(msg, 0) end
end

function Util.Clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- Round down to a step: Util.RoundTo(1.17, 0.1) -> 1.1
function Util.RoundTo(num, step)
  return math.floor(num / step + 1e-9) * step
end

function Util.DeepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Util.DeepCopy(v) end
  return out
end

-- Fill dst from defaults where missing (deep for nested tables).
function Util.ApplyDefaults(dst, defaults)
  for k, v in pairs(defaults) do
    if dst[k] == nil then
      dst[k] = Util.DeepCopy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" then
      Util.ApplyDefaults(dst[k], v)
    end
  end
  return dst
end

-- true when the value is a Midnight-era secret (Forever in combat); false everywhere else, including nil.
function Util.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A number that is safe to do arithmetic on, or the fallback.
function Util.PlainNumber(v, fallback)
  if Util.IsSecret(v) or type(v) ~= "number" or v ~= v then return fallback end
  return v
end

function Util.ClientInfo()
  local version, build, _, interface = GetBuildInfo()
  return { Version = version, Build = build, Interface = tonumber(interface) or 0, Project = WOW_PROJECT_ID }
end