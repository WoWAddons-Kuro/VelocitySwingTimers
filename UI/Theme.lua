-- Velocity Swing Timers: textures, fonts, backdrop. Blizzard stock art only (SPEC section 9.2).
-- Statusbar textures: a built-in set that exists on every client we ship to, plus LibSharedMedia-3.0's
-- statusbar list when that library happens to be loaded by another addon (optional dependency, not embedded).
local ADDON_NAME, NS = ...

local Theme = {}
NS.Theme = Theme

Theme.Font = "Fonts\\FRIZQT__.TTF"
Theme.Spark = "Interface\\CastingBar\\UI-CastingBar-Spark"
Theme.Backdrop = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
Theme.BackdropNoBorder = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  tile = true, tileSize = 16,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
Theme.BackdropInset = 4   -- backdrop frame extends this far beyond the bars

-- VWST_TextureKey -> path. Order matters for the picker.
Theme.BUILTIN_TEXTURES = {
  { key = "Blizzard",                      path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { key = "Blizzard Character Skills Bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
  { key = "Blizzard Raid Bar",             path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { key = "Blizzard Cast Bar",             path = "Interface\\CastingBar\\UI-CastingBar-Bar" },
  { key = "Solid",                         path = "Interface\\Buttons\\WHITE8X8" },
}
Theme.DEFAULT_TEXTURE = "Blizzard"

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- Path for a key; falls back to the default when the key is unknown (e.g. a SharedMedia pack was removed).
function Theme.TexturePath(key)
  for _, t in ipairs(Theme.BUILTIN_TEXTURES) do if t.key == key then return t.path end end
  local lsm = LSM()
  if lsm then
    local p = lsm:Fetch("statusbar", key, true)
    if p then return p end
  end
  return Theme.BUILTIN_TEXTURES[1].path
end

-- Every selectable texture: { {key, path}, ... } built-ins first, then SharedMedia sorted by name.
function Theme.TextureList()
  local out, seen = {}, {}
  for _, t in ipairs(Theme.BUILTIN_TEXTURES) do out[#out + 1] = t; seen[t.key] = true end
  local lsm = LSM()
  if lsm then
    local names = {}
    for name, path in pairs(lsm:HashTable("statusbar")) do
      if not seen[name] then names[#names + 1] = { key = name, path = path } end
    end
    table.sort(names, function(a, b) return a.key < b.key end)
    for _, t in ipairs(names) do out[#out + 1] = t end
  end
  return out
end

function Theme.Text(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Theme.Font, size or NS.DB.Global().fontSize or 10, "OUTLINE")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

function Theme.ApplyColor(obj, c)
  if obj.SetTextColor then obj:SetTextColor(c.r, c.g, c.b, c.a or 1)
  elseif obj.SetStatusBarColor then obj:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
  elseif obj.SetVertexColor then obj:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
end