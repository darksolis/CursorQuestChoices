local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end
CIT.CAReader = {}
local R = CIT.CAReader

local function CA()  return _G.C_CharacterAdvancement end
local function CAU() return _G.CharacterAdvancementUtil end

-- className DBC de la unidad (p.ej. "Guardian"), o nil.
function R.className(unit)
  local _, classFile = UnitClass(unit)
  local u = CAU()
  if not (u and type(u.GetClassDBCByFile) == "function") then return nil end
  local ok, name = pcall(u.GetClassDBCByFile, classFile)
  if ok then return name end
  return nil
end

-- Árbol completo de la clase (lista de nodos crudos). {} si falla.
-- GetTalentsByClass solo devuelve las entries de tipo "Talent", omitiendo los
-- nodos-habilidad de la grilla (confirmado in-game: quedaban ~12 aprendidos sin
-- nodo). GetEntriesByClass(className, tabName, false) trae TODAS las entries de
-- un tab (talentos + habilidades) con posición. Descubrimos los nombres de tabs
-- con GetTalentsByClass y luego pedimos cada tab completo. Fallback: merge de
-- GetTalentsByClass si GetEntriesByClass no existe.
function R.classTree(className, slot)
  local api = CA()
  if not (api and className) then return {} end

  -- 1) Nombres de tabs (specs + Class) desde GetTalentsByClass.
  local tabs, seenTab = {}, {}
  if type(api.GetTalentsByClass) == "function" then
    local ok, entries = pcall(api.GetTalentsByClass, className, slot, false)
    if ok and type(entries) == "table" then
      for _, e in ipairs(entries) do
        if e.Tab and not seenTab[e.Tab] then
          seenTab[e.Tab] = true
          tabs[#tabs + 1] = e.Tab
        end
      end
    end
  end

  local seen, out = {}, {}
  local function absorb(entries)
    if type(entries) ~= "table" then return end
    for _, e in ipairs(entries) do
      if e.ID and not seen[e.ID] then
        seen[e.ID] = true
        out[#out + 1] = e
      end
    end
  end

  -- 2) Todas las entries por tab (grilla completa).
  if type(api.GetEntriesByClass) == "function" and #tabs > 0 then
    for _, tab in ipairs(tabs) do
      local ok, entries = pcall(api.GetEntriesByClass, className, tab, false)
      if ok then absorb(entries) end
    end
  end

  -- 3) Fallback: merge de GetTalentsByClass (ambos modos) si lo anterior no dio.
  if #out == 0 and type(api.GetTalentsByClass) == "function" then
    for _, withMasteries in ipairs({ false, true }) do
      local ok, entries = pcall(api.GetTalentsByClass, className, slot, withMasteries)
      if ok then absorb(entries) end
    end
  end

  return out
end

-- Build aprendida del unit en esa spec: { [EntryId] = { rank, maxRank } }.
function R.unitBuild(unit, slot)
  local api = CA()
  local out = {}
  if not (api and type(api.GetInspectedBuild) == "function") then return out end
  local ok, entries = pcall(api.GetInspectedBuild, unit, slot)
  if not (ok and type(entries) == "table") then return out end
  for _, e in ipairs(entries) do
    if e.EntryId then
      local rank, maxRank = e.Rank, nil
      if type(api.UnitTalentRankByID) == "function" then
        local rok, r, m = pcall(api.UnitTalentRankByID, unit, e.EntryId, slot)
        if rok then
          if type(r) == "number" then rank = r end
          maxRank = m
        end
      end
      out[e.EntryId] = { rank = rank, maxRank = maxRank }
    end
  end
  return out
end

-- Build del PROPIO personaje ("player") para comparar. Intenta GetInspectedBuild
-- primero; si viene vacío (puede no aplicar a uno mismo), cae a consultar el
-- rango real de cada nodo con UnitTalentRankByID("player", ...), que sí devuelve
-- rango para el jugador local. Devuelve { [id] = { rank, maxRank } }.
function R.playerBuild(slot, rawTree)
  local viaInspect = R.unitBuild("player", slot)
  local n = 0
  for _ in pairs(viaInspect) do n = n + 1 end
  if n > 0 then return viaInspect end

  local api = CA()
  local out = {}
  if api and type(api.UnitTalentRankByID) == "function" and type(rawTree) == "table" then
    for _, node in ipairs(rawTree) do
      local id = node.ID
      if id then
        local ok, rank, maxRank = pcall(api.UnitTalentRankByID, "player", id, slot)
        if ok and type(rank) == "number" and rank > 0 then
          out[id] = { rank = rank, maxRank = maxRank }
        end
      end
    end
  end
  return out
end

-- (activeSpec, unlockedSpecs) del unit inspeccionado.
function R.inspectInfo(unit)
  local api = CA()
  if not (api and type(api.GetInspectInfo) == "function") then return nil, nil end
  local ok, active, unlocked = pcall(api.GetInspectInfo, unit)
  if ok then return active, unlocked end
  return nil, nil
end
