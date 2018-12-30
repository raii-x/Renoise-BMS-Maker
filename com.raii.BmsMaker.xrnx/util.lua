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
