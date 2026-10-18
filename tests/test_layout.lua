-- File classification and partner pairing.
package.path = app.params.src .. "/?.lua;" .. package.path
local layout = require("mca_layout")
local ok = true
local function eq(a, b, msg)
  local pass = a == b
  print((pass and "ok   " or "FAIL ") .. msg .. (pass and "" or ("  got " .. tostring(a) .. ", want " .. tostring(b))))
  ok = ok and pass
end
-- Paths use the platform's separator so the test also runs on Windows.
local sep = app.fs.pathSeparator
local function p(...) return table.concat({ ... }, sep) end
local base = p("", "pack", "assets", "minecraft", "textures", "entity", "equipment")
local old = p("", "old", "textures", "models", "armor")
eq(layout.classify(p(base, "humanoid", "iron.png")), layout.LAYER1, "humanoid folder -> Layer 1")
eq(layout.classify(p(base, "humanoid_leggings", "iron.png")), layout.LAYER2, "humanoid_leggings folder -> Layer 2")
eq(layout.classify(p(old, "iron_layer_1.png")), layout.LAYER1, "_layer_1 -> Layer 1")
eq(layout.classify(p(old, "iron_layer_2.png")), layout.LAYER2, "_layer_2 -> Layer 2")
eq(layout.classify(p("", "somewhere", "robot.png")), nil, "unknown name -> nil")
eq(layout.partnerPath(p(base, "humanoid", "iron.png")), p(base, "humanoid_leggings", "iron.png"), "humanoid -> leggings partner")
eq(layout.partnerPath(p(base, "humanoid_leggings", "iron.png")), p(base, "humanoid", "iron.png"), "leggings -> humanoid partner")
eq(layout.partnerPath(p("", "a", "iron_layer_1.png")), p("", "a", "iron_layer_2.png"), "_layer_1 -> _layer_2")
eq(layout.partnerPath(p("", "a", "iron_layer_2.png")), p("", "a", "iron_layer_1.png"), "_layer_2 -> _layer_1")
eq(layout.partnerPath(p("", "a", "robot.png")), nil, "no partner for unknown name")
eq(layout.isArmorSize(64, 32), true, "64x32 is armor size")
eq(layout.isArmorSize(128, 64), true, "128x64 is armor size")
eq(layout.isArmorSize(64, 64), false, "64x64 (skin) is not")
eq(layout.isArmorSize(32, 16), false, "32x16 is not")
-- Every face edge lands on a multiple of 4 (what the 4x4 grid relies on).
local aligned = true
for part in pairs(layout.PARTS) do
  for _, r in pairs(layout.faceRects(part)) do
    for _, v in ipairs(r) do if v % 4 ~= 0 then aligned = false end end
  end
end
eq(aligned, true, "all face rects are 4-aligned")
print(ok and "PASS" or "FAILED")
