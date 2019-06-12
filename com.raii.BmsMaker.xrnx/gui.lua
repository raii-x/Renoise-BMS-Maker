-- GUI variables

local dialog = nil
local vb = nil
local track_rows
local track_options_page = 1

-- Options

local range_options = {
  mode = RANGE_MODE_ENTIRE_SONG,
  start_pos = renoise.SongPos(1, 1),
  end_pos = renoise.SongPos(1, 1),
}

local file_options = {
  directory = ""
}

local render_options = {
  priority = RENDER_PRIORITY_HIGH,
  interpolation = RENDER_INTERPOLATION_DEFAULT,
  sample_rate = RENDER_SAMPLE_RATE_44100,
  bit_depth = RENDER_BIT_DEPTH_16,
}

local track_options = table.create()

local track_option_default = table.create {
  index = 1,
  enabled = true,
  filename = "",
  one_shot = false,
  release_lines = 1,
  chord_mode = false,
  bgm_lane = 1,
}

-- Size constants

local OPTION_TEXT_WIDTH = 80
local ENABLED_WIDTH = 22
local TRACK_WIDTH = 90
local FILENAME_WIDTH = 80
local SPACE_WIDTH = 5
local CHECKBOX_WIDTH = 40
local VALUEBOX_WIDTH = 65

local TRACK_ROWS_NUM = 30


-- Group in GUI
local function gui_group(title, content)
  return vb:column {
    margin = 4,
    style = "group",
    width = 200,
    
    vb:horizontal_aligner {
      mode = "center",
      vb:text {
        text = title,
        font = "bold",
        width = 192,
        align = "center",
      },
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

local function row_to_track(i)
  return (track_options_page - 1) * TRACK_ROWS_NUM + i
end

-- Get only sequencer track indices
local function get_seq_track_indices()
  local t = table.create()
  for i, trk in ipairs(renoise.song().tracks) do
    if trk.type == renoise.Track.TRACK_TYPE_SEQUENCER then
      t:insert(i)
    end
  end
  return t
end

local function refresh_track_options()
  local tracks = renoise.song().tracks
  
  local track_indices = get_seq_track_indices()

  -- Delete unnecessary track options
  for i = #track_indices + 1, #track_options do
    track_options:remove()
  end

  -- Refresh indices
  for i = 1, #track_options do
    track_options[i].index = track_indices[i]
  end

  -- Add new track options
  for i = #track_options + 1, #track_indices do
    local opt = track_option_default:copy()
    opt.index = track_indices[i]
    opt.filename = tracks[opt.index].name
    track_options:insert(opt)
  end
end

local function refresh_track_options_gui()
  refresh_track_options()

  local max_page = math.floor((#track_options - 1) / TRACK_ROWS_NUM) + 1
  
  -- Limit page number
  if track_options_page > max_page then
    track_options_page = max_page
  end

  -- Refresh GUI
  local start_index = (track_options_page - 1) * TRACK_ROWS_NUM + 1
  local end_index = math.min(start_index + TRACK_ROWS_NUM - 1, #track_options)
  local n = end_index - start_index + 1

  for i = 1, n do
    local i_track = start_index - 1 + i
    track_rows[i].row.visible = true
    track_rows[i].enabled.value = track_options[i_track].enabled
    local trk = renoise.song():track(track_options[i_track].index)
    -- Make invisible to prevent resize with long text
    track_rows[i].track.visible = false
    track_rows[i].track.text = ("%02d: %s"):format(
      track_options[i_track].index, trk.name)
    track_rows[i].track.width = TRACK_WIDTH
    track_rows[i].track.visible = true
    track_rows[i].filename.value = track_options[i_track].filename
    track_rows[i].one_shot.value = track_options[i_track].one_shot
    track_rows[i].release.value = track_options[i_track].release_lines
    track_rows[i].chord.value = track_options[i_track].chord_mode
    track_rows[i].bgm_lane.value = track_options[i_track].bgm_lane
  end

  for i = n + 1, TRACK_ROWS_NUM do
    track_rows[i].row.visible = false
  end

  -- Page navigator
  if max_page > 1 then
    vb.views.track_options_navigator.visible = true
    vb.views.track_options_prev.active = track_options_page > 1
    vb.views.track_options_next.active = track_options_page < max_page
  else
    vb.views.track_options_navigator.visible = false
  end
end

local function auto_bgm_lane()
  refresh_track_options()

  local tracks = renoise.song().tracks

  local i = 1
  for _, opt in ipairs(track_options) do
    if opt.enabled then
      opt.bgm_lane = i
      if opt.chord_mode then
        i = i + 1
      else
        i = i + tracks[opt.index].visible_note_columns
      end
    end
  end

  refresh_track_options_gui()
end

local function group_range()
  return gui_group("Range",

    vb:column {
      vb:chooser {
        items = RANGE_MODE_ITEMS,
        value = range_options.mode,
        notifier = function(index)
          range_options.mode = index
          if index == RANGE_MODE_CUSTOM then
            vb.views.range_custom.visible = true
          else
            vb.views.range_custom.visible = false
          end
        end
      },
      
      vb:column {
        id = "range_custom",
        visible = range_options.mode == RANGE_MODE_CUSTOM
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
            value = range_options.start_pos.sequence,
            tostring = index_tostring,
            tonumber = index_tonumber,
            notifier = function(value)
              range_options.start_pos.sequence = value
            end
          },
          vb:valuebox {
            min = 1,
            max = renoise.Pattern.MAX_NUMBER_OF_LINES,
            value = range_options.start_pos.line,
            tostring = index_tostring,
            tonumber = index_tonumber,
            notifier = function(value)
              range_options.start_pos.line = value
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
            value = range_options.end_pos.sequence,
            tostring = index_tostring,
            tonumber = index_tonumber,
            notifier = function(value)
              range_options.end_pos.sequence = value
            end
          },
          vb:valuebox {
            min = 1,
            max = renoise.Pattern.MAX_NUMBER_OF_LINES,
            value = range_options.end_pos.line,
            tostring = index_tostring,
            tonumber = index_tonumber,
            notifier = function(value)
              range_options.end_pos.line = value
            end
          },
        },
      },
    }
    
  )
end

local function group_file_options()
  return gui_group("Destination",

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
          value = file_options.directory,
          notifier = function(value)
            file_options.directory = value
          end
        }
      },
      --[[vb:row {
        vb:text {
          width = OPTION_TEXT_WIDTH,
          text = "BMS filename",
        },
        vb:textfield {
          width = 100,
          value = bms_filename,
          notifier = function(value)
            bms_filename = value
          end
        },
      },
      vb:row {
        vb:text {
          width = OPTION_TEXT_WIDTH,
          text = "Start number",
        },
        vb:valuebox {
          min = 1,
          max = 36 * 36 - 1,
          value = start_number,
          tostring = tostring36,
          tonumber = tonumber36,
          notifier = function(value)
            start_number = value
          end
        },
      },]]
    }
    
  )
end

local function group_render_option()
  return gui_group("Render Options",
    
    vb:column {
      gui_option("Priority", 
        RENDER_PRIORITY_ITEMS, render_options.priority,
        function(value)
          render_options.priority = value
        end
      ),
      gui_option("Interpolation", 
        RENDER_INTERPOLATION_ITEMS, render_options.interpolation,
        function(value)
          render_options.interpolation = value
        end
      ),
      gui_option("Sample rate", 
        RENDER_SAMPLE_RATE_ITEMS, render_options.sample_rate,
        function(value)
          render_options.sample_rate = value
        end
      ),
      gui_option("Bit depth", 
        RENDER_BIT_DEPTH_ITEMS, render_options.render_bit_depth,
        function(value)
          render_options.render_bit_depth = value
        end
      ),
    }

  )
end

local function make_buttons()
  return vb:horizontal_aligner {
    mode = "right",

    vb:button {
      width = 50,
      height = 35,
      text = "Make",
      notifier = function()
        refresh_track_options_gui()
        make_bms(false, range_options, file_options, render_options,
          track_options)
      end
    },
    
    vb:button {
      width = 50,
      height = 35,
      text = "Export\nonly",
      notifier = function()
        refresh_track_options_gui()
        make_bms(true, range_options, file_options, render_options,
          track_options)
      end
    },
  }
end

local function group_track_options()
  track_rows = table.create()
  -- { row, enabled, track, filename, one_shot, release, chord }

  -- Changing checkbox values call notifiers,
  -- so use this variable to know whether clicked or changed from scripts.
  local enabled_all_change = false

  local column_track_options = vb:column {

    vb:horizontal_aligner {
      mode = "right",
      vb:button {
        text = "Init",
        notifier = function()
          track_options:clear()
          refresh_track_options_gui()
        end,
      },
      vb:button {
        text = "Auto BGM Lane",
        notifier = function()
          auto_bgm_lane()
        end,
      },
      vb:button {
        text = "Refresh",
        notifier = function()
          refresh_track_options_gui()
        end,
      },
    },

    vb:row {
      vb:horizontal_aligner {
        width = ENABLED_WIDTH,
        vb:checkbox {
          id = "enabled_all",
          value = true,
          
          notifier = function(value)
            if enabled_all_change then return end

            for i = 1, #track_options do
              track_options[i].enabled = value
            end
            for i = 1, TRACK_ROWS_NUM do
              track_rows[i].enabled.value = value
            end
          end
        },
      },
      vb:text {
        width = TRACK_WIDTH,
        align = "center",
        font = "italic",
        text = "Track",
      },
      vb:space {
        width = SPACE_WIDTH,
      },
      vb:text {
        width = FILENAME_WIDTH,
        align = "center",
        font = "italic",
        text = "Filename",
      },
      vb:space {
        width = SPACE_WIDTH,
      },
      vb:text {
        width = CHECKBOX_WIDTH,
        align = "center",
        font = "italic",
        text = "1-Shot",
      },
      vb:text {
        width = VALUEBOX_WIDTH,
        align = "center",
        font = "italic",
        text = "Release",
      },
      vb:text {
        width = CHECKBOX_WIDTH,
        align = "center",
        font = "italic",
        text = "Chord",
      },
      vb:text {
        width = VALUEBOX_WIDTH,
        align = "center",
        font = "italic",
        text = "BGM Lane",
      },
    },
  }

  for i = 1, 30 do
    track_rows[i] = table.create()

    track_rows[i].enabled = vb:checkbox {
      notifier = function(value)
        local i_track = row_to_track(i)
        if i_track <= #track_options then
          track_options[i_track].enabled = value
        end

        local enabled_all = true
        for _, opt in ipairs(track_options) do
          if not opt.enabled then
            enabled_all = false
          end
        end

        enabled_all_change = true
        vb.views.enabled_all.value = enabled_all
        enabled_all_change = false
      end,
    }

    track_rows[i].track = vb:text {
      width = TRACK_WIDTH,
    }

    track_rows[i].filename = vb:textfield {
      width = FILENAME_WIDTH,
      notifier = function(value)
        track_options[row_to_track(i)].filename = value
      end,
    }

    track_rows[i].one_shot = vb:checkbox {
      notifier = function(value)
        track_options[row_to_track(i)].one_shot = value
      end,
    }

    track_rows[i].release = vb:valuebox {
      min = 0,
      max = renoise.Pattern.MAX_NUMBER_OF_LINES,
      notifier = function(value)
        track_options[row_to_track(i)].release_lines = value
      end
    }

    track_rows[i].chord = vb:checkbox {
      notifier = function(value)
        track_options[row_to_track(i)].chord_mode = value
      end
    }

    track_rows[i].bgm_lane = vb:valuebox {
      min = 1,
      max = 99,
      notifier = function(value)
        track_options[row_to_track(i)].bgm_lane = value
      end
    }

    track_rows[i].row = vb:row {
      visible = false,
      
      vb:horizontal_aligner {
        width = ENABLED_WIDTH,
        track_rows[i].enabled,
      },
      track_rows[i].track,
      vb:space {
        width = SPACE_WIDTH,
      },
      track_rows[i].filename,
      vb:space {
        width = SPACE_WIDTH,
      },
      vb:horizontal_aligner {
        width = CHECKBOX_WIDTH,
        mode = "center",
        track_rows[i].one_shot,
      },
      vb:horizontal_aligner {
        width = VALUEBOX_WIDTH,
        mode = "center",
        track_rows[i].release,
      },
      vb:horizontal_aligner {
        width = CHECKBOX_WIDTH,
        mode = "center",
        track_rows[i].chord,
      },
      vb:horizontal_aligner {
        width = VALUEBOX_WIDTH,
        mode = "center",
        track_rows[i].bgm_lane,
      },
    }

    column_track_options:add_child(track_rows[i].row)
  end

  column_track_options:add_child(
    vb:horizontal_aligner {
      id = "track_options_navigator",
      visible = false,
      mode = "center",
      vb:button {
        id = "track_options_prev",
        active = false,
        width = 60,
        text = "< Prev",
        notifier = function()
          track_options_page = track_options_page - 1
          refresh_track_options_gui()
        end,
      },
      vb:button {
        id = "track_options_next",
        active = false,
        width = 60,
        text = "Next >",
        notifier = function()
          track_options_page = track_options_page + 1
          refresh_track_options_gui()
        end,
      },
    }
  )
  
  return gui_group("Track Options", column_track_options)
end

local function gui()
  vb = renoise.ViewBuilder()

  local dialog_content = vb:row {
    margin = 4,
    spacing = 4,

    group_track_options(),

    vb:column {
      spacing = 4,

      group_range(),
      group_file_options(),
      group_render_option(),
      make_buttons(),
    },
  }

  refresh_track_options_gui()

  dialog = renoise.app():show_custom_dialog(
    "BMS Maker", dialog_content)
end

--------------------------------------------------------------------------------
-- make_bms_gui

function make_bms_gui()
  if dialog and dialog.visible then
    dialog:show()
    return
  end

  gui()
end
