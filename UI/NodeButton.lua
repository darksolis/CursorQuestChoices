local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end
CIT.NodeButton = {}

local NODE_SIZE = 32
local SOLID = "Interface\\ChatFrame\\ChatFrameBackground"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

local COLORS = {
  TEAL   = { 0.20, 0.82, 0.78 }, RED = { 0.90, 0.25, 0.25 },
  GREEN  = { 0.35, 0.85, 0.35 }, BLUE = { 0.30, 0.55, 0.95 },
  PURPLE = { 0.68, 0.40, 0.90 }, YELLOW = { 0.95, 0.82, 0.25 },
  ORANGE = { 0.95, 0.55, 0.20 }, PINK = { 0.95, 0.45, 0.75 },
  WHITE  = { 0.90, 0.90, 0.90 },
}
local function colorFor(name) return COLORS[name] or { 0.85, 0.70, 0.30 } end

local function iconTexture(icon)
  if type(icon) == "number" then return icon end
  if type(icon) ~= "string" or icon == "" then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  if string.find(icon, "\\") or string.find(icon, "/") then return icon end
  return "Interface\\Icons\\" .. icon
end

local function spellIdFor(node)
  local sp = node.spells
  if type(sp) ~= "table" then return nil end
  local function idOf(v)
    if type(v) == "number" then return v end
    if type(v) == "table" then return v.ID or v.SpellID or v.Spell end
  end
  local r = (node.rank and node.rank > 0) and node.rank or 1
  local cand = idOf(sp[r]) or idOf(sp[1])
  if cand then return cand end
  for _, v in pairs(sp) do local id = idOf(v); if id then return id end end
end

function CIT.NodeButton.Create(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(NODE_SIZE); b:SetHeight(NODE_SIZE)

  b.shadow = b:CreateTexture(nil, "BACKGROUND")
  b.shadow:SetTexture(SOLID)
  b.shadow:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
  b.shadow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
  b.shadow:SetVertexColor(0, 0, 0, 0.65)

  b.plate = b:CreateTexture(nil, "BACKGROUND")
  b.plate:SetTexture(SOLID)
  b.plate:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
  b.plate:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
  b.plate:SetVertexColor(0.035, 0.04, 0.055, 1)

  b.border = b:CreateTexture(nil, "BORDER")
  b.border:SetTexture(SOLID)
  b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
  b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)

  b.gloss = b:CreateTexture(nil, "OVERLAY")
  b.gloss:SetTexture(SOLID)
  b.gloss:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.gloss:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
  b.gloss:SetHeight(5)
  b.gloss:SetVertexColor(1, 1, 1, 0.10)

  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture(GLOW)
  b.glow:SetBlendMode("ADD")
  b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.glow:SetWidth(60); b.glow:SetHeight(60)
  b.glow:Hide()

  b.rankPlate = b:CreateTexture(nil, "OVERLAY")
  b.rankPlate:SetTexture(SOLID)
  b.rankPlate:SetVertexColor(0.015, 0.015, 0.02, 0.92)
  b.rankPlate:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)

  b.rank = b:CreateFontString(nil, "OVERLAY")
  b.rank:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  b.rank:SetPoint("CENTER", b.rankPlate, "CENTER", 0, 0)

  b:SetHighlightTexture(SOLID)
  local hl = b:GetHighlightTexture()
  if hl then hl:SetBlendMode("ADD"); hl:SetVertexColor(1, 1, 1, 0.18); hl:SetAllPoints(b) end
  return b
end

function CIT.NodeButton.Style(button, node)
  button.nodeData = node
  button.icon:SetTexture(iconTexture(node.icon))
  local c = colorFor(node.color)

  if node.known then
    button.icon:SetDesaturated(false); button.icon:SetVertexColor(1, 1, 1); button.icon:SetAlpha(1)
    button.border:SetVertexColor(c[1], c[2], c[3], 1)
    button.plate:SetVertexColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 1)
    button.glow:SetVertexColor(c[1], c[2], c[3], 0.55); button.glow:Show()
  else
    button.icon:SetDesaturated(true); button.icon:SetVertexColor(0.72, 0.72, 0.76); button.icon:SetAlpha(0.30)
    button.border:SetVertexColor(0.20, 0.22, 0.28, 1)
    button.plate:SetVertexColor(0.025, 0.028, 0.04, 1)
    button.glow:Hide()
  end

  if node.known and node.rank and node.rank > 0 then
    button.rank:SetText(node.maxRank and (node.rank .. "/" .. node.maxRank) or tostring(node.rank))
    if node.maxRank and node.rank >= node.maxRank then button.rank:SetTextColor(1, 0.82, 0.15)
    else button.rank:SetTextColor(0.95, 0.98, 1) end
    button.rankPlate:SetWidth(button.rank:GetStringWidth() + 6); button.rankPlate:SetHeight(13)
    button.rankPlate:Show(); button.rank:Show()
  else
    button.rankPlate:Hide(); button.rank:Hide()
  end

  button:SetScript("OnEnter", function(self)
    self.gloss:SetVertexColor(1, 1, 1, 0.20)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local sid = spellIdFor(node)
    local shown = false
    if sid then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. sid) end
    if not shown then GameTooltip:SetText(node.name or "Unknown Talent", 1, 0.82, 0.15) end
    if node.known and node.rank and node.rank > 0 then
      GameTooltip:AddLine("Rank " .. (node.maxRank and (node.rank .. "/" .. node.maxRank) or tostring(node.rank)), 0.25, 0.9, 0.82)
    else
      GameTooltip:AddLine("Not learned", 0.62, 0.64, 0.70)
    end
    if node.tab then GameTooltip:AddLine(node.tab, 0.48, 0.62, 0.75) end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(self) self.gloss:SetVertexColor(1, 1, 1, 0.10); GameTooltip:Hide() end)
end
