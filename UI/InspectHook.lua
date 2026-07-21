-- El cambio de spec se maneja con el selector PROPIO del panel (TreePanel.SetSpecs),
-- que re-consulta el árbol de la spec elegida. No dependemos de los botones nativos.
local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end
CIT.InspectHook = {}

-- Estado del inspect en curso.
local current = { unit = nil, className = nil, tree = nil, slot = nil }

-- Devuelve el frame de inspect visible, o nil. En Ascension (realms CoA) la UI
-- moddeada oculta los frames stock y usa AscensionInspectFrame; en clientes
-- stock/Epoch es InspectFrame. Comprobamos ambos para cubrir los dos casos.
local function getInspectFrame()
  local names = {
    "AscensionInspectFrame", "AscensionInspectPaperDollFrame",
    "InspectFrame", "InspectPaperDollFrame",
  }
  for _, n in ipairs(names) do
    local f = _G[n]
    if f and f.IsVisible and f:IsVisible() then return f end
  end
  return nil
end

-- Carga el árbol de la clase del unit y renderiza para la spec `slot`.
local function renderFor(unit, slot)
  if not CIT.enabled then return end
  CIT.TreePanel.Get().userHidden = false
  -- El panel solo tiene sentido junto a un inspect abierto. En CoA el evento
  -- INSPECT_CHARACTER_ADVANCEMENT_RESULT llega cada vez que alguien inspecciona
  -- al target (otros addons lo hacen en automático durante combate), así que sin
  -- esta guarda el panel se abría solo. Ver getInspectFrame().
  if not getInspectFrame() then CIT.TreePanel.Hide(); return end
  local className = CIT.CAReader.className(unit)
  if not className then return end
  current.unit = unit
  current.className = className
  current.slot = slot
  current.tree = CIT.CAReader.classTree(className, slot)
  if #current.tree == 0 then
    current.retries = (current.retries or 0) + 1
    CIT.TreePanel.Get().title:SetText("Loading talents...")
    CIT.TreePanel.Show()
    if current.retries <= 5 then
      local u, s = unit, slot
      -- C_Timer no existe en 3.3.5; usar un frame OnUpdate de un disparo.
      local t = CreateFrame("Frame")
      local waited = 0
      t:SetScript("OnUpdate", function(self, e)
        waited = waited + e
        if waited >= 0.5 then
          self:SetScript("OnUpdate", nil)
          renderFor(u, s)
        end
      end)
    else
      CIT.TreePanel.Get().title:SetText("No talent data")
    end
    return
  end
  current.retries = 0
  -- Rank desde GetInspectedBuild (en inspect, UnitTalentRankByID da rank nil).
  local buildMap = CIT.CAReader.unitBuild(unit, slot)
  local model = CIT.TreeModel.build(current.tree, buildMap)
  local inspectFrame = getInspectFrame()
  if inspectFrame then CIT.TreePanel.AttachTo(inspectFrame) end
  CIT.TreePanel.Get().title:SetText((UnitName(unit) or "") .. " — Spec " .. tostring(slot))

  -- Selector de spec propio: al hacer clic, re-consulta el árbol de esa spec.
  local _, unlocked = CIT.CAReader.inspectInfo(unit)
  local specs = {}
  if type(unlocked) == "table" then
    for _, s in ipairs(unlocked) do specs[#specs + 1] = s end
  elseif type(unlocked) == "number" then
    for s = 1, unlocked do specs[#specs + 1] = s end
  end
  if #specs == 0 then specs = { slot } end
  -- Usar current.unit en los closures para no capturar un target obsoleto.
  CIT.TreePanel.SetSpecs(specs, slot, function(s) renderFor(current.unit, s) end)

  -- Botón Comparar: alterna mostrar tu propio árbol junto al del inspeccionado.
  CIT.TreePanel.SetCompare(current.compare, function()
    current.compare = not current.compare
    renderFor(current.unit, current.slot)
  end)

  -- Si Comparar está activo, construir tu propio modelo (tu clase + tu spec).
  local myModel, mySlot = nil, nil
  if current.compare then
    local myClass = CIT.CAReader.className("player")
    mySlot = (CIT.CAReader.inspectInfo("player")) or 1
    if myClass then
      local myTree = CIT.CAReader.classTree(myClass, mySlot)
      if #myTree > 0 then
        local myBuild = CIT.CAReader.playerBuild(mySlot, myTree)
        myModel = CIT.TreeModel.build(myTree, myBuild)
      end
    end
  end

  CIT.TreePanel.Render(model, slot, myModel, mySlot)
  CIT.TreePanel.Show()
end
CIT.InspectHook.RenderFor = renderFor

-- Al llegar la data CoA del inspeccionado, renderizar su spec activa. Usamos
-- siempre "target" (el inspeccionado en CoA es tu objetivo); inspectFrame.unit
-- puede quedar obsoleto y mostrar al jugador anterior.
CIT.RegisterEvent("INSPECT_CHARACTER_ADVANCEMENT_RESULT", function()
  local active = CIT.CAReader.inspectInfo("target") or 1
  renderFor("target", active)
end)

-- Al cambiar de objetivo: descartar el árbol del inspeccionado anterior y, si
-- hay inspect abierto sobre un jugador, pedir/renderizar los datos del nuevo.
CIT.RegisterEvent("PLAYER_TARGET_CHANGED", function()
  if not CIT.enabled then return end
  current.unit = nil; current.className = nil; current.tree = nil
  current.slot = nil; current.retries = 0
  local f = getInspectFrame()
  if not f then CIT.TreePanel.Hide(); return end
  if UnitExists("target") and UnitIsPlayer("target") then
    local api = _G.C_CharacterAdvancement
    if api and type(api.InspectUnit) == "function" then
      CIT.safe(api.InspectUnit, "target")
    end
    local active = CIT.CAReader.inspectInfo("target") or 1
    renderFor("target", active)
  else
    CIT.TreePanel.Hide()
  end
end)

-- Muestra el panel solo cuando la pestaña Build del inspect está activa.
-- RECONOCIMIENTO PENDIENTE: rellenar `isBuildTabActive` con la comprobación
-- real del selectedTab del frame nativo (ver Task 9 Step 1). Mientras no se
-- determine, se asume visible cuando hay un inspect en curso.
local buildTabWatcher = CreateFrame("Frame")
local accum = 0
buildTabWatcher:SetScript("OnUpdate", function(_, elapsed)
  if not CIT.enabled then return end
  accum = accum + elapsed
  if accum < 0.2 then return end
  accum = 0
  local f = getInspectFrame()
  if not f then CIT.TreePanel.Hide(); return end
  local function isBuildTabActive()
    -- Placeholder de detección: si no se pudo determinar la pestaña, asumir
    -- visible. Reemplazar por la comprobación real del selectedTab del frame.
    return true
  end
  if current.unit and isBuildTabActive() then
    CIT.TreePanel.Show()
  else
    CIT.TreePanel.Hide()
  end
end)
