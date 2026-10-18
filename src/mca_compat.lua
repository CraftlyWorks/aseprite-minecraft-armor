-- Small shims so the extension runs on every Aseprite 1.3.x release and on
-- Windows, macOS and Linux alike.

local C = {}

-- Aseprite 1.3.0 is API version 26.
C.MIN_API_VERSION = 26
C.MIN_VERSION_LABEL = "1.3"

local WINDOWS = app.fs.pathSeparator == "\\"

-- Key for comparing file paths: separators and "."/".." normalized, and
-- lower case on Windows, whose file system ignores case.
function C.pathKey(path)
  if not path or path == "" then return path end
  local key = app.fs.normalizePath(path)
  if WINDOWS then key = key:lower() end
  return key
end

function C.samePath(a, b)
  return a ~= nil and b ~= nil and C.pathKey(a) == C.pathKey(b)
end

-- Reads a field that older Aseprite versions don't have (accessing an
-- unknown field raises an error instead of returning nil).
local function tryField(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
  return nil
end

-- Whether a sprite is still open. Sprite.isValid exists from 1.3.16.
function C.isOpen(sprite)
  if not sprite then return false end
  local valid = tryField(sprite, "isValid")
  if valid ~= nil then return valid end
  for _, s in ipairs(app.sprites) do
    local ok, same = pcall(function() return s == sprite end)
    if ok and same then return true end
  end
  return false
end

-- Status-bar tip; app.tip exists from 1.3.15.
function C.tip(text)
  local tip = tryField(app, "tip")
  if tip then tip(text) end
end

-- Listens to an event if this Aseprite version has it (e.g. the sprite
-- 'layervisibility' event exists from 1.3.15). Returns the listener code.
function C.on(events, name, fn)
  local ok, code = pcall(function() return events:on(name, fn) end)
  if ok then return code end
  return nil
end

return C
