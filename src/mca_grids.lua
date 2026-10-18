-- Body-part grids: one coloured slice per face of every armor part. Slices
-- are drawn by Aseprite as outlines on the canvas and are not written into
-- PNG files, so the texture itself is never touched.

local compat = require("mca_compat")
local layout = require("mca_layout")

local G = {}

-- Must match "publisher/name" in package.json.
G.PROPERTY_KEY = "craftlyworks/minecraft-armor-tools"

local SLICE_ALPHA = 210

local function isGridSlice(slice)
  local ok, props = pcall(function() return slice.properties(G.PROPERTY_KEY) end)
  return ok and props and props.grid == true
end

function G.hasGrids(sprite)
  for _, slice in ipairs(sprite.slices) do
    if isGridSlice(slice) then return true end
  end
  return false
end

local function removeGridSlices(sprite)
  local old = {}
  for _, slice in ipairs(sprite.slices) do
    if isGridSlice(slice) then old[#old + 1] = slice end
  end
  for _, slice in ipairs(old) do
    sprite:deleteSlice(slice)
  end
end

-- Runs fn with sprite as the active sprite so its changes land in that
-- sprite's undo history.
local function withActiveSprite(sprite, label, fn)
  local previous = app.sprite
  if previous ~= sprite then app.sprite = sprite end
  app.transaction(label, fn)
  if previous and previous ~= sprite and compat.isOpen(previous) then app.sprite = previous end
end

-- (Re)creates the grid slices for the pieces enabled in `pieces`
-- (e.g. { helmet=true, chestplate=false }; missing = enabled).
function G.apply(sprite, layer, pieces)
  local scale = sprite.width // layout.BASE_W
  withActiveSprite(sprite, "Armor Grids", function()
    removeGridSlices(sprite)
    for _, region in ipairs(layout.GRIDS[layer] or {}) do
      if not pieces or pieces[region.piece] ~= false then
        local rects = layout.faceRects(region.part)
        local c = region.color
        for _, face in ipairs(layout.FACE_ORDER) do
          local r = rects[face]
          local slice = sprite:newSlice(Rectangle(r[1] * scale, r[2] * scale, r[3] * scale, r[4] * scale))
          slice.name = region.label .. " - " .. layout.FACE_NAMES[face]
          slice.color = Color{ r=c[1], g=c[2], b=c[3], a=SLICE_ALPHA }
          slice.properties(G.PROPERTY_KEY).grid = true
        end
      end
    end
  end)
  -- Every face edge of the armor layout lands on a multiple of 4 texels,
  -- so a 4x4 grid (View > Show > Grid) lines up with all of them.
  sprite.gridBounds = Rectangle(0, 0, 4 * scale, 4 * scale)
end

function G.remove(sprite)
  if not G.hasGrids(sprite) then return end
  withActiveSprite(sprite, "Remove Armor Grids", function()
    removeGridSlices(sprite)
  end)
end

return G
