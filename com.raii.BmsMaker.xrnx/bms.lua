bms_start_number = 1


local function output(en_track_opts, bms_data, start_number, filepath)
  local bar_num = 0
  local lane_num = 0

  for i_trk, data in ipairs(bms_data) do
    for _, v in ipairs(data.order) do
      bar_num = math.max(bar_num, 1 + math.floor(v.pos / 192))
      lane_num = math.max(lane_num,
        en_track_opts[i_trk].bgm_lane + v.column - 1)
    end
  end

  local strs = table.create {
    "#TITLE Untitled",
    ("#BPM %d"):format(renoise.song().transport.bpm),
    "",
    "",
  }

  -- bars[bar][lane]
  local bars = table.create()
  for i = 1, bar_num do
    local t = table.create()
    for j = 1, lane_num do
      t:insert(table.create())
    end
    bars:insert(t)
  end

  local note_number = start_number

  for i_trk, data in ipairs(bms_data) do
    for _, v in ipairs(data.order) do
      local bar = 1 + math.floor(v.pos / 192)
      local lane = en_track_opts[i_trk].bgm_lane + v.column - 1
      bars[bar][lane]:insert {
        pos = v.pos % 192,
        number = note_number + v.note.number,
      }
    end

    for _, v in ipairs(data.notes) do
      -- Add wav header text
      strs:insert(("#WAV%s %s_%03d.wav"):format(
        tostring36(note_number + v.number), en_track_opts[i_trk].filename,
        v.number))
    end

    note_number = note_number + #data.notes
  end
  
  strs:insert("")
  strs:insert("")

  for i_bar, bar in ipairs(bars) do
    for i_lane, lane in ipairs(bar) do
      
      local t = table.create()
      for i = 1, 192 do
        t:insert("00")
      end

      for _, note in ipairs(lane) do
        t[1 + note.pos] = tostring36(note.number)
      end

      -- Add sequence text
      strs:insert(("#%03d01:%s"):format(i_bar - 1, t:concat()))
    end
  end

  strs:insert("")
  strs:insert("")
  strs:insert("")
  
  local file = io.open(filepath, "w")
  file:write(strs:concat("\n"))
  file:close()
end

--------------------------------------------------------------------------------
-- export_to_bms

function export_to_bms(file_opts, en_track_opts, bms_data)

  local vb = renoise.ViewBuilder()
  
  -- Size
  local OPTION_TEXT_WIDTH = 80
  
  local dialog_content = vb:column {
    margin = 4,
    
    vb:row {
      vb:text {
        width = OPTION_TEXT_WIDTH,
        text = "File name"
      },
      
      vb:textfield {
        width = 120,
        id = "filename",
        value = "_untitled.bms",
      },
    },
    
    vb:row {
      vb:text {
        width = OPTION_TEXT_WIDTH,
        text = "Start number"
      },
      
      vb:valuebox {
        id = "start_number",
        min = 1,
        max = 1295,
        value = bms_start_number,
        
        tostring = function(value)
          local n = table.create()
          local s = ""
          n[1] = math.floor(value / 36)
          n[2] = value % 36
          for i, v in ipairs(n) do
            s = s .. (v < 10 and tostring(v) or string.char(65 + (v-10)))
          end
          return s
        end,
        
        tonumber = function(str)
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
        end,
        
        notifier = function(value)
          bms_start_number = value
        end,
      },
    },
    
    vb:button {
      text = "Export",
      notifier = function()
        local filename = vb.views.filename.value
        local filepath = file_opts.directory .. filename
        output(en_track_opts, bms_data, vb.views.start_number.value, filepath)
        renoise.app():show_status(("Exported to '%s'."):format(filename))
      end
    },
    
  }
  
  renoise.app():show_custom_dialog(
    "BMS Export", dialog_content)
end

