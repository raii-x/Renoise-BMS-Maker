-- Make an array of lines
-- start_time : lines from start of song
--              neeeded for automation functions
local function flatten_lines(pat_seq, trk_idx, s_pos, e_pos)
  local lines = table.create()
  local pos_list = table.create()
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
        pos_list:insert(renoise.SongPos(seq_idx, line_idx))
      end
      
    end
  end
  
  return lines, pos_list, start_time
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
      str = str .. ("%.3f,%.5f,"):format(pt.time, quantize(pt.value, 1 / 0x10000))
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

local function update_pos_beat(nume, deno, prm_lpb, lpb_pt_idx, time, max_line)
  if prm_lpb ~= nil then
    local lpb
    lpb, lpb_pt_idx = get_value_in_points(
      prm_lpb.linear, prm_lpb.envelope, lpb_pt_idx, time)
    lpb = quantize(prm_lpb.param.value_min +
      lpb * (prm_lpb.param.value_max - prm_lpb.param.value_min))
    
    local d = lcm(lpb, deno)
    if d > 0x10000000000000 / max_line then
      renoise.app():show_error("Least common multiple of LPBs is too big.")
      return nil
    end

    nume = nume * (d / deno)
    deno = d

    nume = nume + deno / lpb
        
  else
    nume = nume + 1
  end

  return nume, deno, lpb_pt_idx
end

--------------------------------------------------------------------------------
-- analyze_column

local function analyze_column(target, state, track_opt)

  local ecol_num = target.trk.visible_effect_columns

  -- lines, automation, number
  --   lines -> [array of {note_columns, effect_columns} tables]
  local note = nil
  local note_line_idx = 1
  local note_time
  local time = target.start_time
  local start_pt_idx = table.create()

  for i = 1, #target.auto_prms do
    start_pt_idx[i] = 1
  end

  local prm_lpb = target.param_tags.LPB
  local pos_beat_nume = 0
  local pos_beat_deno = renoise.song().transport.lpb
  local lpb_pt_idx = 1
  
  local function note_end()
    local nlines = track_opt.release_lines
    if not track_opt.one_shot then
      nlines = nlines + #note.lines
    end

    -- Check if the note length exceeds the maximum length of a pattern
    if nlines > renoise.Pattern.MAX_NUMBER_OF_LINES then
      state.err_exceed:insert(
        ("Track %02d: %s, Sequence %d, Line %d"):format(
          track_opt.index, target.trk.name,
          target.pos_list[note_line_idx].sequence - 1,
          target.pos_list[note_line_idx].line - 1))
      
      note = nil
      return
    end

    -- Automation
    note.automation = table.create()
    for prm_idx, prm in ipairs(target.auto_prms) do
      local q = prm.param.time_quantum
      
      local slice
      slice, start_pt_idx[prm_idx] = slice_points(
        prm.linear, prm.envelope, start_pt_idx[prm_idx], note_time, note_time + nlines - q)
      note.automation:insert(slice)
    end
    
    local str = note_to_string(target.trk, note)
    
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
    if note and has_end(line, target.start_ncol_idx, target.end_ncol_idx) then
      note_end()
    end
  
    -- Note start
    if has_start(line, target.start_ncol_idx, target.end_ncol_idx) then
      note = {
        lines = table.create()
      }
      note_line_idx = line_idx
      note_time = time
      state.order:insert {
        pos = quantize(pos_beat_nume / pos_beat_deno * BMS_RESOLUTION / 4),
        column = target.start_ncol_idx,
        note = nil,
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
      
      if track_opt.one_shot or has_cut(target.trk, noteline) then
        note_end()
      end
    end
    
    pos_beat_nume, pos_beat_deno, lpb_pt_idx = update_pos_beat(
      pos_beat_nume, pos_beat_deno, prm_lpb, lpb_pt_idx, time, #target.lines)

    if pos_beat_nume == nil then
      return false
    end

    time = time + 1
  end
  
  if note then
    note_end()
  end

  return true
end

--------------------------------------------------------------------------------
-- analyze_track

local function analyze_track(track_opt, params, param_tags, s_pos, e_pos)
  local pat_seq = renoise.song().sequencer.pattern_sequence
  local trk = renoise.song():track(track_opt.index)
  local ncol_num = trk.visible_note_columns
  
  -- Automation
  local auto_prms = filter_track_params(params, track_opt.index)
  
  -- Flatten lines
  local lines, pos_list, start_time =
    flatten_lines(pat_seq, track_opt.index, s_pos, e_pos)
  
  local target = {
    trk = trk,
    lines = lines,
    pos_list = pos_list,
    start_time = start_time,
    auto_prms = auto_prms,
    param_tags = param_tags,
    start_ncol_idx = nil,
    end_ncol_idx = nil,
  }

  local state = {
    notes = table.create(),
    order = table.create(),
    notes_hash = {},
    note_number = 0,
    err_exceed = table.create(),
  }
  
  if track_opt.chord_mode then
    target.start_ncol_idx = 1
    target.end_ncol_idx = ncol_num
    if not analyze_column(target, state, track_opt) then
      return nil
    end
  else
    for i = 1, ncol_num do
      target.start_ncol_idx = i
      target.end_ncol_idx = i
      if not analyze_column(target, state, track_opt) then
        return nil
      end
    end
  end
  
  local bms_data = {
    notes = state.notes,
    order = state.order,
    automated_params = auto_prms,
  }
  return bms_data, state.err_exceed
end

--------------------------------------------------------------------------------
-- analyze_bpm
-- If error, return false.

local function analyze_bpm(s_pos, e_pos, prm_bpm, prm_lpb)
  if prm_bpm == nil then
    return nil
  end

  local pat_seq = renoise.song().sequencer.pattern_sequence

  local lines, pos_list, start_time =
    flatten_lines(pat_seq, prm_bpm.trk_idx, s_pos, e_pos)

  local pos_beat_nume = 0
  local pos_beat_deno = renoise.song().transport.lpb
  local lpb_pt_idx = 1

  local t = table.create()
  local bpm_pt_idx = 1

  for time = start_time, start_time + #lines - 1 do

    for i = bpm_pt_idx, #prm_bpm.envelope do
      local pt = prm_bpm.envelope[i]

      if pt.time > time then
        break
      elseif pt.time == time then
        t:insert {
          pos = quantize(pos_beat_nume / pos_beat_deno * BMS_RESOLUTION / 4),
          value = quantize(prm_bpm.param.value_min +
            pt.value * (prm_bpm.param.value_max - prm_bpm.param.value_min))
        }
      end

      bpm_pt_idx = i
    end
    
    pos_beat_nume, pos_beat_deno, lpb_pt_idx = update_pos_beat(
      pos_beat_nume, pos_beat_deno, prm_lpb, lpb_pt_idx, time, #lines)

    if pos_beat_nume == nil then
      return false
    end
  end

  return t
end

--------------------------------------------------------------------------------
-- analyze

function analyze(en_track_opts, s_pos, e_pos)
  local params, param_tags = flatten_all_params()
  if params == nil then
    return nil
  end

  local bms_data = table.create()

  local err_exceed = table.create()

  for i, track_opt in ipairs(en_track_opts) do
    local data, exc = analyze_track(track_opt, params, param_tags, s_pos, e_pos)
    if data == nil then
      return nil
    end
    bms_data:insert(data)

    for _, v in ipairs(exc) do
      err_exceed:insert(v)
    end
  end

  if #err_exceed >= 1 then
    renoise.app():show_error(
      "The note length exceeds the maximum length of a pattern:\n" ..
      err_exceed:concat("\n")
    )
    return nil
  end

  local bpm_data = analyze_bpm(s_pos, e_pos, param_tags.BPM, param_tags.LPB)
  if bpm_data == false then
    return nil
  end

  return bms_data, bpm_data
end
