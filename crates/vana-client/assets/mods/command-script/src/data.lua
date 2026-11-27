-- Saved scripts by job: scripts-<World>.json (scripts.json until the world is known).
--
-- {
--   "ALL": { "pull": { "lines": ["/ja \"Provoke\" <t>", "then /ws \"Fast Blade\" <t>"] } },
--   "RDM": { "nuke": { "lines": ["/ma \"Fire IV\" <t>"] } }
-- }

local M = {}

local LEGACY = "scripts.json"
local FILE = LEGACY

local deps = nil
local db = {}

local function is_table(v) return type(v) == "table" end

function M.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "a | b" or semicolon-separated -> lines
function M.split_lines(text)
  local out = {}
  local t = tostring(text or "")
  if t:find("|", 1, true) then
    for piece in t:gmatch("[^|]+") do
      piece = M.trim(piece)
      if piece ~= "" then out[#out + 1] = piece end
    end
    return out
  end
  for piece in t:gmatch("[^;\n]+") do
    piece = M.trim(piece)
    if piece ~= "" then out[#out + 1] = piece end
  end
  return out
end

function M.join_lines(lines)
  return table.concat(lines or {}, " | ")
end

function M.sanitize_word(word)
  word = M.trim(word):lower():gsub("[^%w_%-]", "")
  return word ~= "" and word or nil
end

local function bucket(job)
  job = (job == "ALL") and "ALL" or M.trim(job):upper()
  if job == "" then job = "ALL" end
  if not db[job] then db[job] = {} end
  return db[job]
end

local function read_json(file, raw)
  if not raw or raw:match("^%s*$") then return {} end
  local ok, parsed = pcall(deps.decode, raw)
  if ok and is_table(parsed) then return parsed end
  pcall(deps.write, file .. ".bad", raw)
  return nil, tostring(parsed)
end

local function write(file, t)
  local ok, err = pcall(function() deps.write(file, deps.encode(t)) end)
  if not ok and deps.log then deps.log("could not save " .. file .. ": " .. tostring(err)) end
  return ok, err
end

function M.init(d)
  deps = d
  return M.load()
end

function M.load()
  local raw = deps.read(FILE)
  if not raw and FILE ~= LEGACY then raw = deps.read(LEGACY) end
  local parsed, why = read_json(FILE, raw)
  db = parsed or {}
  if not parsed then return false, why, FILE end
  return true
end

function M.save()
  return write(FILE, db)
end

function M.file() return FILE end

function M.set_world(name)
  local file = name and name ~= "" and ("scripts-" .. (name:gsub("[^%w%-_]", "_")) .. ".json") or LEGACY
  if file == FILE then return false end
  FILE = file
  return true, M.load()
end

function M.jobs_in_file()
  local jobs = {}
  for k in pairs(db) do
    if is_table(db[k]) and next(db[k]) then jobs[#jobs + 1] = k end
  end
  table.sort(jobs)
  return jobs
end

-- Merged word -> { lines, scope } for `job` (main job abbr) and ALL.
function M.list(job)
  local out = {}
  for word, entry in pairs(bucket("ALL")) do
    if is_table(entry) and type(entry.lines) == "table" then
      out[word] = { lines = entry.lines, scope = "ALL" }
    end
  end
  job = M.trim(job):upper()
  if job ~= "" and job ~= "ALL" then
    for word, entry in pairs(bucket(job)) do
      if is_table(entry) and type(entry.lines) == "table" then
        out[word] = { lines = entry.lines, scope = job }
      end
    end
  end
  return out
end

function M.get(word, job)
  word = M.sanitize_word(word)
  if not word then return nil end
  local merged = M.list(job)
  return merged[word]
end

function M.set(word, lines, scope)
  word = M.sanitize_word(word)
  if not word or type(lines) ~= "table" or #lines == 0 then return false end
  scope = (scope == "ALL") and "ALL" or M.trim(scope):upper()
  if scope == "" then
    local mj = require("src.jobs").current()
    scope = mj or "ALL"
  end
  bucket(scope)[word] = { lines = lines }
  local saved, err = M.save()
  return saved, err
end

function M.remove(word, scope)
  word = M.sanitize_word(word)
  if not word then return false end
  local entry = M.get(word, require("src.jobs").current())
  if not entry then return false end
  scope = scope or entry.scope
  scope = (scope == "ALL") and "ALL" or M.trim(scope):upper()
  local b = bucket(scope)
  if not b[word] then return false end
  b[word] = nil
  M.save()
  return true, scope
end

-- Sorted { word, entry } for UI.
function M.sorted(job)
  local merged = M.list(job)
  local keys = {}
  for w in pairs(merged) do keys[#keys + 1] = w end
  table.sort(keys)
  local rows = {}
  for _, w in ipairs(keys) do
    rows[#rows + 1] = { word = w, entry = merged[w] }
  end
  return rows
end

return M