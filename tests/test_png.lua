-- The built-in PNG reader against known pixels (tests/fixtures/png) and
-- against Aseprite's own loader for any other PNGs passed in `files`.
--   aseprite -b --script-param src=<src dir> --script-param dir=<tests/fixtures/png>
--     [--script-param files="a.png;b.png"] --script tests/test_png.lua
package.path = app.params.src .. "/?.lua;" .. package.path
local png = require("mca_png")
local render = require("mca_render")
local failures = 0

local function read(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("a")
  f:close()
  return data
end

local function report(name, diffs, note)
  print(string.format("%-4s %-28s %s", diffs == 0 and "ok" or "FAIL", name, note or (diffs .. " differing pixels")))
  if diffs ~= 0 then failures = failures + 1 end
end

local dir = app.params.dir
local names = app.fs.listFiles(dir)
table.sort(names)
for _, name in ipairs(names) do
  if name:match("%.png$") then
    local w, h, px = png.decode(read(app.fs.joinPath(dir, name)))
    if not w then
      report(name, 1, "error: " .. tostring(h))
    else
      local want = read(app.fs.joinPath(dir, (name:gsub("%.png$", ".rgba"))))
      local diffs = 0
      for i = 0, w * h - 1 do
        local r, g, b, a = want:byte(i * 4 + 1, i * 4 + 4)
        if px[i] ~= (r | (g << 8) | (b << 16) | (a << 24)) then diffs = diffs + 1 end
      end
      report(name, diffs)
    end
  end
end

-- Real files: compare with Aseprite's loader.
for path in (app.params.files or ""):gmatch("[^;]+") do
  local w, h, px = png.decode(read(path))
  local spr = Sprite{ fromFile=path }
  local img = Image(spr.width, spr.height, ColorMode.RGB)
  img:drawSprite(spr, 1)
  local ref = render.textureFromImage(img)
  spr:close()
  local diffs = 0
  for i = 0, ref.w * ref.h - 1 do
    local p, q = px[i] or 0, ref.px[i] or 0
    if ((p >> 24) ~= 0 or (q >> 24) ~= 0) and p ~= q then diffs = diffs + 1 end
  end
  report(app.fs.fileName(app.fs.filePath(path)) .. "/" .. app.fs.fileName(path), diffs)
end

-- Garbage input fails cleanly.
local w, err = png.decode("not a png")
report("rejects non-PNG data", w == nil and 0 or 1, w == nil and ("error: " .. err) or "accepted garbage")

print(failures == 0 and "PASS" or ("FAIL: " .. failures))
