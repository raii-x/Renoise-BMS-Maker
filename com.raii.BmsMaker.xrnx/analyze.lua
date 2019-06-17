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


class "Analyzer"
  function Analyzer:__init(en_track_opts, s_pos, e_pos)
    self.en_track_opts = en_track_opts
    self.s_pos = s_pos
    self.e_pos = e_pos

    self.params = nil
    self.param_tags = nil
    self.lines = nil
    self.pos_list = nil
    -- lines from start of song
    -- neeeded for automation functions
    self.start_time = nil
  end

  ------------------------------------------------------------------------------
  -- analyze

  function Analyzer:analyze()
    self.params, self.param_tags = flatten_all_params()
    if self.params == nil then
      return nil
    end

    self:_flatten_lines()
  
    local bms_data = table.create()
  
    local err_exceed = table.create()
  
    for i, track_opt in ipairs(self.en_track_opts) do
      local analyzer = TrackAnalyzer(
        track_opt, self.lines[track_opt.index], self.pos_list, self.start_time,
        self.params, self.param_tags)
      local data, exc = analyzer:analyze()
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
  
    local bpm_data = self:_analyze_bpm(self.param_tags.BPM, self.param_tags.LPB)
    if bpm_data == false then
      return nil
    end
  
    return bms_data, bpm_data
  end

  -- Make an array of lines

  function Analyzer:_flatten_lines()
    local pat_seq = renoise.song().sequencer.pattern_sequence

    self.pos_list = table.create()
    self.start_time = 1
    
    for seq_idx, pat_idx in ipairs(pat_seq) do
      if seq_idx > self.e_pos.sequence then
        break
      end
      
      local pat = renoise.song():pattern(pat_idx)
      
      if seq_idx < self.s_pos.sequence then
        self.start_time = self.start_time + pat.number_of_lines
        
      else
        local s_line_idx, e_line_idx
        
        if seq_idx == self.s_pos.sequence then
          s_line_idx = self.s_pos.line
          self.start_time = self.start_time + self.s_pos.line - 1
        else
          s_line_idx = 1
        end
        if seq_idx == self.e_pos.sequence then
          e_line_idx = self.e_pos.line
        else
          e_line_idx = pat.number_of_lines
        end
    
        for line_idx = s_line_idx, e_line_idx do
          self.pos_list:insert(renoise.SongPos(seq_idx, line_idx))
        end
        
      end
    end

    self.lines = table.create()
    for trk_idx = 1, #renoise.song().tracks do
      self.lines[trk_idx] = false
    end

    for _, track_opt in ipairs(self.en_track_opts) do

      local trk_idx = track_opt.index
      self.lines[trk_idx] = table.create()

      for seq_idx = self.s_pos.sequence, self.e_pos.sequence do
        local pat_idx = pat_seq[seq_idx]
        local pat = renoise.song():pattern(pat_idx)
        local pattrk = pat:track(trk_idx)
        
        local s_line_idx, e_line_idx
        
        if seq_idx == self.s_pos.sequence then
          s_line_idx = self.s_pos.line
        else
          s_line_idx = 1
        end
        if seq_idx == self.e_pos.sequence then
          e_line_idx = self.e_pos.line
        else
          e_line_idx = pat.number_of_lines
        end
    
        for line_idx = s_line_idx, e_line_idx do
          self.lines[trk_idx]:insert(pattrk:line(line_idx))
        end
      end

    end

  end

  ------------------------------------------------------------------------------
  -- _analyze_bpm
  -- If error, return false.

  function Analyzer:_analyze_bpm(prm_bpm, prm_lpb)
    if prm_bpm == nil then
      return nil
    end

    local pos_beat_nume = 0
    local pos_beat_deno = renoise.song().transport.lpb
    local lpb_pt_idx = 1

    local t = table.create()
    local bpm_pt_idx = 1

    for time = self.start_time, self.start_time + #self.pos_list - 1 do

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
        pos_beat_nume, pos_beat_deno, prm_lpb, lpb_pt_idx, time, #self.pos_list)

      if pos_beat_nume == nil then
        return false
      end
    end

    return t
  end


class "TrackAnalyzer"
  function TrackAnalyzer:__init(track_opt, lines, pos_list, start_time, params, param_tags)
    self.track_opt = track_opt

    self.track = renoise.song():track(track_opt.index)
    self.lines = lines
    self.pos_list = pos_list
    self.start_time = start_time
    self.auto_prms = filter_track_params(params, self.track_opt.index)
    self.param_tags = param_tags

    self.notes = table.create()
    self.order = table.create()
    self.notes_hash = {}
    self.note_number = 0
    self.err_exceed = table.create()
  end

  ------------------------------------------------------------------------------
  -- analyze

  function TrackAnalyzer:analyze()
    -- local pat_seq = renoise.song().sequencer.pattern_sequence
    local ncol_num = self.track.visible_note_columns
    
    -- local target = {
    --   trk = trk,
    --   lines = lines,
    --   pos_list = pos_list,
    --   start_time = start_time,
    --   auto_prms = auto_prms,
    --   param_tags = param_tags,
    --   start_ncol_idx = nil,
    --   end_ncol_idx = nil,
    -- }

    -- local state = {
    --   notes = table.create(),
    --   order = table.create(),
    --   notes_hash = {},
    --   note_number = 0,
    --   err_exceed = table.create(),
    -- }
    
    if self.track_opt.chord_mode then
      if not self:_analyze_column(1, ncol_num) then
        return nil
      end
    else
      for i = 1, ncol_num do
        if not self:_analyze_column(i, i) then
          return nil
        end
      end
    end
    
    local bms_data = {
      notes = self.notes,
      order = self.order,
      automated_params = self.auto_prms,
    }
    return bms_data, self.err_exceed
  end

  ------------------------------------------------------------------------------
  -- _analyze_column

  function TrackAnalyzer:_analyze_column(start_ncol_idx, end_ncol_idx)

    local ecol_num = self.track.visible_effect_columns

    -- lines, automation, number
    --   lines -> [array of {note_columns, effect_columns} tables]
    local note = nil
    local note_line_idx = 1
    local note_time
    local time = self.start_time
    local start_pt_idx = table.create()

    for i = 1, #self.auto_prms do
      start_pt_idx[i] = 1
    end

    local prm_lpb = self.param_tags.LPB
    local pos_beat_nume = 0
    local pos_beat_deno = renoise.song().transport.lpb
    local lpb_pt_idx = 1
    
    local function note_end()
      local nlines = self.track_opt.release_lines
      if not self.track_opt.one_shot then
        nlines = nlines + #note.lines
      end

      -- Check if the note length exceeds the maximum length of a pattern
      if nlines > renoise.Pattern.MAX_NUMBER_OF_LINES then
        self.err_exceed:insert(
          ("Track %02d: %s, Sequence %d, Line %d"):format(
            self.track_opt.index, self.track.name,
            self.pos_list[note_line_idx].sequence - 1,
            self.pos_list[note_line_idx].line - 1))
        
        note = nil
        return
      end

      -- Automation
      note.automation = table.create()
      for prm_idx, prm in ipairs(self.auto_prms) do
        local q = prm.param.time_quantum
        
        local slice
        slice, start_pt_idx[prm_idx] = slice_points(
          prm.linear, prm.envelope, start_pt_idx[prm_idx], note_time, note_time + nlines - q)
        note.automation:insert(slice)
      end
      
      local str = self:_note_to_string(note)
      
      if self.notes_hash[str] == nil then
        self.notes_hash[str] = note
        self.notes:insert(note)
        note.number = self.note_number
        self.note_number = self.note_number + 1
      else
        note = self.notes_hash[str]
      end
      
      self.order[#self.order].note = note
      note = nil
    end

    -- Iterate lines
    for line_idx, line in ipairs(self.lines) do
      if note and self:_has_end(line, start_ncol_idx, end_ncol_idx) then
        note_end()
      end
    
      -- Note start
      if self:_has_start(line, start_ncol_idx, end_ncol_idx) then
        note = {
          lines = table.create()
        }
        note_line_idx = line_idx
        note_time = time
        self.order:insert {
          pos = quantize(pos_beat_nume / pos_beat_deno * BMS_RESOLUTION / 4),
          column = start_ncol_idx,
          note = nil,
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
        
        if self.track_opt.one_shot or self:_has_cut(noteline) then
          note_end()
        end
      end
      
      pos_beat_nume, pos_beat_deno, lpb_pt_idx = update_pos_beat(
        pos_beat_nume, pos_beat_deno, prm_lpb, lpb_pt_idx, time, #self.lines)

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

  function TrackAnalyzer:_note_to_string(note)
    local str = ""

    for line_idx, line in ipairs(note.lines) do
      for ncol_idx, ncol in ipairs(line.note_columns) do
        str = str .. ncol.note_string .. ncol.instrument_string

        if self.track.volume_column_visible then
          str = str .. ncol.volume_string
        end
        if self.track.panning_column_visible then
          str = str .. ncol.panning_string
        end
        if self.track.delay_column_visible then
          str = str .. ncol.delay_string
        end
        if self.track.sample_effects_column_visible then
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
  function TrackAnalyzer:_has_end(line, start_ncol_idx, end_ncol_idx)
    for i = start_ncol_idx, end_ncol_idx do
      -- not empty
      if line:note_column(i).note_value ~= 121 then
        return true
      end
    end
    return false
  end

  -- Does the line have a note start(not OFF nor empty)?
  function TrackAnalyzer:_has_start(line, start_ncol_idx, end_ncol_idx)
    for i = start_ncol_idx, end_ncol_idx do
      -- not OFF nor empty
      if line:note_column(i).note_value < 120 then
        return true
      end
    end
    return false
  end

  -- Does the line have a note cut(Cx command on volume or panning column)?
  function TrackAnalyzer:_has_cut(noteline)
    for ncol_idx, ncol in ipairs(noteline.note_columns) do
      if (self.track.volume_column_visible and
        bit.band(ncol.volume_value, 0xff00) == 0x0c00) or
        (self.track.panning_column_visible and
        bit.band(ncol.panning_value, 0xff00) == 0x0c00) then
        
        return true
      end
    end
    return false
  end
