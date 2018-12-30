require "util"
require "const"
require "analyze"
require "automation"
require "render"
require "bms"
require "gui"


--------------------------------------------------------------------------------
-- Menu Entry : Make BMS

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Make BMS...",
  invoke = function()
    make_bms_gui()
  end
}


-- Returns the start position and the end position
-- Returns nil when it couldn't get the range
local function get_range(range_opts)
  local pat_seq = renoise.song().sequencer.pattern_sequence
  local s_pos = renoise.SongPos()
  local e_pos = renoise.SongPos()
  
  if range_opts.mode == RANGE_MODE_ENTIRE_SONG then
    s_pos.sequence = 1
    s_pos.line = 1
    e_pos.sequence = #pat_seq
    local end_pat_idx = pat_seq[e_pos.sequence]
    e_pos.line = renoise.song():pattern(end_pat_idx).number_of_lines
    
  elseif range_opts.mode == RANGE_MODE_SELECTION_SEQUENCE then
    local range = renoise.song().sequencer.selection_range
    -- No range is selected
    if range[1] == 0 then
      renoise.app():show_error("Please select a range.")
      return nil
    end

    s_pos.sequence = range[1]
    s_pos.line = 1
    e_pos.sequence = range[2]
    local end_pat_idx = pat_seq[e_pos.sequence]
    e_pos.line = renoise.song():pattern(end_pat_idx).number_of_lines
    
  elseif range_opts.mode == RANGE_MODE_SELECTION_PATTERN then
    local seq_idx = renoise.song().selected_sequence_index
    local range = renoise.song().selection_in_pattern
    -- No range is selected
    if range == nil then
      renoise.app():show_error("Please select a range.")
      return nil
    end
    
    s_pos.sequence = seq_idx
    s_pos.line = range.start_line
    e_pos.sequence = seq_idx
    e_pos.line = range.end_line
    
  elseif range_opts.mode == RANGE_MODE_CUSTOM then
    if range_opts.start_pos.sequence > #pat_seq or
      range_opts.end_pos.sequence > #pat_seq or
      range_opts.start_pos.line >
        renoise.song():pattern(range_opts.start_pos.sequence).number_of_lines or
      range_opts.end_pos.line >
        renoise.song():pattern(range_opts.end_pos.sequence).number_of_lines then
      
      renoise.app():show_error("The range position doesn't exist.")
      return nil
    end
    if range_opts.start_pos > range_opts.end_pos then
      renoise.app():show_error(
        "The range start position must be before the end position."
      )
      return nil
    end
    
    s_pos.sequence = range_opts.start_pos.sequence
    s_pos.line = range_opts.start_pos.line
    e_pos.sequence = range_opts.end_pos.sequence
    e_pos.line = range_opts.end_pos.line
    
  end
  
  return s_pos, e_pos
end


--------------------------------------------------------------------------------
-- make_bms

function make_bms(export_only, range_opts, file_opts, render_opts_gui,
  track_opts)
  
  local start_pos, end_pos = get_range(range_opts)

  if start_pos == nil then
    return
  end

  local render_opts = {
    sample_rate = RENDER_SAMPLE_RATE_VALUE[render_opts_gui.sample_rate],
    bit_depth = RENDER_BIT_DEPTH_VALUE[render_opts_gui.bit_depth],
    interpolation = RENDER_INTERPOLATION_VALUE[render_opts_gui.interpolation],
    priority = RENDER_PRIORITY_VALUE[render_opts_gui.priority],
  }
  
  -- Existence check
  if not io.exists(file_opts.directory) or
    io.stat(file_opts.directory).type ~= "directory" then
    
    renoise.app():show_error("The directory doesn't exist.")
    return
  end
  
  -- Add '\' to the end of directory
  local dir_lastchar = file_opts.directory:sub(-1)
  if dir_lastchar ~= [[\]] and dir_lastchar ~= [[/]] then
    file_opts.directory = file_opts.directory .. [[\]]
  end
  
  local enabled_track_opts = table.create()
  for _, opt in ipairs(track_opts) do
    if opt.enabled then
      enabled_track_opts:insert(opt)
    end
  end

  local bms_data = table.create()

  for i, note_opts in ipairs(enabled_track_opts) do
    bms_data:insert(analyze(note_opts, start_pos, end_pos))
  
    if bms_data[i] == nil then
      return
    end
  end
  
  if export_only then
    export_to_bms(file_opts, enabled_track_opts, bms_data)
  else
    local function get_render_func(i)
      return function()
        if i > #enabled_track_opts then

          export_to_bms(file_opts, enabled_track_opts, bms_data)
        else
          start_rendering(enabled_track_opts[i], file_opts, render_opts,
            bms_data[i], get_render_func(i + 1))
        end
      end
    end

    get_render_func(1)()
  end
  
end



