local CIT = _G.CoAInspectTree
if not CIT then CIT = {}; _G.CoAInspectTree = CIT end

function CIT.Log(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff8080ff[CoAInspectTree]|r " .. tostring(msg))
  end
end

-- Envuelve fn en pcall. Devuelve (ok, resultado). Loguea el error si falla.
function CIT.safe(fn, ...)
  local ok, res = pcall(fn, ...)
  if not ok then CIT.Log("error: " .. tostring(res)) end
  return ok, res
end
