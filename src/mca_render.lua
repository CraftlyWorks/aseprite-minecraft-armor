-- Software renderer for the armor model: an orthographic, z-buffered
-- rasterizer that maps texture pixels onto the model boxes and returns an
-- Image ready to be drawn on a dialog canvas.

local layout = require("mca_layout")

local R = {}

local floor, ceil, abs = math.floor, math.ceil, math.abs
local min, max, sin, cos, rad = math.min, math.max, math.sin, math.cos, math.rad
local spack, sunpack = string.pack, string.unpack

-- Minecraft armor is drawn with an alpha cutout; fainter pixels are skipped
-- and the rest are drawn fully opaque.
local ALPHA_CUTOFF = 26 << 24

-- Fixed per-direction lighting, like the game's flat entity shading.
local FACE_SHADE = { top=1.0, bottom=0.55, front=0.86, back=0.86, right=0.7, left=0.7 }
-- Extra darkening for the inside of a box (seen through transparent pixels).
local INSIDE_SHADE = 0.6

-- Vertical centre of the model, used as the rotation pivot.
local MODEL_CENTER_Y = 16

---------------------------------------------------------------------------
-- Textures: { w, h, scale, px = { [y*w + x] = rgba } }

-- palette is needed for indexed images (e.g. vanilla iron.png).
function R.textureFromImage(img, palette)
  local w, h = img.width, img.height
  local px = {}
  if img.colorMode == ColorMode.RGB then
    local bytes, stride = img.bytes, img.rowStride
    for y = 0, h - 1 do
      local row, base = y * stride + 1, y * w
      for x = 0, w - 1 do
        px[base + x] = sunpack("<I4", bytes, row + x * 4)
      end
    end
  else
    local pc = app.pixelColor
    local indexed = img.colorMode == ColorMode.INDEXED
    local lut = {}
    for it in img:pixels() do
      local v = it()
      local c = lut[v]
      if not c then
        if indexed then
          c = (palette and v < #palette) and palette:getColor(v).rgbaPixel or 0
        else
          local g = pc.grayaV(v)
          c = pc.rgba(g, g, g, pc.grayaA(v))
        end
        lut[v] = c
      end
      px[it.y * w + it.x] = c
    end
  end
  return { w=w, h=h, scale=w / layout.BASE_W, px=px }
end

-- RGB copy of an indexed or grayscale cel image. `transparent` is the
-- palette index drawn as transparent (none for background layers).
local function celImageToRGB(img, palette, transparent)
  local pc = app.pixelColor
  local indexed = img.colorMode == ColorMode.INDEXED
  local lut, out, n = {}, {}, 0
  for it in img:pixels() do
    local v = it()
    local packed = lut[v]
    if not packed then
      local c
      if indexed then
        c = (v ~= transparent and v < #palette) and palette:getColor(v).rgbaPixel or 0
      else
        local g = pc.grayaV(v)
        c = pc.rgba(g, g, g, pc.grayaA(v))
      end
      packed = spack("<I4", c)
      lut[v] = packed
    end
    n = n + 1
    out[n] = packed
  end
  local rgb = Image(img.width, img.height, ColorMode.RGB)
  rgb.bytes = table.concat(out)
  return rgb
end

-- Flattened frame of an open sprite, composed straight from its cels.
-- Image:drawSprite() is avoided on purpose: in Aseprite 1.3.17/1.3.18,
-- calling it while a brush stroke is being committed moves the stroked
-- cel to 0,0 (ScopedToolLoopFix restores a stale position), which shifted
-- leggings textures up by 16 pixels.
function R.textureFromSprite(sprite, frame)
  frame = frame or 1
  local out = Image(sprite.width, sprite.height, ColorMode.RGB)
  local palette = sprite.palettes[1]
  local transparent = sprite.transparentColor

  local function drawLayers(layers, parentOpacity)
    for _, layer in ipairs(layers) do
      if layer.isVisible and not layer.isReference then
        local opacity = parentOpacity * (layer.opacity or 255) // 255
        if layer.isGroup then
          drawLayers(layer.layers, opacity)
        elseif layer.isImage and not layer.isTilemap then
          local cel = layer:cel(frame)
          if cel then
            local img = cel.image
            if img.colorMode ~= ColorMode.RGB then
              img = celImageToRGB(img, palette, layer.isBackground and -1 or transparent)
            end
            out:drawImage(img, cel.position, opacity * cel.opacity // 255, layer.blendMode)
          end
        end
      end
    end
  end
  drawLayers(sprite.layers, 255)
  return R.textureFromImage(out)
end

-- Reads a texture straight from disk without opening a tab.
function R.textureFromFile(path)
  local ok, img = pcall(Image, { fromFile=path })
  if not ok or not img then return nil end
  local palette
  if img.colorMode == ColorMode.INDEXED then
    local okPal, pal = pcall(Palette, { fromFile=path })
    if okPal then palette = pal end
  end
  return R.textureFromImage(img, palette)
end

---------------------------------------------------------------------------
-- Geometry

-- The six faces of an inflated box as parallelograms in model space:
-- o = corner at texture pixel (0,0), du/dv = edges along texture x/y.
local function boxFaces(bone, grow)
  local part = layout.PARTS[bone.part]
  local w, h, d = part.size[1], part.size[2], part.size[3]
  local x0, y0, z0 = bone.from[1] - grow, bone.from[2] - grow, bone.from[3] - grow
  local x1, y1, z1 = bone.from[1] + w + grow, bone.from[2] + h + grow, bone.from[3] + d + grow
  local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
  local rects = layout.faceRects(bone.part)
  local faces = {
    { id="front",  o={x0, y1, z1}, du={ dx, 0, 0}, dv={0, -dy, 0}, n={ 0, 0,  1} },
    { id="back",   o={x1, y1, z0}, du={-dx, 0, 0}, dv={0, -dy, 0}, n={ 0, 0, -1} },
    { id="right",  o={x0, y1, z0}, du={0, 0,  dz}, dv={0, -dy, 0}, n={-1, 0,  0} },
    { id="left",   o={x1, y1, z1}, du={0, 0, -dz}, dv={0, -dy, 0}, n={ 1, 0,  0} },
    { id="top",    o={x0, y1, z0}, du={ dx, 0, 0}, dv={0, 0,  dz}, n={ 0, 1,  0} },
    { id="bottom", o={x0, y0, z0}, du={ dx, 0, 0}, dv={0, 0,  dz}, n={ 0, -1, 0} },
  }
  for _, f in ipairs(faces) do
    f.rect = rects[f.id]
    f.shade = FACE_SHADE[f.id]
    if bone.mirror then
      -- Mirror across the box's own centre: the "right side" pixels land on
      -- the outer (left) side and every face is flipped horizontally.
      f.o[1] = x0 + x1 - f.o[1]
      f.du[1], f.dv[1], f.n[1] = -f.du[1], -f.dv[1], -f.n[1]
    end
  end
  return faces
end

-- Integer x range [lo, hi] where 0 <= f0 + fx*x <= 1.
local function clampSpan(f0, fx, lo, hi)
  if fx > 1e-12 then
    lo = max(lo, ceil(-f0 / fx))
    hi = min(hi, floor((1 - f0) / fx))
  elseif fx < -1e-12 then
    lo = max(lo, ceil((1 - f0) / fx))
    hi = min(hi, floor(-f0 / fx))
  elseif f0 < 0 or f0 > 1 then
    return 1, 0
  end
  return lo, hi
end

-- Zoom (pixels per texel) that fits the whole model in a w x h area.
function R.fitZoom(w, h)
  return min(h * 0.86 / 36, w * 0.86 / 22)
end

---------------------------------------------------------------------------
-- Rendering

-- opts = {
--   width, height,
--   textures = { humanoid=tex, humanoid_leggings=tex },  -- either may be nil
--   show = { helmet=bool, chestplate=bool, leggings=bool, boots=bool },
--   yaw, pitch (degrees), zoom (px per texel), panX, panY (px)
-- }
-- Returns an RGBA Image; empty pixels are transparent.
function R.render(opts)
  local W, H = opts.width, opts.height
  local zoom = opts.zoom or R.fitZoom(W, H)
  local cyaw, syaw = cos(rad(opts.yaw or 0)), sin(rad(opts.yaw or 0))
  local cp, sp = cos(rad(opts.pitch or 0)), sin(rad(opts.pitch or 0))
  local cx, cy = W / 2 + (opts.panX or 0), H / 2 + (opts.panY or 0)

  -- Rotate a model-space vector into view space (x right, y up, z toward viewer).
  local function rotate(x, y, z)
    local x1 = x * cyaw + z * syaw
    local z1 = -x * syaw + z * cyaw
    return x1, y * cp - z1 * sp, y * sp + z1 * cp
  end

  local zbuf, cbuf = {}, {}
  local shadeCaches = {}
  local bias = 0

  for _, piece in ipairs(layout.PIECES) do
    local tex = opts.textures[piece.layer]
    if tex and (not opts.show or opts.show[piece.id] ~= false) then
      local texW, px, s = tex.w, tex.px, tex.scale
      for _, ref in ipairs(piece.bones) do
        -- Later bones win ties on coplanar faces (e.g. arms over the chest).
        bias = bias + 1e-3
        for _, f in ipairs(boxFaces(layout.BONES[ref[1]], ref[2])) do
          local ox, oy, oz = rotate(f.o[1], f.o[2] - MODEL_CENTER_Y, f.o[3])
          ox, oy = cx + ox * zoom, cy - oy * zoom
          local ux, uy, uz = rotate(f.du[1], f.du[2], f.du[3])
          ux, uy = ux * zoom, -uy * zoom
          local vx, vy, vz = rotate(f.dv[1], f.dv[2], f.dv[3])
          vx, vy = vx * zoom, -vy * zoom
          local det = ux * vy - vx * uy
          if abs(det) > 1e-6 then
            local _, _, nz = rotate(f.n[1], f.n[2], f.n[3])
            local shade = f.shade * (nz < 0 and INSIDE_SHADE or 1)
            local cache = shadeCaches[shade]
            if not cache then cache = {}; shadeCaches[shade] = cache end

            local ru, rv = floor(f.rect[1] * s), floor(f.rect[2] * s)
            local rw, rh = floor(f.rect[3] * s), floor(f.rect[4] * s)
            local idet = 1 / det
            local ax, bx = vy * idet, -uy * idet
            local ymin = max(0, floor(min(oy, oy + uy, oy + vy, oy + uy + vy)))
            local ymax = min(H - 1, floor(max(oy, oy + uy, oy + vy, oy + uy + vy)))
            local fz = oz + bias

            for py = ymin, ymax do
              local ry = py + 0.5 - oy
              local rx0 = 0.5 - ox
              -- Texture coords along this row: a = a0 + ax*x, b = b0 + bx*x (0..1)
              local a0 = (rx0 * vy - ry * vx) * idet
              local b0 = (ry * ux - rx0 * uy) * idet
              local lo, hi = clampSpan(a0, ax, 0, W - 1)
              if lo <= hi then lo, hi = clampSpan(b0, bx, lo, hi) end
              local rowBase = py * W
              for x = lo, hi do
                local a, b = a0 + ax * x, b0 + bx * x
                local tx, ty = floor(a * rw), floor(b * rh)
                if tx >= rw then tx = rw - 1 elseif tx < 0 then tx = 0 end
                if ty >= rh then ty = rh - 1 elseif ty < 0 then ty = 0 end
                local c = px[(rv + ty) * texW + ru + tx]
                if c and c >= ALPHA_CUTOFF then
                  local z = fz + a * uz + b * vz
                  local i = rowBase + x
                  local zb = zbuf[i]
                  if not zb or z > zb then
                    zbuf[i] = z
                    local packed = cache[c]
                    if not packed then
                      local r = floor((c & 0xff) * shade + 0.5)
                      local g = floor(((c >> 8) & 0xff) * shade + 0.5)
                      local bl = floor(((c >> 16) & 0xff) * shade + 0.5)
                      packed = spack("<I4", r | (g << 8) | (bl << 16) | 0xff000000)
                      cache[c] = packed
                    end
                    cbuf[i] = packed
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  local out, empty = {}, "\0\0\0\0"
  for i = 0, W * H - 1 do
    out[i + 1] = cbuf[i] or empty
  end
  local img = Image(W, H, ColorMode.RGB)
  img.bytes = table.concat(out)
  return img
end

return R
