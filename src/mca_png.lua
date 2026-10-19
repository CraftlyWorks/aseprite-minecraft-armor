-- Small PNG reader. Loading images with Image{ fromFile } opens them as
-- documents behind the scenes (and adds them to the recent files list), so
-- textures and skins that aren't open in a tab are decoded here instead.
-- Supports every colour type, bit depths 1-16 and interlaced images.

local P = {}

local sbyte = string.byte

---------------------------------------------------------------------------
-- Inflate (RFC 1951)

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                   35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                    8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                     7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- Canonical Huffman table from code lengths (lengths[0..n-1]).
local function huffman(lengths, n)
  local count, offs, symbol = {}, {}, {}
  for len = 0, 15 do count[len] = 0 end
  for s = 0, n - 1 do count[lengths[s] or 0] = count[lengths[s] or 0] + 1 end
  offs[1] = 0
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  for s = 0, n - 1 do
    local len = lengths[s] or 0
    if len ~= 0 then
      symbol[offs[len]] = s
      offs[len] = offs[len] + 1
    end
  end
  return { count=count, symbol=symbol }
end

local function inflate(data, pos)
  local bitbuf, bitcnt = 0, 0
  local out, n = {}, 0

  local function bits(need)
    while bitcnt < need do
      local b = sbyte(data, pos)
      if not b then error("PNG data ended early") end
      pos = pos + 1
      bitbuf = bitbuf | (b << bitcnt)
      bitcnt = bitcnt + 8
    end
    local v = bitbuf & ((1 << need) - 1)
    bitbuf = bitbuf >> need
    bitcnt = bitcnt - need
    return v
  end

  local function decode(h)
    local code, first, index = 0, 0, 0
    local count, symbol = h.count, h.symbol
    for len = 1, 15 do
      code = code | bits(1)
      local c = count[len]
      if code - c < first then return symbol[index + (code - first)] end
      index = index + c
      first = (first + c) << 1
      code = code << 1
    end
    error("bad PNG data")
  end

  local function codes(lencode, distcode)
    while true do
      local sym = decode(lencode)
      if sym < 256 then
        n = n + 1
        out[n] = sym
      elseif sym == 256 then
        return
      else
        sym = sym - 256
        local len = LEN_BASE[sym] + bits(LEN_EXTRA[sym])
        local dsym = decode(distcode) + 1
        local dist = DIST_BASE[dsym] + bits(DIST_EXTRA[dsym])
        if dist > n then error("bad PNG data") end
        for _ = 1, len do
          n = n + 1
          out[n] = out[n - dist]
        end
      end
    end
  end

  local fixedLen, fixedDist
  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      bitbuf, bitcnt = 0, 0
      local b1, b2, b3, b4 = sbyte(data, pos, pos + 3)
      local len = b1 | (b2 << 8)
      if (len ~ (b3 | (b4 << 8))) ~= 0xffff then error("bad PNG data") end
      pos = pos + 4
      for i = 0, len - 1 do out[n + 1 + i] = sbyte(data, pos + i) end
      n = n + len
      pos = pos + len
    elseif kind == 1 then
      if not fixedLen then
        local l = {}
        for s = 0, 143 do l[s] = 8 end
        for s = 144, 255 do l[s] = 9 end
        for s = 256, 279 do l[s] = 7 end
        for s = 280, 287 do l[s] = 8 end
        fixedLen = huffman(l, 288)
        local d = {}
        for s = 0, 29 do d[s] = 5 end
        fixedDist = huffman(d, 30)
      end
      codes(fixedLen, fixedDist)
    elseif kind == 2 then
      local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
      local lengths = {}
      for i = 1, 19 do lengths[CODE_LENGTH_ORDER[i]] = (i <= ncode) and bits(3) or 0 end
      local lencode = huffman(lengths, 19)
      lengths = {}
      local i = 0
      while i < nlen + ndist do
        local sym = decode(lencode)
        if sym < 16 then
          lengths[i] = sym
          i = i + 1
        else
          local value, rep = 0, 0
          if sym == 16 then
            if i == 0 then error("bad PNG data") end
            value, rep = lengths[i - 1], 3 + bits(2)
          elseif sym == 17 then
            rep = 3 + bits(3)
          else
            rep = 11 + bits(7)
          end
          for _ = 1, rep do
            lengths[i] = value
            i = i + 1
          end
        end
      end
      local lit, dist = {}, {}
      for s = 0, nlen - 1 do lit[s] = lengths[s] end
      for s = 0, ndist - 1 do dist[s] = lengths[nlen + s] end
      codes(huffman(lit, nlen), huffman(dist, ndist))
    else
      error("bad PNG data")
    end
  until last == 1
  return out
end

---------------------------------------------------------------------------
-- PNG

local SIGNATURE = "\137PNG\r\n\26\n"
local CHANNELS = { [0]=1, [2]=3, [3]=1, [4]=2, [6]=4 }
-- Adam7 passes: x start, y start, x step, y step
local ADAM7 = { {0, 0, 8, 8}, {4, 0, 8, 8}, {0, 4, 4, 8}, {2, 0, 4, 4},
                {0, 2, 2, 4}, {1, 0, 2, 2}, {0, 1, 1, 2} }

local function u32(s, i)
  local a, b, c, d = sbyte(s, i, i + 3)
  return (a << 24) | (b << 16) | (c << 8) | d
end

-- Decodes PNG file contents. Returns width, height and a table of RGBA
-- pixels ({ [y*width + x] = rgba }), or nil and an error message.
function P.decode(data)
  local ok, w, h, px = pcall(function()
    if data:sub(1, 8) ~= SIGNATURE then error("not a PNG file") end
    local pos = 9
    local width, height, depth, ctype, interlace
    local palette, trns = {}, nil
    local idat = {}
    while pos + 8 <= #data do
      local len, kind = u32(data, pos), data:sub(pos + 4, pos + 7)
      local body = pos + 8
      if kind == "IHDR" then
        width, height = u32(data, body), u32(data, body + 4)
        depth, ctype = sbyte(data, body + 8), sbyte(data, body + 9)
        interlace = sbyte(data, body + 12)
      elseif kind == "PLTE" then
        for i = 0, len // 3 - 1 do
          local r, g, b = sbyte(data, body + i * 3, body + i * 3 + 2)
          palette[i] = r | (g << 8) | (b << 16) | 0xff000000
        end
      elseif kind == "tRNS" then
        trns = data:sub(body, body + len - 1)
      elseif kind == "IDAT" then
        idat[#idat + 1] = data:sub(body, body + len - 1)
      elseif kind == "IEND" then
        break
      end
      pos = body + len + 4
    end
    if not width or not CHANNELS[ctype] then error("unsupported PNG") end

    local z = table.concat(idat)
    if (sbyte(z, 2) & 0x20) ~= 0 then error("unsupported PNG") end
    local raw = inflate(z, 3)

    local channels = CHANNELS[ctype]
    local bitsPerPixel = channels * depth
    local bpp = math.max(1, bitsPerPixel // 8)
    local maxv = (1 << depth) - 1

    -- Palette transparency, and the single transparent colour of grey/RGB.
    local keyGray, keyRGB
    if trns then
      if ctype == 3 then
        for i = 0, #trns - 1 do
          if palette[i] then palette[i] = (palette[i] & 0xffffff) | (sbyte(trns, i + 1) << 24) end
        end
      elseif ctype == 0 then
        keyGray = (sbyte(trns, 1) << 8) | sbyte(trns, 2)
      elseif ctype == 2 then
        keyRGB = { (sbyte(trns, 1) << 8) | sbyte(trns, 2), (sbyte(trns, 3) << 8) | sbyte(trns, 4),
                   (sbyte(trns, 5) << 8) | sbyte(trns, 6) }
      end
    end

    local out = {}
    local rpos = 1

    local function readPass(x0, y0, dx, dy)
      local pw = (width - x0 + dx - 1) // dx
      local ph = (height - y0 + dy - 1) // dy
      if pw <= 0 or ph <= 0 then return end
      local stride = (pw * bitsPerPixel + 7) // 8
      local prev = {}
      for i = 1, stride do prev[i] = 0 end
      for row = 0, ph - 1 do
        local filter = raw[rpos]
        rpos = rpos + 1
        local cur = {}
        for i = 1, stride do
          local x = raw[rpos + i - 1]
          local a = (i > bpp) and cur[i - bpp] or 0
          local b = prev[i]
          if filter == 1 then x = x + a
          elseif filter == 2 then x = x + b
          elseif filter == 3 then x = x + ((a + b) >> 1)
          elseif filter == 4 then
            local c = (i > bpp) and prev[i - bpp] or 0
            local p = a + b - c
            local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
            if pa <= pb and pa <= pc then x = x + a elseif pb <= pc then x = x + b else x = x + c end
          end
          cur[i] = x & 0xff
        end
        rpos = rpos + stride

        -- Samples of this row, scaled to 8 bits (16-bit keeps the high byte).
        local function sample(k)
          if depth == 8 then return cur[k + 1] end
          if depth == 16 then return cur[2 * k + 1], (cur[2 * k + 1] << 8) | cur[2 * k + 2] end
          local bit = k * depth
          local byte = cur[(bit >> 3) + 1]
          return (byte >> (8 - depth - (bit & 7))) & maxv
        end

        local y = y0 + row * dy
        for col = 0, pw - 1 do
          local c
          local k = col * channels
          if ctype == 3 then
            c = palette[sample(k)] or 0
          elseif ctype == 0 then
            local g, g16 = sample(k)
            local raw16 = (depth == 16) and g16 or g
            if depth < 8 then g = g * 255 // maxv end
            c = (keyGray and raw16 == keyGray) and 0 or (g | (g << 8) | (g << 16) | 0xff000000)
          elseif ctype == 4 then
            local g, a = sample(k), sample(k + 1)
            c = g | (g << 8) | (g << 16) | (a << 24)
          elseif ctype == 2 then
            local r, r16 = sample(k)
            local g, g16 = sample(k + 1)
            local b, b16 = sample(k + 2)
            local transparent = false
            if keyRGB then
              if depth == 16 then
                transparent = r16 == keyRGB[1] and g16 == keyRGB[2] and b16 == keyRGB[3]
              else
                transparent = r == keyRGB[1] and g == keyRGB[2] and b == keyRGB[3]
              end
            end
            c = transparent and 0 or (r | (g << 8) | (b << 16) | 0xff000000)
          else
            local r, g, b, a = sample(k), sample(k + 1), sample(k + 2), sample(k + 3)
            c = r | (g << 8) | (b << 16) | (a << 24)
          end
          out[y * width + x0 + col * dx] = c
        end
        prev = cur
      end
    end

    if interlace == 1 then
      for _, pass in ipairs(ADAM7) do readPass(pass[1], pass[2], pass[3], pass[4]) end
    else
      readPass(0, 0, 1, 1)
    end
    return width, height, out
  end)
  if not ok then return nil, tostring(w):gsub("^.-:%d+: ", "") end
  return w, h, px
end

return P
