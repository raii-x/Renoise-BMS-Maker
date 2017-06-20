require "analyze"
require "automation"
require "render"
require "bmse"


--------------------------------------------------------------------------------
-- Variables

local dialog = nil

-- Range

local RANGE_MODE_ENTIRE_SONG = 1
local RANGE_MODE_SELECTION_SEQUENCE = 2
local RANGE_MODE_SELECTION_PATTERN = 3
local RANGE_MODE_CUSTOM = 4
local RANGE_MODE_ITEMS = {
  "Entire Song",
  "Selection in Sequence",
  "Selection in Pattern",
  "Custom",
}
local range_mode = RANGE_MODE_ENTIRE_SONG

local range_start_pos = renoise.SongPos()
local range_end_pos = renoise.SongPos()
range_start_pos.sequence = 1
range_start_pos.line = 1
range_end_pos.sequence = 1
range_end_pos.line = 1

-- Note Options

local has_duration = true
local release_lines = 1
local chord_mode = false

-- File Options

local directory = ""
local filename = ""
local file_start_index = 0

-- Priority

local RENDER_PRIORITY_LOW = 1
local RENDER_PRIORITY_HIGH = 2
local RENDER_PRIORITY_ITEMS = {
  "Low", "High"
}
local RENDER_PRIORITY_VALUE = {
  "low", "high"
}
local render_priority = RENDER_PRIORITY_HIGH

-- Interpolation

local RENDER_INTERPOLATION_DEFAULT = 1
local RENDER_INTERPOLATION_PRECISE = 2
local RENDER_INTERPOLATION_ITEMS = {
  "Default", "Precise"
}
local RENDER_INTERPOLATION_VALUE = {
  "default", "precise"
}
local render_interpolation = RENDER_INTERPOLATION_DEFAULT

-- Sample rate

local RENDER_SAMPLE_RATE_22050 = 1
local RENDER_SAMPLE_RATE_44100 = 2
local RENDER_SAMPLE_RATE_48000 = 3
local RENDER_SAMPLE_RATE_88200 = 4
local RENDER_SAMPLE_RATE_96000 = 5
local RENDER_SAMPLE_RATE_ITEMS = {
  "22050 Hz", "44100 Hz", "48000 Hz",
  "88200 Hz", "96000 Hz"
}
local RENDER_SAMPLE_RATE_VALUE = {
  22050, 44100, 48000, 88200, 96000
}
local render_sample_rate = RENDER_SAMPLE_RATE_44100

-- Bit depth

local RENDER_BIT_DEPTH_16 = 1
local RENDER_BIT_DEPTH_24 = 2
local RENDER_BIT_DEPTH_32 = 3
local RENDER_BIT_DEPTH_ITEMS = {
  "16 Bit", "24 Bit", "32 Bit"
}
local RENDER_BIT_DEPTH_VALUE = {
  16, 24, 32
}
local render_bit_depth = RENDER_BIT_DEPTH_16


--------------------------------------------------------------------------------
-- Menu Entry : Make BMS

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Make BMS...",
  invoke = function()
    make_bms_gui()
    --export_to_bmse()
  end
}


function get_filename(file_opts, index)
  return ("%s_%03d.wav"):format(
    file_opts.name, file_opts.start_index + index
  )
end


-- Returns the start position and the end position
-- Returns nil when it couldn't get the range
local function get_range()
  local pat_seq = renoise.song().sequencer.pattern_sequence
  local s_pos = renoise.SongPos()
  local e_pos = renoise.SongPos()
  
  if range_mode == RANGE_MODE_ENTIRE_SONG then
    s_pos.sequence = 1
    s_pos.line = 1
    e_pos.sequence = #pat_seq
    local end_pat_idx = pat_seq[e_pos.sequence]
    e_pos.line = renoise.song():pattern(end_pat_idx).number_of_lines
    
  elseif range_mode == RANGE_MODE_SELECTION_SEQUENCE then
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
    
  elseif range_mode == RANGE_MODE_SELECTION_PATTERN then
    error("not implemented")
  elseif range_mode == RANGE_MODE_SELECTION_CUSTOM then
    error("not implemented")
  end
  
  return s_pos, e_pos
end


--------------------------------------------------------------------------------
-- make_bms

function make_bms(export_only)
  
  local track_index = renoise.song().selected_track_index
  local start_pos, end_pos = get_range()

  if start_pos == nil then
    return
  end

  local note_opts = {
    duration = has_duration,
    release_lines = release_lines,
    chord_mode = chord_mode,
  }
  local file_opts = {
    directory = directory,
    name = filename,
    start_index = file_start_index,
  }
  local render_opts = {
    sample_rate = RENDER_SAMPLE_RATE_VALUE[render_sample_rate],
    bit_depth = RENDER_BIT_DEPTH_VALUE[render_bit_depth],
    interpolation = RENDER_INTERPOLATION_VALUE[render_interpolation],
    priority = RENDER_PRIORITY_VALUE[render_priority],
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
  
  local bms_data = analyze(track_index, note_opts, start_pos, end_pos)
  
  if export_only then
    export_to_bmse(file_opts, bms_data)
  else
    start_rendering(track_index, note_opts, file_opts, render_opts, bms_data,
      function()
        export_to_bmse(file_opts, bms_data)
      end
    )
  end
  
end


--------------------------------------------------------------------------------
-- make_bms_gui

function make_bms_gui()

  if dialog and dialog.visible then
    dialog:show()
    return
  end

  -- ViewBuilder
  local vb = renoise.ViewBuilder()
  
  -- Size
  local OPTION_TEXT_WIDTH = 80
  
  -- tostring/tonumber for lua array index
  local function index_tos(value)
    return tostring(value-1)
  end
  local function index_ton(str)
    return tonumber(str)+1
  end
  
  -- Group in GUI
  local function gui_group(title, content)
    return vb:column {
      margin = 4,
      style = "group",
      width = 200,
      
      vb:text {
        text = title,
        font = "bold",
        width = 192,
        align = "center",
      },
      
      content
    } 
  end
  
  -- Option in GUI
  local function gui_option(label, items, default, notifier)
    return vb:row {
      vb:text {
        width = OPTION_TEXT_WIDTH,
        text = label
      },
      
      vb:popup {
        items = items,
        value = default,
        notifier = notifier
      }
    }
  end
  
  -- GUI
  local dialog_content = vb:column {
    margin = 4,
    spacing = 4,
    
    gui_group("Range",
    
      vb:column {
        vb:chooser {
          items = RANGE_MODE_ITEMS,
          value = range_mode,
          notifier = function(index)
            range_mode = index
            if index == RANGE_MODE_CUSTOM then
              vb.views.range_custom.visible = true
            else
              vb.views.range_custom.visible = false
            end
          end
        },
        
        vb:column {
          id = "range_custom",
          visible = range_mode == RANGE_MODE_CUSTOM
            and true or false,
          
          vb:row {
            vb:space {
              width = 40
            },
            vb:text {
              width = 60,
              align = "center",
              text = "Sequence"
            },
            vb:text {
              width = 60,
              align = "center",
              text = "Line"
            }
          },
          
          vb:row {
            vb:text {
              width = 40,
              text = "From"
            },
            vb:valuebox {
              min = 1,
              max = 1000,
              value = range_start_pos.sequence,
              tostring = index_tos,
              tonumber = index_ton,
              notifier = function(value)
                range_start_pos.sequence = value
              end
            },
            vb:valuebox {
              min = 1,
              max = renoise.Pattern.MAX_NUMBER_OF_LINES,
              value = range_start_pos.line,
              tostring = index_tos,
              tonumber = index_ton,
              notifier = function(value)
                range_start_pos.line = value
              end
            },
          },
          
          vb:row {
            vb:text {
              width = 40,
              text = "To"
            },
            vb:valuebox {
              min = 1,
              max = 1000,
              value = range_end_pos.sequence,
              tostring = index_tos,
              tonumber = index_ton,
              notifier = function(value)
                range_end_pos.sequence = value
              end
            },
            vb:valuebox {
              min = 1,
              max = renoise.Pattern.MAX_NUMBER_OF_LINES,
              value = range_end_pos.line,
              tostring = index_tos,
              tonumber = index_ton,
              notifier = function(value)
                range_end_pos.line = value
              end
            },
          },
        },
      }
      
    ),
    
    gui_group("Note Options",
    
      vb:column {
        vb:row {
          vb:text {
            width = OPTION_TEXT_WIDTH,
            text = "Has duration"
          },
          vb:checkbox {
            value = has_duration,
            notifier = function(value)
              has_duration = value
            end
          },
        },
        
        vb:row {
          vb:text {
            width = OPTION_TEXT_WIDTH,
            text = "Release lines"
          },
          vb:valuebox {
            min = 0,
            max = 512,
            value = release_lines,
            notifier = function(value)
              release_lines = value
            end
          },
        },
        
        vb:row {
          vb:text {
            width = OPTION_TEXT_WIDTH,
            text = "Chord mode"
          },
          vb:checkbox {
            value = chord_mode,
            notifier = function(value)
              chord_mode = value
            end
          },
        },
      }
      
    ),
    
    gui_group("File options",
    
      vb:column {
        vb:row {
          vb:button {
            text = "Browse",
            notifier = function()
              local path = renoise.app():prompt_for_path(
                "Please choose a destination directory")
              if path ~= "" then
                vb.views.directory.value = path
              end
            end,
          },
          vb:textfield {
            id = "directory",
            width = 140,
            value = directory,
            notifier = function(value)
              directory = value
            end
          }
        },
        
        vb:row {
          vb:textfield {
            id = "filename",
            width = 80,
            value = filename,
            notifier = function(value)
              filename = value
            end,
          },
          vb:text {
            text = "_***.wav"
          }
        },
        
        vb:row {
          vb:text {
            width = OPTION_TEXT_WIDTH,
            text = "Start number"
          },
          
          vb:valuebox {
            min = 0,
            max = 999,
            value = file_start_index,
            tostring = function(value)
              return ("%03d"):format(value)
            end,
            tonumber = function(str)
              return tonumber(str)
            end,
            notifier = function(value)
              file_start_index = value
            end
          }
        }
      }
      
    ),
    
    gui_group("Render Options",
    
      vb:column {
        gui_option("Priority", 
          RENDER_PRIORITY_ITEMS, render_priority,
          function(value)
            render_priority = value
          end
        ),
        gui_option("Interpolation", 
          RENDER_INTERPOLATION_ITEMS, render_interpolation,
          function(value)
            render_interpolation = value
          end
        ),
        gui_option("Sample rate", 
          RENDER_SAMPLE_RATE_ITEMS, render_sample_rate,
          function(value)
            render_sample_rate = value
          end
        ),
        gui_option("Bit depth", 
          RENDER_BIT_DEPTH_ITEMS, render_bit_depth,
          function(value)
            render_bit_depth = value
          end
        ),
      }
    
    ),
    
    vb:row {
      vb:button {
        width = 50,
        height = 35,
        text = "Make",
        notifier = function()
          make_bms(false)
        end
      },
      
      vb:button {
        width = 50,
        height = 35,
        text = "Export\nonly",
        notifier = function()
          make_bms(true)
        end
      },
    }
    
  }
  
  dialog = renoise.app():show_custom_dialog(
    "BMS Maker", dialog_content)
end

