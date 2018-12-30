function start_rendering(note_opts, file_opts, render_opts,
  bms_data, on_end_rendering)
  
  -- Make new pattern
  local pat_idx = renoise.song().sequencer:insert_new_pattern_at(1)
  local working_pattern = renoise.song().patterns[pat_idx]
  working_pattern.number_of_lines = renoise.Pattern.MAX_NUMBER_OF_LINES
  
  -- Called on end
  local function end_rendering()
    renoise.song().sequencer:delete_sequence_at(1)
    renoise.app():show_status("Rendering completed.")
    on_end_rendering()
  end
  
  -- Render single note (Recursively called)
  local function render_note(note_index) 
  
    if note_index > #bms_data.notes then
      end_rendering()
      return
    end
  
    local filename = ("%s_%03d.wav"):format(note_opts.filename, note_index-1)

    renoise.app():show_status(
      "Rendering '" .. filename .. "'."
    )
    
    local note = bms_data.notes[note_index]
    
    working_pattern:clear()
    local pattrk = working_pattern:track(note_opts.index)
    
    -- Write note
    for line_idx, line in ipairs(note.lines) do
      for ncol_idx, ncol in ipairs(line.note_columns) do
        pattrk:line(line_idx):note_column(ncol_idx):copy_from(ncol)
      end
      for ecol_idx, ecol in ipairs(line.effect_columns) do
        pattrk:line(line_idx):effect_column(ecol_idx):copy_from(ecol)
      end
    end
    
    if not note_opts.one_shot and
      #note.lines + 1 <= renoise.Pattern.MAX_NUMBER_OF_LINES then
      -- Write note off
      for i = 1, #note.lines[1].note_columns do
        pattrk:line(#note.lines + 1):note_column(i).note_value = 120
      end
    end
    
    -- Write automation
    for prm_idx, prm in ipairs(bms_data.automated_params) do
      local auto = pattrk:create_automation(prm)
      auto.points = note.automation[prm_idx]
    end
    
    local line_num
    if note_opts.one_shot then
      line_num = note_opts.release_lines
    else
      line_num = #note.lines + note_opts.release_lines
    end
    
    local s_pos = renoise.SongPos(1, 1)
    local e_pos = renoise.SongPos(1, line_num)
    
    -- If s_pos == e_pos, render will be error.
    if e_pos.line <= 1 then
      e_pos.line = 2
    end
    
    -- Render
    local ret, msg = renoise.song():render(
      {
        start_pos = s_pos, end_pos = e_pos,
        sample_rate = render_opts.sample_rate,
        bit_depth = render_opts.bit_depth,
        interpolation = render_opts.interpolation,
        priority = render_opts.priority
      },
      file_opts.directory .. filename,
      function()
        -- render next sample
        render_note(note_index + 1)
      end
    )
    
    -- On error
    if not ret then
      renoise.app():show_error(msg)
      renoise.song().sequencer:delete_sequence_at(1)
    end
  end
  
  -- Render
  render_note(1)
  
end

