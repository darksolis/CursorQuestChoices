local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end
CIT.EdgeLines = {}

local SOLID = "Interface\\ChatFrame\\ChatFrameBackground"  -- textura blanca sólida

-- Dibuja conexiones como codos (segmento vertical + horizontal), usando solo
-- rectángulos finos alineados a los ejes (confiable en 3.3.5, sin rotaciones).
-- `centers` mapea clave -> { x, y, known } en coords TOPLEFT de `content`
-- (x hacia la derecha, y NEGATIVA hacia abajo).
function CIT.EdgeLines.Draw(content, edges, centers, thickness, linePool)
  thickness = thickness or 2
  local half = thickness / 2
  local used = 0

  local function seg(x, y, w, h, known)
    used = used + 1
    local t = linePool[used]
    if not t then
      t = content:CreateTexture(nil, "BACKGROUND")
      t:SetTexture(SOLID)
      linePool[used] = t
    end
    if known then
      t:SetVertexColor(0.25, 0.85, 0.80, 0.85)
    else
      t:SetVertexColor(0.40, 0.40, 0.46, 0.5)
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
    t:SetWidth(w)
    t:SetHeight(h)
    t:Show()
  end

  for _, e in ipairs(edges) do
    local a, b = centers[e.from], centers[e.to]
    if a and b then
      local known = a.known and b.known
      -- Segmento vertical sobre la columna de A, entre las filas de A y B.
      local yTop = math.max(a.y, b.y)           -- menos negativo = más arriba
      local vh = math.abs(a.y - b.y)
      if vh > 0 then seg(a.x - half, yTop, thickness, vh, known) end
      -- Segmento horizontal en la fila de B, entre las columnas de A y B.
      local xLeft = math.min(a.x, b.x)
      local hw = math.abs(a.x - b.x)
      if hw > 0 then seg(xLeft, b.y + half, hw, thickness, known) end
    end
  end

  for i = used + 1, #linePool do linePool[i]:Hide() end
end
