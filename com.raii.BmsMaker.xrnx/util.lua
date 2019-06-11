-- tostring/tonumber for lua array index
function index_tostring(value)
  return tostring(value-1)
end
function index_tonumber(str)
  return tonumber(str)+1
end

-- tostring/tonumber for base36
function tostring36(value)
  local n = table.create()
  local s = ""
  n[1] = math.floor(value / 36)
  n[2] = value % 36
  for i, v in ipairs(n) do
    s = s .. (v < 10 and tostring(v) or string.char(65 + (v-10)))
  end
  return s
end

function tonumber36(str)
  local c = table.create()
  local n = 0
  c[1], c[2] = str:byte(1, 2)
  
  for i, v in ipairs(c) do
    -- Capitalize
    if c[i] >= 97 and c[i] <= 122 then
      c[i] = c[i] - 32
    end
    n = n * 36 + (c[i] <= 57 and c[i] - 48 or 10 + (c[i] - 65))
  end
  return n
end

-- Make (pattern_num) patterns of 64 lines and 1 sequence track + master track.
-- Clear all pattern contents and automations.
-- Delete all track DSPs.
function setup_test(pattern_num)
  local seq = renoise.song().sequencer
  seq:sort()

  for i = #seq.pattern_sequence, pattern_num + 1, -1 do
    seq:delete_sequence_at(i)
  end

  for i = 1, pattern_num do
    if i > #seq.pattern_sequence then
      seq:insert_new_pattern_at(i)
    end
    local pat = renoise.song():pattern(seq.pattern_sequence[i])

    pat:clear()
    pat.number_of_lines = 64
  end

  local found_seq = false
  local i = 1
  while i <= #renoise.song().tracks do
    local type = renoise.song():track(i).type

    if type == renoise.Track.TRACK_TYPE_SEQUENCER and not found_seq then
      found_seq = true
      i = i + 1
    elseif type == renoise.Track.TRACK_TYPE_MASTER then
      i = i + 1
    else
      renoise.song():delete_track_at(i)
    end
  end

  for i = 1, #renoise.song().tracks do
    local trk = renoise.song():track(i)
    for j = #trk.devices, 2, -1 do
      trk:delete_device_at(j)
    end
  end
end

-- Check equality of tables recursively.
-- value_map is a table of functions that maps value.
--   Can be nil.
--   Key: class name, Value: Mapping function
function table_eq_deep(a, b, value_map)
  if #table.keys(a) ~= #table.keys(b) then
    return false
  end

  for k, v in pairs(a) do
    if type(a[k]) ~= type(b[k]) then
      return false
      
    elseif type(a[k]) == "table" then
      if not table_eq_deep(a[k], b[k], value_map) then
        return false
      end

    elseif value_map ~= nil and value_map[type(a[k])] ~= nil then
      local f = value_map[type(a[k])]
      if f(a[k]) ~= f(b[k]) then
        return false
      end

    elseif a[k] ~= b[k] then
      return false

    end
  end

  return true
end

-- Quantize by q.
-- q = 1 when q is nil.
function quantize(x, q)
  if q == nil then q = 1 end
  return math.floor(x / q + 0.5) * q
end

function gcd(a, b)
  while a ~= 0 do
      a, b = b%a, a
  end
  return b
end

function lcm(a, b)
  return a / gcd(a, b) * b
end
