local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end
CIT.Debug = {}

-- Resumen por tab del target inspeccionado: total de nodos y cuántos aprendidos.
function CIT.Debug.dumpTarget()
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no CoA class on target (inspect a player first)."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1
  local tree = CIT.CAReader.classTree(cn, active)
  if #tree == 0 then CIT.Log("debug: empty tree (data not loaded yet?)."); return end

  local byId, total, order = {}, {}, {}
  for _, n in ipairs(tree) do
    byId[n.ID] = n.Tab
    if total[n.Tab] == nil then total[n.Tab] = 0; order[#order + 1] = n.Tab end
    total[n.Tab] = total[n.Tab] + 1
  end

  local build = CIT.CAReader.unitBuild(u, active)
  local learned, totalLearned = {}, 0
  for id in pairs(build) do
    local tb = byId[id]
    if tb then learned[tb] = (learned[tb] or 0) + 1 end
    totalLearned = totalLearned + 1
  end

  CIT.Log("class=" .. tostring(cn) .. " slot=" .. tostring(active)
    .. " nodes=" .. #tree .. " learned=" .. totalLearned)
  for _, tb in ipairs(order) do
    CIT.Log("  TAB " .. tb .. " total=" .. total[tb] .. " learned=" .. (learned[tb] or 0))
  end
end

-- Lista los nodos del tab "Class" con posición y marca de aprendido.
function CIT.Debug.dumpClass()
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no CoA class on target."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1
  local tree = CIT.CAReader.classTree(cn, active)
  local build = CIT.CAReader.unitBuild(u, active)
  local n = 0
  for _, node in ipairs(tree) do
    if node.Tab == "Class" then
      n = n + 1
      local mark = build[node.ID] and "*" or "-"
      CIT.Log(mark .. " " .. node.ID .. " " .. (node.Name or "?")
        .. " x=" .. tostring(node.PositionX) .. " y=" .. tostring(node.PositionY))
    end
  end
  CIT.Log("Class nodes: " .. n)
end

-- Lista las funciones disponibles en las tablas de la API CoA, para descubrir
-- de dónde sacar el árbol de clase real.
function CIT.Debug.dumpAPI()
  local function dumpTbl(name, t)
    if type(t) ~= "table" then CIT.Log(name .. " = nil"); return end
    local names = {}
    for k, v in pairs(t) do
      if type(v) == "function" then names[#names + 1] = k end
    end
    table.sort(names)
    CIT.Log(name .. " (" .. #names .. " funcs):")
    local line = ""
    for _, n in ipairs(names) do
      if #line + #n + 2 > 90 then CIT.Log("  " .. line); line = "" end
      line = (line == "") and n or (line .. ", " .. n)
    end
    if line ~= "" then CIT.Log("  " .. line) end
  end
  dumpTbl("C_CharacterAdvancement", _G.C_CharacterAdvancement)
  dumpTbl("CharacterAdvancementUtil", _G.CharacterAdvancementUtil)
end

-- Muestra los EntryId aprendidos que NO aparecen en el árbol de GetTalentsByClass
-- (los que "faltan"), para identificar de qué árbol vienen.
function CIT.Debug.dumpMissing()
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no class."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1
  local tree = CIT.CAReader.classTree(cn, active)
  local inTree = {}
  for _, n in ipairs(tree) do inTree[n.ID] = true end
  local build = CIT.CAReader.unitBuild(u, active)
  local miss = {}
  for id in pairs(build) do if not inTree[id] then miss[#miss + 1] = id end end
  CIT.Log("learned NOT in tree: " .. #miss)
  if #miss > 0 then
    CIT.Log(table.concat(miss, ",", 1, math.min(#miss, 25)))
  end
end

-- Prueba funciones alternativas de la API para hallar el árbol de clase real:
-- reporta, por cada una, cuántas entries trae, el desglose por Tab, y cuántos de
-- los EntryId aprendidos "faltantes" aparecen (para confirmar la fuente correcta).
function CIT.Debug.dumpEntries()
  local api = _G.C_CharacterAdvancement
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no class."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1

  -- Conjunto de aprendidos que faltan en GetTalentsByClass (referencia).
  local tree = CIT.CAReader.classTree(cn, active)
  local inTree = {}
  for _, n in ipairs(tree) do inTree[n.ID] = true end
  local build = CIT.CAReader.unitBuild(u, active)
  local miss, missN = {}, 0
  for id in pairs(build) do if not inTree[id] then miss[id] = true; missN = missN + 1 end end

  local function analyze(label, res)
    if type(res) ~= "table" then CIT.Log(label .. " -> " .. type(res)); return end
    local n, total, ord, found = 0, {}, {}, 0
    for _, e in ipairs(res) do
      n = n + 1
      local tb = e.Tab or "?"
      if total[tb] == nil then total[tb] = 0; ord[#ord + 1] = tb end
      total[tb] = total[tb] + 1
      if e.ID and miss[e.ID] then found = found + 1 end
    end
    CIT.Log(label .. " -> " .. n .. " entries; faltantes: " .. found .. "/" .. missN)
    local line = ""
    for _, tb in ipairs(ord) do
      local seg = tb .. "=" .. total[tb]
      if #line + #seg + 2 > 90 then CIT.Log("   " .. line); line = "" end
      line = (line == "") and seg or (line .. ", " .. seg)
    end
    if line ~= "" then CIT.Log("   " .. line) end
  end

  local function tryFn(label, fn, ...)
    if type(fn) ~= "function" then CIT.Log(label .. " = nil"); return end
    local ok, res = pcall(fn, ...)
    if not ok then CIT.Log(label .. " error: " .. tostring(res)); return end
    analyze(label, res)
  end

  -- Nombres de tabs desde GetTalentsByClass.
  local tabs, seen = {}, {}
  local ok0, base = pcall(api.GetTalentsByClass, cn, active, false)
  if ok0 and type(base) == "table" then
    for _, e in ipairs(base) do
      if e.Tab and not seen[e.Tab] then seen[e.Tab] = true; tabs[#tabs + 1] = e.Tab end
    end
  end

  -- GetEntriesByClass(className, tabName, withMasteries) por tab: ¿trae TODAS
  -- las entries (incl. las no-talento) con posición, cubriendo los faltantes?
  CIT.Log("GetEntriesByClass por tab (faltan " .. missN .. "):")
  local totalFound = 0
  for _, tab in ipairs(tabs) do
    local ok, res = pcall(api.GetEntriesByClass, cn, tab, false)
    if ok and type(res) == "table" then
      local n, found, hasPos = 0, 0, false
      for _, e in ipairs(res) do
        n = n + 1
        if e.ID and miss[e.ID] then found = found + 1 end
        if e.PositionX ~= nil then hasPos = true end
      end
      totalFound = totalFound + found
      CIT.Log("  " .. tab .. " -> " .. n .. " entries, faltantes_aqui=" .. found
        .. ", hasPos=" .. tostring(hasPos))
    else
      CIT.Log("  " .. tab .. " error: " .. tostring(res))
    end
  end
  CIT.Log("total faltantes cubiertos por GetEntriesByClass: " .. totalFound .. "/" .. missN)
end

-- Para cada aprendido que NO está en el árbol, busca su Tab/Class en el dump
-- global y si es talento o mastery. Revela de dónde salen los nodos que faltan.
function CIT.Debug.findMissing()
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no class."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1
  local tree = CIT.CAReader.classTree(cn, active)
  local inTree = {}
  for _, n in ipairs(tree) do inTree[n.ID] = true end
  local build = CIT.CAReader.unitBuild(u, active)
  local miss = {}
  for id in pairs(build) do if not inTree[id] then miss[id] = true end end

  local api = _G.C_CharacterAdvancement
  local info = {}
  local all = api.GetAllEntries and api.GetAllEntries()
  if type(all) == "table" then
    for _, e in ipairs(all) do
      if e.ID and miss[e.ID] then info[e.ID] = (tostring(e.Class) .. "/" .. tostring(e.Tab)) end
    end
  end
  for id in pairs(miss) do
    local isTal = api.IsTalentID and api.IsTalentID(id)
    local isMas = api.IsMastery and api.IsMastery(id)
    CIT.Log(id .. " " .. (info[id] or "notfound")
      .. " talent=" .. tostring(isTal) .. " mastery=" .. tostring(isMas))
  end
end

-- Por cada tab, dumpea las combinaciones distintas de Type/NodeType/Quality/Color
-- (con conteo) para identificar la categoría de los talentos hero y poder filtrarla.
function CIT.Debug.dumpCats()
  local api = _G.C_CharacterAdvancement
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no class."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1
  local tabs, seen = {}, {}
  local ok, base = pcall(api.GetTalentsByClass, cn, active, false)
  if ok and type(base) == "table" then
    for _, e in ipairs(base) do
      if e.Tab and not seen[e.Tab] then seen[e.Tab] = true; tabs[#tabs + 1] = e.Tab end
    end
  end
  for _, tab in ipairs(tabs) do
    local ok2, res = pcall(api.GetEntriesByClass, cn, tab, false)
    if ok2 and type(res) == "table" then
      local combo, ord = {}, {}
      for _, e in ipairs(res) do
        local k = tostring(e.Type) .. "|" .. tostring(e.NodeType)
          .. "|" .. tostring(e.Quality) .. "|" .. tostring(e.Color)
        if combo[k] == nil then combo[k] = 0; ord[#ord + 1] = k end
        combo[k] = combo[k] + 1
      end
      CIT.Log(tab .. ":")
      for _, k in ipairs(ord) do CIT.Log("   " .. k .. " = " .. combo[k]) end
    end
  end
end

-- Dumpea info de specs/categorías para distinguir la spec activa de los árboles
-- hero (que comparten formato de entry pero son tabs aparte).
function CIT.Debug.dumpSpecs()
  local api = _G.C_CharacterAdvancement
  local u = "target"
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("debug: no class."); return end
  local active, unlocked = CIT.CAReader.inspectInfo(u)
  local unlockedStr = type(unlocked) == "table" and ("{" .. table.concat(unlocked, ",") .. "}") or tostring(unlocked)
  CIT.Log("active=" .. tostring(active) .. " unlocked=" .. unlockedStr)

  -- GetCategories: puede separar specs de hero.
  if type(api.GetCategories) == "function" then
    local ok, cats = pcall(api.GetCategories, cn)
    if ok and type(cats) == "table" then
      for i, c in ipairs(cats) do
        if type(c) == "table" then
          local parts = {}
          for k, v in pairs(c) do parts[#parts + 1] = k .. "=" .. tostring(v) end
          CIT.Log("  cat[" .. i .. "] " .. table.concat(parts, " "))
        else
          CIT.Log("  cat[" .. i .. "] " .. tostring(c))
        end
      end
    else
      CIT.Log("  GetCategories -> " .. tostring(cats))
    end
  end

  -- Por tab: total y aprendidos (para ver cuáles tienen puntos).
  local slot = active or 1
  local tree = CIT.CAReader.classTree(cn, slot)
  local build = CIT.CAReader.unitBuild(u, slot)
  local total, learned, ord = {}, {}, {}
  for _, n in ipairs(tree) do
    if total[n.Tab] == nil then total[n.Tab] = 0; ord[#ord + 1] = n.Tab end
    total[n.Tab] = total[n.Tab] + 1
    if build[n.ID] then learned[n.Tab] = (learned[n.Tab] or 0) + 1 end
  end
  for _, tb in ipairs(ord) do
    CIT.Log("  TAB " .. tb .. " total=" .. total[tb] .. " learned=" .. (learned[tb] or 0))
  end
end

-- Diagnostica los nodos de ELECCIÓN (2+ opciones) del target inspeccionado:
-- los agrupa por campo Group (no-cero) y por posición (tab:x:y) y, para cada
-- miembro, reporta si nuestro método actual (EntryId de GetInspectedBuild) lo
-- marca como conocido vs. lo que dice UnitKnownID(unit, ID, spec). Revela por
-- qué los nodos de elección hero no se iluminan (overlap de posición o
-- desajuste de namespace de ID).
function CIT.Debug.dumpChoice()
  local u = "target"
  local api = _G.C_CharacterAdvancement
  local cn = CIT.CAReader.className(u)
  if not cn then CIT.Log("choice: no CoA class on target (inspecciona un player)."); return end
  local active = CIT.CAReader.inspectInfo(u) or 1
  local tree = CIT.CAReader.classTree(cn, active)
  if #tree == 0 then CIT.Log("choice: árbol vacío (data no cargada aún?)."); return end
  local build = CIT.CAReader.unitBuild(u, active)

  local function known1(id) return build[id] ~= nil end
  local function knownAPI(id)
    if type(api.UnitKnownID) ~= "function" then return "n/a" end
    local ok, k = pcall(api.UnitKnownID, u, id, active)
    if not ok then return "err" end
    return k and "Y" or "n"
  end

  -- Agrupar por Group (no-cero) y por posición tab:x:y.
  local byGroup, byPos = {}, {}
  for _, n in ipairs(tree) do
    local g = n.Group
    if g and g ~= 0 then
      byGroup[g] = byGroup[g] or {}
      byGroup[g][#byGroup[g] + 1] = n
    end
    local pk = tostring(n.Tab) .. ":" .. tostring(n.PositionX) .. ":" .. tostring(n.PositionY)
    byPos[pk] = byPos[pk] or {}
    byPos[pk][#byPos[pk] + 1] = n
  end

  local function report(label, buckets, keyIsPos)
    local shown = 0
    for key, list in pairs(buckets) do
      if #list > 1 then
        shown = shown + 1
        CIT.Log(label .. " " .. tostring(key) .. " (" .. #list .. " opciones):")
        for _, n in ipairs(list) do
          CIT.Log("   ID=" .. tostring(n.ID) .. " '" .. tostring(n.Name) .. "'"
            .. " pos=" .. tostring(n.PositionX) .. "," .. tostring(n.PositionY)
            .. " grp=" .. tostring(n.Group)
            .. " inBuild=" .. (known1(n.ID) and "Y" or "n")
            .. " UnitKnownID=" .. knownAPI(n.ID))
        end
      end
    end
    if shown == 0 then CIT.Log(label .. ": ninguno con 2+ miembros.") end
  end

  CIT.Log("=== CHOICE dump: " .. tostring(cn) .. " spec=" .. tostring(active)
    .. " nodos=" .. #tree .. " enBuild=" .. (function() local c=0 for _ in pairs(build) do c=c+1 end return c end)() .. " ===")
  report("GROUP", byGroup, false)
  report("POS", byPos, true)
end

-- /coait          -> resumen por tab
-- /coait class    -> nodos del tab Class con posiciones
-- /coait api      -> funciones de la API CoA
-- /coait miss     -> aprendidos que no están en el árbol
-- /coait choice   -> nodos de elección (2+ opciones): overlap y estado conocido
_G.SLASH_COAIT1 = "/coait"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList["COAIT"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "class" then
    CIT.safe(CIT.Debug.dumpClass)
  elseif msg == "api" then
    CIT.safe(CIT.Debug.dumpAPI)
  elseif msg == "miss" then
    CIT.safe(CIT.Debug.dumpMissing)
  elseif msg == "entries" then
    CIT.safe(CIT.Debug.dumpEntries)
  elseif msg == "findmiss" then
    CIT.safe(CIT.Debug.findMissing)
  elseif msg == "cats" then
    CIT.safe(CIT.Debug.dumpCats)
  elseif msg == "specs" then
    CIT.safe(CIT.Debug.dumpSpecs)
  elseif msg == "choice" then
    CIT.safe(CIT.Debug.dumpChoice)
  else
    CIT.safe(CIT.Debug.dumpTarget)
  end
end
