-- Renders an armor set from several angles into one contact sheet PNG,
-- checks every view drew something, and prints the average render time.
--   aseprite -b --script-param src=<src dir> --script-param l1=<layer 1 png>
--     --script-param l2=<layer 2 png> --script-param out=<png> --script tests/test_render.lua
package.path = app.params.src .. "/?.lua;" .. package.path
local render = require("mca_render")

local textures = {
  humanoid = render.textureFromFile(app.params.l1),
  humanoid_leggings = app.params.l2 and render.textureFromFile(app.params.l2) or nil,
}
local views = {
  { yaw=0,    pitch=0 },
  { yaw=-30,  pitch=15 },
  { yaw=90,   pitch=0 },
  { yaw=180,  pitch=10 },
  { yaw=35,   pitch=-35 },
  { yaw=-20,  pitch=60 },
}
local W, H = 220, 300
local sheet = Image(W * #views, H, ColorMode.RGB)
sheet:clear(app.pixelColor.rgba(52, 52, 58, 255))
local total, empty = 0, 0
for i, v in ipairs(views) do
  local t0 = os.clock()
  local img = render.render{ width=W, height=H, textures=textures, yaw=v.yaw, pitch=v.pitch }
  total = total + (os.clock() - t0)
  local drawn = 0
  for it in img:pixels() do if (it() >> 24) > 0 then drawn = drawn + 1 end end
  if drawn < 1000 then empty = empty + 1 end
  sheet:drawImage(img, Point((i - 1) * W, 0))
end
sheet:saveAs(app.params.out)
print(string.format("avg render %.1f ms at %dx%d", total * 1000 / #views, W, H))
print(empty == 0 and "PASS" or ("FAIL: " .. empty .. " empty view(s)"))
