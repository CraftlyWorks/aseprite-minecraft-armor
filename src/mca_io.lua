-- All file reading and downloading happens here. Aseprite asks once before
-- a script reads files or runs a program, and it asks per script file, so
-- keeping this in one file means one prompt ("Give full access" covers both).

local IO = {}

IO.WINDOWS = app.fs.pathSeparator == "\\"

-- Whole file as a string, or nil and an error message.
function IO.readFile(path)
  local ok, f, err = pcall(io.open, path, "rb")
  if not ok then return nil, "no permission to read files" end
  if not f then return nil, err end
  local data = f:read("a")
  f:close()
  return data
end

-- Quotes one command-line argument.
local function quote(arg)
  if IO.WINDOWS then return '"' .. arg:gsub('"', "") .. '"' end
  return "'" .. arg:gsub("'", "'\\''") .. "'"
end

local CURL_ERRORS = {
  [6] = "no internet connection",
  [7] = "no internet connection",
  [28] = "the server took too long",
  [127] = "curl isn't installed",
  [9009] = "curl isn't installed",
}
-- Dropped or reset connections are worth one more try.
local RETRY = { [7]=true, [35]=true, [52]=true, [56]=true }

-- Downloads a URL with curl (built into Windows 10+, macOS and most Linux
-- systems). With `toFile` the download is saved there. Returns the response
-- body (or "" when saved to a file), or nil and an error message. HTTP
-- errors like 404 still return the body, so callers can read the reason.
function IO.download(url, toFile)
  -- --retry also waits and retries when a server says "too many requests".
  local cmd = "curl -sL --max-time 20 --retry 2 --retry-delay 1 "
  if toFile then cmd = cmd .. "-o " .. quote(toFile) .. " " end
  cmd = cmd .. quote(url)
  for attempt = 1, 2 do
    local ok, handle = pcall(io.popen, cmd, "r")
    if not ok then return nil, "no permission to run curl" end
    if not handle then return nil, "couldn't run curl" end
    local body = handle:read("a")
    local success, _, code = handle:close()
    if success then return body end
    if attempt == 2 or not RETRY[code] then
      return nil, CURL_ERRORS[code] or ("download failed (curl error " .. tostring(code) .. ")")
    end
  end
end

return IO
