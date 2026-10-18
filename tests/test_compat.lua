-- Cross-platform path handling and the fallbacks for older Aseprite 1.3.x.
--   aseprite -b --script-param src=<src dir> --script tests/test_compat.lua
package.path = app.params.src .. "/?.lua;" .. package.path
local compat = require("mca_compat")
local layout = require("mca_layout")
local ok = true
local function eq(a, b, msg)
  local pass = a == b
  print((pass and "ok   " or "FAIL ") .. msg .. (pass and "" or ("  got " .. tostring(a) .. ", want " .. tostring(b))))
  ok = ok and pass
end

local sep = app.fs.pathSeparator
local function p(...) return table.concat({ ... }, sep) end

-- Path keys
eq(compat.pathKey(p("", "pack", "x", "..", "humanoid", "iron.png")), p("", "pack", "humanoid", "iron.png"),
   "pathKey resolves '..'")
eq(compat.samePath(p("", "a", ".", "b.png"), p("", "a", "b.png")), true, "samePath ignores '.'")
eq(compat.samePath(nil, p("", "a.png")), false, "samePath with nil is false")
if sep == "\\" then
  eq(compat.samePath("C:\\Pack\\Iron.png", "c:/pack/iron.png"), true, "Windows: case and separators ignored")
else
  eq(compat.samePath("/pack/Iron.png", "/pack/iron.png"), false, "macOS/Linux: case is kept")
end

-- Folder/name matching ignores case; the partner keeps the original case.
eq(layout.classify(p("", "pack", "HUMANOID", "iron.png")), layout.LAYER1, "classify ignores folder case")
eq(layout.classify(p("", "pack", "Iron_Layer_2.png")), layout.LAYER2, "classify ignores name case")
eq(layout.partnerPath(p("", "pack", "Iron_Layer_1.png")), p("", "pack", "Iron_Layer_2.png"),
   "partnerPath keeps the file's own case")

-- Fallbacks
local spr = Sprite(64, 32)
eq(compat.isOpen(spr), true, "isOpen: open sprite")
local closed = Sprite(64, 32)
closed:close()
eq(compat.isOpen(closed), false, "isOpen: closed sprite")
eq(compat.isOpen(nil), false, "isOpen: nil")
-- An object without isValid (like a Sprite on Aseprite < 1.3.16) uses the
-- fallback instead of raising an error.
local oldStyle = setmetatable({}, { __index=function(_, k) error("Field " .. k .. " does not exist") end })
eq(compat.isOpen(oldStyle), false, "isOpen: object without isValid")
eq(pcall(compat.tip, "test"), true, "tip never raises")
eq(pcall(compat.on, spr.events, "no_such_event", function() end), true, "on() with an unknown event never raises")
eq(compat.on(spr.events, "change", function() end) ~= nil, true, "on() returns a listener code")
eq(compat.MIN_API_VERSION <= app.apiVersion, true, "this Aseprite meets the minimum version")

print(ok and "PASS" or "FAILED")
