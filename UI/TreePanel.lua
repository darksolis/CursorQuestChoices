local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end
CIT.TreePanel = {}
local TP = CIT.TreePanel

local SOLID = "Interface\\ChatFrame\\ChatFrameBackground"  -- textura blanca sólida
local BASE_CELL = 44   -- px por celda de grilla a escala completa
local MIN_CELL = 22    -- px mínimos por celda al reducir para caber
local TITLE_H = 34     -- alto del título
local SPEC_H = 30      -- alto de la fila de selector de spec
local PAD = 14         -- margen interior
local TAB_HEADER = 24  -- alto del título de cada Tab (dentro del content)
local TAB_COL_GAP = 26 -- separación horizontal entre columnas de Tab
local SECTION_GAP = 48 -- separación entre el árbol del inspeccionado y el tuyo

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 1.5, 0.05

-- Lee la escala guardada, con default 0.75 y recorte al rango permitido.
local function savedScale()
  local db = _G.CoAInspectTreeDB
  local s = db and db.scale
  if type(s) ~= "number" then s = 0.75 end
  if s < SCALE_MIN then s = SCALE_MIN elseif s > SCALE_MAX then s = SCALE_MAX end
  return s
end

local frame, scroll, content

-- Crea el panel una sola vez. Contiene un ScrollFrame con un content interno,
-- una fila de selector de spec y un botón Comparar.
function TP.Get()
  if frame then return frame end
  frame = CreateFrame("Frame", "CoAInspectTreePanel", UIParent)
  frame:SetWidth(360)
  frame:SetHeight(400)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 14,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  frame:SetBackdropColor(0.025, 0.03, 0.045, 0.98)
  frame:SetBackdropBorderColor(0.28, 0.42, 0.50, 1)
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)

  local topBar = frame:CreateTexture(nil, "BORDER")
  topBar:SetTexture(SOLID)
  topBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
  topBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -7)
  topBar:SetHeight(TITLE_H - 5)
  topBar:SetVertexColor(0.045, 0.10, 0.13, 0.96)

  local accent = frame:CreateTexture(nil, "ARTWORK")
  accent:SetTexture(SOLID)
  accent:SetPoint("BOTTOMLEFT", topBar, "BOTTOMLEFT", 0, 0)
  accent:SetPoint("BOTTOMRIGHT", topBar, "BOTTOMRIGHT", 0, 0)
  accent:SetHeight(2)
  accent:SetVertexColor(0.20, 0.82, 0.78, 0.9)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  title:SetText("Character Advancement")
  title:SetTextColor(0.92, 0.96, 1)
  frame.title = title

  -- Botón Comparar (arriba a la derecha).
  local cmp = CreateFrame("Button", nil, frame)
  cmp:SetWidth(82); cmp:SetHeight(20)
  cmp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -11)
  cmp:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, tile = false, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 } })
  cmp.txt = cmp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cmp.txt:SetAllPoints(cmp)
  cmp.txt:SetText("Compare")
  cmp:Hide()
  frame.compareBtn = cmp

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -7)
  close:SetScript("OnClick", function() frame.userHidden = true; frame:Hide() end)
  frame.closeButton = close

  -- Controles de escala del panel: label + [-] [+] [Reset]. Usamos botones
  -- (paso discreto) en vez de slider: un slider hijo del frame que escala se
  -- reescala bajo el cursor al arrastrarlo y se traba. Persistente en la DB.
  local function makeHdrButton(w, text)
    local b = CreateFrame("Button", nil, frame)
    b:SetWidth(w); b:SetHeight(18)
    b:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, tile = false, edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    b:SetBackdropColor(0.10, 0.10, 0.13, 0.9)
    b:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.txt:SetAllPoints(b)
    b.txt:SetText(text)
    return b
  end

  local resetBtn = makeHdrButton(44, "Reset")
  resetBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_H + 7))
  local plusBtn = makeHdrButton(20, "+")
  plusBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
  local minusBtn = makeHdrButton(20, "-")
  minusBtn:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)

  local scaleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scaleLabel:SetPoint("RIGHT", minusBtn, "LEFT", -6, 0)
  frame.scaleLabel = scaleLabel

  local function setScale(v)
    v = math.floor(v * 100 + 0.5) / 100        -- redondea a 1% para evitar ruido
    if v < SCALE_MIN then v = SCALE_MIN elseif v > SCALE_MAX then v = SCALE_MAX end
    frame:SetScale(v)
    scaleLabel:SetText("Scale " .. math.floor(v * 100 + 0.5) .. "%")
    if _G.CoAInspectTreeDB then _G.CoAInspectTreeDB.scale = v end
  end
  frame.setScale = setScale

  minusBtn:SetScript("OnClick", function() setScale(frame:GetScale() - SCALE_STEP) end)
  plusBtn:SetScript("OnClick", function() setScale(frame:GetScale() + SCALE_STEP) end)
  resetBtn:SetScript("OnClick", function() setScale(0.75) end)

  setScale(savedScale())

  -- Fila de selector de spec (botones propios, no dependemos del panel nativo).
  frame.specRow = CreateFrame("Frame", nil, frame)
  frame.specRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + 3))
  frame.specRow:SetHeight(SPEC_H)
  frame.specRow:SetWidth(240)
  frame.specButtons = {}

  scroll = CreateFrame("ScrollFrame", "CoAInspectTreeScroll", frame)
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H + SPEC_H))
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + 14), PAD)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, (content and content:GetHeight() or 0) - self:GetHeight())
    local nextValue = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 34))
    self:SetVerticalScroll(nextValue)
    if frame.scrollThumb then
      local trackH = math.max(1, frame.scrollTrack:GetHeight() - frame.scrollThumb:GetHeight())
      frame.scrollThumb:ClearAllPoints()
      frame.scrollThumb:SetPoint("TOP", frame.scrollTrack, "TOP", 0, -(maxScroll > 0 and (nextValue / maxScroll) * trackH or 0))
    end
  end)

  content = CreateFrame("Frame", "CoAInspectTreeContent", scroll)
  content:SetWidth(1)
  content:SetHeight(1)
  scroll:SetScrollChild(content)

  local track = frame:CreateTexture(nil, "BACKGROUND")
  track:SetTexture(SOLID)
  track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_H + SPEC_H))
  track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
  track:SetWidth(6)
  track:SetVertexColor(0.08, 0.10, 0.14, 0.9)
  frame.scrollTrack = track

  local thumb = frame:CreateTexture(nil, "ARTWORK")
  thumb:SetTexture(SOLID)
  thumb:SetPoint("TOP", track, "TOP", 0, 0)
  thumb:SetWidth(6); thumb:SetHeight(42)
  thumb:SetVertexColor(0.20, 0.62, 0.62, 0.9)
  frame.scrollThumb = thumb

  frame.content = content
  frame.scroll = scroll
  frame.buttons = {}      -- pool de NodeButton
  frame.buttonsById = {}  -- clave prefijada -> button (última render)
  frame.linePool = {}     -- pool de texturas de líneas de conexión
  frame:Hide()
  return frame
end

-- Ancla el panel al borde derecho del inspect por la esquina superior.
function TP.AttachTo(inspectFrame)
  local f = TP.Get()
  f:ClearAllPoints()
  local screenW = UIParent:GetWidth() or 1024
  local right = inspectFrame:GetRight() or 0
  local estimatedW = f:GetWidth() * f:GetScale()
  if right + estimatedW + 12 <= screenW then
    f:SetPoint("TOPLEFT", inspectFrame, "TOPRIGHT", 6, 0)
  else
    f:SetPoint("TOPRIGHT", inspectFrame, "TOPLEFT", -6, 0)
  end
end

function TP.Show() local f = TP.Get(); if not f.userHidden then f:Show() end end
function TP.Hide() if frame then frame:Hide() end end

-- Configura el botón Comparar: estado on/off y callback de clic.
function TP.SetCompare(isOn, onClick)
  local f = TP.Get()
  local b = f.compareBtn
  if isOn then
    b:SetBackdropColor(0.14, 0.45, 0.42, 0.95)
    b:SetBackdropBorderColor(0.25, 0.85, 0.80, 1)
  else
    b:SetBackdropColor(0.10, 0.10, 0.13, 0.9)
    b:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
  end
  b:SetScript("OnClick", function() if onClick then onClick() end end)
  b:Show()
end

-- Dibuja los botones de selección de spec.
function TP.SetSpecs(specs, current, onClick)
  local f = TP.Get()
  for i = 1, #f.specButtons do f.specButtons[i]:Hide() end
  local x = 0
  for i, slot in ipairs(specs or {}) do
    local b = f.specButtons[i]
    if not b then
      b = CreateFrame("Button", nil, f.specRow)
      b:SetWidth(28); b:SetHeight(20)
      b:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 } })
      b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.txt:SetAllPoints(b)
      f.specButtons[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("LEFT", f.specRow, "LEFT", x, 0)
    b.txt:SetText(tostring(slot))
    if slot == current then
      b:SetBackdropColor(0.14, 0.45, 0.42, 0.95)
      b:SetBackdropBorderColor(0.25, 0.85, 0.80, 1)
    else
      b:SetBackdropColor(0.10, 0.10, 0.13, 0.9)
      b:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
    end
    b:SetScript("OnClick", function() if onClick then onClick(slot) end end)
    b:Show()
    x = x + 32
  end
end

-- Obtiene (o crea) el botón i del pool.
local function acquireButton(f, i)
  local b = f.buttons[i]
  if not b then
    b = CIT.NodeButton.Create(f.content)
    f.buttons[i] = b
  end
  b:Show()
  return b
end

-- Obtiene (o crea) el header i del pool de títulos de Tab.
local function acquireHeader(f, i)
  f.headers = f.headers or {}
  local h = f.headers[i]
  if not h then
    h = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetTextColor(0.45, 0.90, 0.85)
    f.headers[i] = h
  end
  h:Show()
  return h
end

-- Suma de columnas visibles (para elegir escala) y nº de tabs mostrados,
-- dado el `order` (lista de tabs) ya calculado.
local function shownCols(model, order)
  local bounds = CIT.TreeModel.bounds(model)
  local byName = {}
  for _, ti in ipairs(bounds.tabs) do byName[ti.name] = ti end
  local cols, tabs = 0, 0
  for _, name in ipairs(order) do
    local ti = byName[name]
    if ti then cols = cols + (ti.maxX - ti.minX + 1); tabs = tabs + 1 end
  end
  return cols, tabs
end

-- Coloca las columnas de un modelo (según `order`) desde startX. Usa prefijo de
-- clave (para no colisionar IDs entre árboles) y prefijo de header ("YOU · ").
-- Agrega los rects {x,w} de cada columna a `rects`. Devuelve
-- (nuevoX, maxColH, btnIndex, headerIndex).
local function renderColumns(f, model, order, keyPrefix, headerPrefix, startX, cell, iconSize, btnIndex, headerIndex, rects, placed)
  local bounds = CIT.TreeModel.bounds(model)
  local byName = {}
  for _, ti in ipairs(bounds.tabs) do byName[ti.name] = ti end

  local xOffset = startX
  local maxColH = 0
  for _, tabName in ipairs(order) do
    local tabInfo = byName[tabName]
    if tabInfo then
      headerIndex = headerIndex + 1
      local header = acquireHeader(f, headerIndex)
      header:ClearAllPoints()
      header:SetPoint("TOPLEFT", f.content, "TOPLEFT", xOffset, 0)
      header:SetText(headerPrefix .. string.upper(tabName))

      for id, node in pairs(model.nodes) do
        if node.tab == tabName then
          btnIndex = btnIndex + 1
          local b = acquireButton(f, btnIndex)
          b:SetWidth(iconSize)
          b:SetHeight(iconSize)
          CIT.NodeButton.Style(b, node)
          b:ClearAllPoints()
          -- Normalizar al origen del tab para columnas compactas y parejas.
          local px = xOffset + ((node.x or 0) - tabInfo.minX) * cell
          local py = -TAB_HEADER - (((node.y or 0) - tabInfo.minY) * cell)
          b:SetPoint("TOPLEFT", f.content, "TOPLEFT", px, py)
          f.buttonsById[keyPrefix .. id] = b
          placed[keyPrefix .. id] = { px = px, py = py, known = node.known }
        end
      end

      local colW = (tabInfo.maxX - tabInfo.minX + 1) * cell
      local colH = TAB_HEADER + (tabInfo.maxY - tabInfo.minY + 1) * cell
      if colH > maxColH then maxColH = colH end
      rects[#rects + 1] = { x = xOffset, w = colW }
      xOffset = xOffset + colW + TAB_COL_GAP
    end
  end
  return xOffset, maxColH, btnIndex, headerIndex
end

-- Dibuja divisores verticales en el hueco entre cada par de columnas contiguas.
local function drawDividers(f, rects, height)
  f.dividers = f.dividers or {}
  for i = 1, #f.dividers do f.dividers[i]:Hide() end
  for i = 1, #rects - 1 do
    local rightEdge = rects[i].x + rects[i].w
    local nextStart = rects[i + 1].x
    local mid = (rightEdge + nextStart) / 2
    local d = f.dividers[i]
    if not d then
      d = f.content:CreateTexture(nil, "BACKGROUND")
      f.dividers[i] = d
    end
    d:SetTexture(SOLID)
    d:SetVertexColor(0.18, 0.28, 0.34, 0.55)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", f.content, "TOPLEFT", mid - 1, 0)
    d:SetWidth(2)
    d:SetHeight(height)
    d:Show()
  end
end

-- Renderiza el árbol del inspeccionado (Class + spec del `slot`) y, si `myModel`
-- viene dado, tu propio árbol a la derecha (headers "YOU · ..."). Dibuja un
-- divisor entre cada par de columnas contiguas.
function CIT.TreePanel.Render(model, slot, myModel, mySlot)
  local f = CIT.TreePanel.Get()
  for i = 1, #f.buttons do f.buttons[i]:Hide() end
  if f.headers then for i = 1, #f.headers do f.headers[i]:Hide() end end
  f.buttonsById = {}

  local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1024
  local sh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768

  local order1 = CIT.TreeModel.layoutTabs(model, slot)
  local order2 = myModel and CIT.TreeModel.layoutTabs(myModel, mySlot) or nil

  local cols1, tabs1 = shownCols(model, order1)
  local cols2, tabs2 = 0, 0
  if myModel then cols2, tabs2 = shownCols(myModel, order2) end
  local totalCols = cols1 + cols2
  local totalTabs = tabs1 + tabs2

  local widthFactor = myModel and 0.75 or 0.55
  local nGaps = math.max(0, totalTabs - 1)
  local extra = myModel and SECTION_GAP or 0
  local maxContentW = math.floor(sw * widthFactor) - nGaps * TAB_COL_GAP - extra
  local cell = CIT.TreeModel.fitScale(totalCols, BASE_CELL, maxContentW, MIN_CELL)
  local iconSize = math.max(14, cell - 8)

  local rects, placed = {}, {}
  local x, maxColH, btnIndex, headerIndex = renderColumns(f, model, order1, "t", "", 0, cell, iconSize, 0, 0, rects, placed)

  if myModel then
    -- x trae un TAB_COL_GAP de más al final; convertirlo en el hueco de sección.
    local myStartX = x - TAB_COL_GAP + SECTION_GAP
    local x2, h2
    x2, h2, btnIndex, headerIndex = renderColumns(f, myModel, order2, "m", "YOU · ", myStartX, cell, iconSize, btnIndex, headerIndex, rects, placed)
    if h2 > maxColH then maxColH = h2 end
    x = x2
  end

  local contentW = math.max(1, x - TAB_COL_GAP)
  local contentH = math.max(1, maxColH + 10)
  f.content:SetWidth(contentW)
  f.content:SetHeight(contentH)

  -- Líneas de conexión: centros en coords TOPLEFT (Y negativa hacia abajo).
  local centers = {}
  for key, p in pairs(placed) do
    centers[key] = { x = p.px + iconSize / 2, y = p.py - iconSize / 2, known = p.known }
  end
  local edges = {}
  for _, e in ipairs(model.edges) do edges[#edges + 1] = { from = "t" .. e.from, to = "t" .. e.to } end
  if myModel then
    for _, e in ipairs(myModel.edges) do edges[#edges + 1] = { from = "m" .. e.from, to = "m" .. e.to } end
  end
  CIT.EdgeLines.Draw(f.content, edges, centers, 2, f.linePool)

  drawDividers(f, rects, maxColH)

  local headerTotal = TITLE_H + SPEC_H
  local maxPanelInner = math.floor(sh * 0.9) - headerTotal - PAD
  local innerH = math.min(contentH, maxPanelInner)
  f:SetWidth(contentW + 2 * PAD)
  f:SetHeight(innerH + headerTotal + PAD)
  local maxScroll = math.max(0, contentH - innerH)
  if maxScroll > 0 then
    f.scrollTrack:Show(); f.scrollThumb:Show()
    local ratio = math.max(0.12, math.min(1, innerH / contentH))
    f.scrollThumb:SetHeight(math.max(26, f.scrollTrack:GetHeight() * ratio))
  else
    f.scroll:SetVerticalScroll(0)
    f.scrollTrack:Hide(); f.scrollThumb:Hide()
  end
end
