local function output(bms_data, start_number, filepath)
  local str = "BMSE ClipBoard Object Data Format\n"
  for i, v in ipairs(bms_data.order) do
    str = str .. ("%d%08d%d\n"):format(101 + (v.column - 1), v.pos, v.note.number + start_number)
  end
  
  local file = io.open(filepath, "w")
  file:write(str)
  file:close()
end

--------------------------------------------------------------------------------
-- export_to_bmse

function export_to_bmse(file_opts, bms_data)

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
        value = "bmse_clipboard.txt",
      },
    },
    
    vb:row {
      vb:text {
        width = OPTION_TEXT_WIDTH,
        text = "Start number"
      },
      
      vb:valuebox {
        id = "start_number",
        min = 0,
        max = 1295,
        value = 1,
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
            n = n + (c[i] <= 57 and c[i] - 48 or 10 + (c[i] - 65)) * 36 ^ (2-i)
          end
          return n
        end,
      },
    },
    
    vb:button {
      text = "Export",
      notifier = function()
        local filename = vb.views.filename.value
        local filepath = file_opts.directory .. filename
        output(bms_data, vb.views.start_number.value, filepath)
        renoise.app():show_prompt(
          "Make BMS",
          ("Exported to '%s'."):format(filename),
          {"OK"}
        )
      end
    },
    
  }
  
  renoise.app():show_custom_dialog(
    "BMSE Export", dialog_content)
end

