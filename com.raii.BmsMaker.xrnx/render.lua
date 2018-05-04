function start_rendering(track_index, note_opts, file_opts, render_opts,
  bms_data, on_end_rendering)
  
  local overwrite_all = false
  
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
  
    if not overwrite_all and
      io.exists(
        file_opts.directory .. get_filename(file_opts, note_index-1)
      ) then
      
      local pressed = renoise.app():show_prompt(
        "Make BMS",
        "Overwrite '" .. get_filename(file_opts, note_index-1) .. "'?",
        {"Overwrite", "Overwrite all", "Cancel"}
      )
      if pressed == "Cancel" then
        end_rendering()
        return
      elseif pressed == "Overwrite all" then
        overwrite_all = true
      end
    end
    
    renoise.app():show_status(
      "Rendering '" .. get_filename(file_opts, note_index-1) .. "'."
    )
    
    local note = bms_data.notes[note_index]
    local s_pos = renoise.SongPos()
    local e_pos = renoise.SongPos()
    local line_num = note_opts.release_lines
    if note_opts.duration then
      line_num = line_num + #note.lines
    end
    
    working_pattern:clear()
    local pattrk = working_pattern:track(track_index)
    
    -- Write note
    for line_idx, line in ipairs(note.lines) do
      for ncol_idx, ncol in ipairs(line.note_columns) do
        pattrk:line(line_idx):note_column(ncol_idx):copy_from(ncol)
      end
      for ecol_idx, ecol in ipairs(line.effect_columns) do
        pattrk:line(line_idx):effect_column(ecol_idx):copy_from(ecol)
      end
    end
    
    if note_opts.duration then
      -- Write note off
      for i = 1, #note.lines[1].note_columns do
        pattrk:line(#note.lines + 1):note_column(i).note_value = 120
      end
    end
    
    -- Write automation
    if note_opts.duration then
      line_num = #note.lines + note_opts.release_lines
    else
      line_num = note_opts.release_lines
    end
    
    for prm_idx, prm in ipairs(bms_data.automated_params) do
      local auto = pattrk:create_automation(prm)
      auto.points = note.automation[prm_idx]
    end
    
    s_pos.sequence = 1
    s_pos.line = 1
    e_pos.sequence = 1
    e_pos.line = line_num
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
        priority =render_opts.priority
      },
      file_opts.directory .. get_filename(file_opts, note_index-1),
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

