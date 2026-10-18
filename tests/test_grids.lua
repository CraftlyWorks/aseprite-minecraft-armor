-- Grid slices: counts, toggling, HD scaling, and a PNG round trip (pixels
-- untouched, slices not stored in the file).
--   aseprite -b --script-param src=<src dir> --script-param file=<copy>/humanoid/test_armor.png
--     --script tests/test_grids.lua
package.path = app.params.src .. "/?.lua;" .. package.path
local layout = require("mca_layout")
local grids = require("mca_grids")
local ok = true
local function check(cond, msg) print((cond and "ok   " or "FAIL ") .. msg); ok = ok and cond end

local file = app.params.file
local before = Image{ fromFile=file }
local spr = app.open(file)
local layer = layout.classify(file)
check(layer == layout.LAYER1, "classified as Layer 1")
grids.apply(spr, layer, nil)
check(#spr.slices == 30, "30 grid slices on Layer 1 (got " .. #spr.slices .. ")")
check(grids.hasGrids(spr), "hasGrids")
check(spr.gridBounds.width == 4, "4x4 grid")
grids.apply(spr, layer, { boots=false })
check(#spr.slices == 24, "boots toggled off -> 24 slices (got " .. #spr.slices .. ")")
grids.apply(spr, layer, nil)
check(#spr.slices == 30, "re-apply does not duplicate (got " .. #spr.slices .. ")")

-- Save back to PNG and verify the texture is untouched.
spr:saveAs(file)
spr:close()
local after = Image{ fromFile=file }
local same = after.width == before.width and after.height == before.height
for it in before:pixels() do
  if after:getPixel(it.x, it.y) ~= it() then same = false; break end
end
check(same, "saved PNG pixels identical to the original")
local reopened = app.open(file)
check(#reopened.slices == 0, "slices are not stored in the PNG")
reopened:close()

-- Layer 2
local spr2 = Sprite(64, 32)
grids.apply(spr2, layout.LAYER2, nil)
check(#spr2.slices == 12, "12 grid slices on Layer 2 (got " .. #spr2.slices .. ")")
grids.remove(spr2)
check(#spr2.slices == 0, "remove clears grid slices")

-- HD texture
local hd = Sprite(128, 64)
grids.apply(hd, layout.LAYER1, nil)
local headFront
for _, s in ipairs(hd.slices) do if s.name == "Helmet - Front" then headFront = s.bounds end end
check(headFront and headFront.x == 16 and headFront.y == 16 and headFront.width == 16, "HD 128x64 grids scale 2x")

print(ok and "PASS" or "FAILED")
