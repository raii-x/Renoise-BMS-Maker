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


local function note_to_string(trk, note)
  local str = ""

  for line_idx, line in ipairs(note.lines) do
    for ncol_idx, ncol in ipairs(line.note_columns) do
      str = str .. ncol.note_string .. ncol.instrument_string

      if trk.volume_column_visible then
        str = str .. ncol.volume_string
      end
      if trk.panning_column_visible then
        str = str .. ncol.panning_string
      end
      if trk.delay_column_visible then
        str = str .. ncol.delay_string
      end
      if trk.sample_effects_column_visible then
        str = str .. ncol.effect_number_string .. ncol.effect_amount_string
      end
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
local function has_cut(trk, noteline)
  for ncol_idx, ncol in ipairs(noteline.note_columns) do
    if (trk.volume_column_visible and
      bit.band(ncol.volume_value, 0xff00) == 0x0c00) or
      (trk.panning_column_visible and
      bit.band(ncol.panning_value, 0xff00) == 0x0c00) then
      
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- analyze_column

local function analyze_column(target, state, note_opts)

  local lpb = renoise.song().transport.lpb
  local ecol_num = target.trk.visible_effect_columns

  -- lines, automation, number
  --   lines -> [array of {note_columns, effect_columns} tables]
  local note = nil
  local note_time
  local pos_bmse = 0
  local time = target.start_time
  local start_pt_idx = table.create()

  for i = 1, #target.auto_envs do
    start_pt_idx[i] = 1
  end
  
  local function note_end()
    -- Automation
    note.automation = table.create()
    for env_idx, env in ipairs(target.auto_envs) do
      local q = target.auto_prms[env_idx].time_quantum
      local nlines = note_opts.release_lines
      if not note_opts.one_shot then
        nlines = nlines + #note.lines
      end
      
      if start_pt_idx[env_idx] > #env then debug.start() end
      local slice
      slice, start_pt_idx[env_idx] = slice_points(
        env, start_pt_idx[env_idx], note_time, note_time + nlines - q)
      note.automation:insert(slice)
    end
    
    local str = note_to_string(target.trk, note)
    print("note", math.floor((note_time-1)/64), (note_time-1)%64)
    print(str)
    
    if state.notes_hash[str] == nil then
      state.notes_hash[str] = note
      state.notes:insert(note)
      note.number = state.note_number
      state.note_number = state.note_number + 1
    else
      note = state.notes_hash[str]
    end
    
    state.order[#state.order].note = note
    note = nil
  end
  
  -- Iterate lines
  for line_idx, line in ipairs(target.lines) do
  
    --local ncol = line:note_column(col_idx)
    
    if note and has_end(line, target.start_ncol_idx, target.end_ncol_idx) then
      note_end()
    end
  
    -- Note start
    if has_start(line, target.start_ncol_idx, target.end_ncol_idx) then
      note = {
        lines = table.create()
      }
      note_time = time
      state.order:insert {
        pos = pos_bmse,
        column = target.start_ncol_idx,
      }
    end
    
    -- Note line
    if note then
      local noteline = {
        note_columns = table.create(),
        effect_columns = table.create(),
      }
      for i = target.start_ncol_idx, target.end_ncol_idx do
        local ncol = line:note_column(i)
        noteline.note_columns:insert(ncol)
      end
      for i = 1, ecol_num do
        local ecol = line:effect_column(i)
        noteline.effect_columns:insert(ecol)
      end
      
      note.lines:insert(noteline)
      
      if note_opts.one_shot or has_cut(target.trk, noteline) then
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

--------------------------------------------------------------------------------
-- analyze

function analyze(note_opts, s_pos, e_pos)
  local sclock = os.clock()
  
  local pat_seq = renoise.song().sequencer.pattern_sequence
  local trk = renoise.song():track(note_opts.index)
  local ncol_num = trk.visible_note_columns
  
  -- Automation
  local auto_prms = search_automated_params(trk)
  local auto_envs = table.create()
  
  do
    local prm_idx = 1
    
    while prm_idx <= #auto_prms do
      local prm = auto_prms[prm_idx]
      local env = flatten_points(pat_seq, note_opts.index, prm)
      
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
  local lines, start_time =
    flatten_lines(pat_seq, note_opts.index, s_pos, e_pos)
  
  local target = {
    trk = trk,
    lines = lines,
    start_time = start_time,
    auto_envs = auto_envs,
    auto_prms = auto_prms,
    start_ncol_idx = nil,
    end_ncol_idx = nil,
  }

  local state = {
    notes = table.create(),
    order = table.create(),
    notes_hash = {},
    note_number = 0,
  }
  
  if note_opts.chord_mode then
    target.start_ncol_idx = 1
    target.end_ncol_idx = ncol_num
    analyze_column(target, state, note_opts)
  else
    for i = 1, ncol_num do
      target.start_ncol_idx = i
      target.end_ncol_idx = i
      analyze_column(target, state, note_opts)
    end
  end
  
  print("analyze", os.clock() - sclock)
  
  -- Check if the note length exceeds the maximum length of a pattern
  local release = note_opts.release_lines
  if release == 0 then
    -- For note off
    release = 1
  end
  
  for i, v in ipairs(state.notes) do
    if #v.lines + release > renoise.Pattern.MAX_NUMBER_OF_LINES then
      renoise.app():show_error(
        "The note length exceeds the maximum length of a pattern."
      )
      return nil
    end
  end
  
  local bms_data = {
    notes = state.notes,
    order = state.order,
    automated_params = auto_prms,
  }
  return bms_data
end

