-- Make an array of lines
local function flatten_lines(pat_seq, trk_idx, s_pos, e_pos)
  local lines = table.create()
  local start_time = 1
  
  for seq_idx, pat_idx in ipairs(pat_seq) do
    if seq_idx > e_pos.sequence then
      break
    end
    
    local pat = renoise.song():pattern(pat_idx)
    local pattrk = pat:track(trk_idx)
    
    if seq_idx < s_pos.sequence then
      start_time = start_time + pat.number_of_lines
      
    else
      local s_line_idx, e_line_idx
      
      if seq_idx == s_pos.sequence then
        s_line_idx = s_pos.line
        start_time = start_time + s_pos.line - 1
      else
        s_line_idx = 1
      end
      if seq_idx == e_pos.sequence then
        e_line_idx = e_pos.line
      else
        e_line_idx = pat.number_of_lines
      end
  
      for line_idx = s_line_idx, e_line_idx do
        lines:insert(pattrk:line(line_idx))
      end
      
    end
  end
  
  return lines, start_time
end


local function quantize_value(x)
  return math.floor(x * 256 + 0.5) / 256
end


local function note_to_string(note)
  --[[local strs = table.create()
  for line_idx, line in ipairs(note.lines) do
    strs:insert(tostring(line.note_columns[1]))
    strs:insert("\n")
  end
  for env_idx, env in ipairs(note.automation) do
    for pt_idx, pt in ipairs(env) do
      strs:insert(("%.2f,%.3f,"):format(pt.time, quantize_value(pt.value)))
    end
    strs:insert("\n")
  end
  
  return strs:concat()]]
  
  local str = ""
  for line_idx, line in ipairs(note.lines) do
    for ncol_idx, ncol in ipairs(line.note_columns) do
      str = str .. tostring(ncol)
    end
    for ecol_idx, ecol in ipairs(line.effect_columns) do
      str = str .. tostring(ecol)
    end
    str = str .. "\n"
  end
  for env_idx, env in ipairs(note.automation) do
    for pt_idx, pt in ipairs(env) do
      str = str .. ("%.2f,%.3f,"):format(pt.time, quantize_value(pt.value))
    end
    str = str .. "\n"
  end
  
  return str
end

-- Does the line have a note end(not empty)?
local function has_end(line, start_ncol_idx, end_ncol_idx)
  for i = start_ncol_idx, end_ncol_idx do
    -- not empty
    if line:note_column(i).note_value ~= 121 then
      return true
    end
  end
  return false
end

-- Does the line have a note start(not OFF nor empty)?
local function has_start(line, start_ncol_idx, end_ncol_idx)
  for i = start_ncol_idx, end_ncol_idx do
    -- not OFF nor empty
    if line:note_column(i).note_value < 120 then
      return true
    end
  end
  return false
end

-- Does the line have a note cut(Cx command on volume or panning column)?
local function has_cut(line)
  for ncol_idx, ncol in ipairs(line.note_columns) do
    if bit.band(ncol.volume_value, 0xff00) == 0x0c00 or
      bit.band(ncol.panning_value, 0xff00) == 0x0c00 then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- analyze

function analyze(trk_idx, note_opts, s_pos, e_pos)
  local sclock = os.clock()
  
  local notes = table.create()
  local order = table.create()
  local notes_hash = {}
  local note_number = 0
  local lpb = renoise.song().transport.lpb
  local pat_seq = renoise.song().sequencer.pattern_sequence
  local trk = renoise.song():track(trk_idx)
  local ncol_num = trk.visible_note_columns
  local ecol_num = trk.visible_effect_columns
  
  -- Automation
  local auto_prms = search_automated_params(trk)
  local auto_envs = table.create()
  
  do
    local prm_idx = 1
    
    while prm_idx <= #auto_prms do
      local prm = auto_prms[prm_idx]
      local env = flatten_points(pat_seq, trk_idx, prm)
      
      if env then
        auto_envs[prm_idx] = env
        prm_idx = prm_idx + 1
      -- Command controled parameter
      else
        auto_prms:remove(prm_idx)
      end
    end
  end
  
  -- Flatten lines
  local lines, start_time = flatten_lines(pat_seq, trk_idx, s_pos, e_pos)
  
  local function analyze_column(start_ncol_idx, end_ncol_idx)
  
    -- lines, automation, number
    --   lines -> [array of {note_columns, effect_columns} tables]
    local note = nil
    local note_time
    local pos_bmse = 0
    local time = start_time
    local start_pt_idx = 1
    
    local function note_end()
      -- Automation
      note.automation = table.create()
      for env_idx, env in ipairs(auto_envs) do
        local q = auto_prms[env_idx].time_quantum
        local nlines = note_opts.release_lines
        if note_opts.duration then
          nlines = nlines + #note.lines
        end
        
        local slice
        slice, start_pt_idx = slice_points(
          env, start_pt_idx, note_time, note_time + nlines - q)
        note.automation:insert(slice)
      end
      
      local str = note_to_string(note)
      print("note", math.floor((note_time-1)/64), (note_time-1)%64)
      print(str)
      
      if notes_hash[str] == nil then
        notes_hash[str] = note
        notes:insert(note)
        note.number = note_number
        note_number = note_number + 1
      else
        note = notes_hash[str]
      end
      
      order[#order].note = note
      note = nil
    end
    
    -- Iterate lines
    for line_idx, line in ipairs(lines) do
    
      --local ncol = line:note_column(col_idx)
      
      if note and has_end(line, start_ncol_idx, end_ncol_idx) then
        note_end()
      end
    
      -- Note start
      if has_start(line, start_ncol_idx, end_ncol_idx) then
        note = {
          lines = table.create()
        }
        note_time = time
        order:insert {
          pos = pos_bmse,
          column = start_ncol_idx,
        }
      end
      
      -- Note line
      if note then
        local noteline = {
          note_columns = table.create(),
          effect_columns = table.create(),
        }
        for i = start_ncol_idx, end_ncol_idx do
          local ncol = line:note_column(i)
          noteline.note_columns:insert(ncol)
        end
        for i = 1, ecol_num do
          local ecol = line:effect_column(i)
          noteline.effect_columns:insert(ecol)
        end
        
        note.lines:insert(noteline)
        
        if not note_opts.duration or has_cut(noteline) then
          note_end()
        end
      end
      
      pos_bmse = pos_bmse + 48 / lpb
      time = time + 1
      
    end
    
    if note then
      note_end()
    end
    
  end
  
  if note_opts.chord_mode then
    analyze_column(1, ncol_num)
  else
    for i = 1, ncol_num do
      analyze_column(i, i)
    end
  end
  
  print("analyze", os.clock() - sclock)
  
  local bms_data = {
    notes = notes,
    order = order,
    automated_params = auto_prms,
  }
  return bms_data
end

