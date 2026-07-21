local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end

CIT.enabled = false

-- Frame despachador de eventos. Los módulos registran callbacks en CIT.on[EVENT].
CIT.on = CIT.on or {}
local dispatcher = CreateFrame("Frame")
dispatcher:RegisterEvent("PLAYER_LOGIN")
dispatcher:SetScript("OnEvent", function(_, event, ...)
  local handlers = CIT.on[event]
  if handlers then
    for i = 1, #handlers do CIT.safe(handlers[i], ...) end
  end
end)
CIT.dispatcher = dispatcher

-- Registra un handler para un evento y asegura que el frame lo escuche.
function CIT.RegisterEvent(event, handler)
  CIT.on[event] = CIT.on[event] or {}
  table.insert(CIT.on[event], handler)
  dispatcher:RegisterEvent(event)
end

-- Al login: preparar SavedVariables y detectar si el realm soporta CoA.
CIT.RegisterEvent("PLAYER_LOGIN", function()
  CoAInspectTreeDB = CoAInspectTreeDB or {}
  if type(CoAInspectTreeDB.scale) ~= "number" then CoAInspectTreeDB.scale = 0.75 end
  CIT.enabled = (_G.C_CharacterAdvancement ~= nil)
  if CIT.enabled then
    CIT.Log("active (Character Advancement detected).")
  end
end)

-- Lightweight controls for recovery and display tuning.
_G.SlashCmdList = _G.SlashCmdList or {}
SLASH_COAINSPECTTREE1 = "/cit"
SLASH_COAINSPECTTREE2 = "/coainspecttree"
SlashCmdList["COAINSPECTTREE"] = function(msg)
  msg = string.lower(tostring(msg or ""))
  if msg == "reset" then
    CoAInspectTreeDB = CoAInspectTreeDB or {}
    CoAInspectTreeDB.scale = 0.75
    if CIT.TreePanel and CIT.TreePanel.Get then CIT.TreePanel.Get().setScale(0.75) end
    CIT.Log("display scale reset to 75%.")
  elseif msg == "show" then
    if CIT.TreePanel and CIT.TreePanel.Get then
      CIT.TreePanel.Get().userHidden = false
      CIT.TreePanel.Show()
    end
  elseif msg == "hide" then
    if CIT.TreePanel and CIT.TreePanel.Get then
      CIT.TreePanel.Get().userHidden = true
      CIT.TreePanel.Hide()
    end
  else
    CIT.Log("commands: /cit show, /cit hide, /cit reset")
  end
end
