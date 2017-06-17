-- search_automated_params(trk)
-- flatten_points(pat_seq, trk_idx, prm)
-- slice_points(points, start_pt_idx, s_time, e_time)


-- The returned params may contain command controled param
function search_automated_params(trk)
  local t = table.create()
  
  for dev_idx, dev in ipairs(trk.devices) do
    for prm_idx, prm in ipairs(dev.parameters) do
      if prm.is_automated then
        t:insert(prm)
      end
    end
  end
  return t
end


-- If there's no point, return nil.
local function get_first_value(pat_seq, trk_idx, prm)
  for seq_idx, pat_idx in ipairs(pat_seq) do
    local pattrk = renoise.song():pattern(pat_idx):track(trk_idx)
    
    local auto = pattrk:find_automation(prm)
    if auto then
      return auto.points[1].value
    end
  end
  return nil
end


local function add_point(table, point)
  -- Same value 3 points -> 2 points
  if #table >= 2 then
    if table[#table].value == point.value and
      table[#table-1].value == point.value then
      
      table[#table].time = point.time
      return
    end
  end
  
  table:insert(point)
end


function flatten_points(pat_seq, trk_idx, prm)
  local fpts = table.create()
  
  -- Iterate sequences
  local seq_time = 0
  for seq_idx, pat_idx in ipairs(pat_seq) do
    local pat = renoise.song():pattern(pat_idx)
    local pattrk = pat:track(trk_idx)
    
    local nlines = pat.number_of_lines
    local end_time = nlines + 1 - prm.time_quantum
    
    local auto = pattrk:find_automation(prm)
    -- With automation
    if auto then
      local pts = auto.points
      
      if auto.playmode ~= renoise.PatternTrackAutomation.PLAYMODE_LINEAR then
        error("Supported only linear interpolation.")
      end
      
      -- If there's no point at the head, add point there
      if not auto:has_point_at(1) then
        add_point(fpts, {
          time = seq_time + 1,
          value = pts[1].value
        })
      end
      
      -- Flatten points
      for pt_idx, pt in ipairs(auto.points) do
        pt.time = pt.time + seq_time
        add_point(fpts, pt)
      end
      
      -- If there's no point at the end, add point there
      if not auto:has_point_at(end_time) then
        add_point(fpts, {
          time = seq_time + end_time,
          value = pts[#pts].value
        })
      end
      
    -- Without automation
    else
      if seq_idx == 1 then
        local val = get_first_value(pat_seq, trk_idx, prm)
        -- If there's no automation, return nil
        if not val then
          return nil
        end
        -- Add point at the head
        add_point(fpts, {
          time = 1,
          value = val
        })
      end
      
      -- Add point at the end
      add_point(fpts, {
        time = seq_time + end_time,
        value = fpts[#fpts].value
      })
    end
    
    seq_time = seq_time + nlines
  end
  
  -- Same value 2 points at the end -> 1 point
  if #fpts >= 2 then
    if fpts[#fpts].value == fpts[#fpts-1].value then
      fpts:remove()
    end
  end
  
  return fpts
end


local function interpolate_points(pt1, pt2, time)
  return pt1.value + (time - pt1.time) *
    ((pt2.value - pt1.value) / (pt2.time - pt1.time))
end


function slice_points(points, start_pt_idx, s_time, e_time)
  -- Decide start point (Update start_pt_idx)
  for pt_idx = start_pt_idx, #points do
    local pt = points[pt_idx]
    
    if pt.time > s_time then
      -- (start point).time can equal to s_time
      start_pt_idx = pt_idx - 1
      break
    -- The last point
    elseif pt_idx == #points then
      start_pt_idx = pt_idx
      break
    end
  end
  
  local slice = table.create()

  -- Slice
  -- Before time range
  if start_pt_idx == #points then
    slice:insert {
      time = 1,
      value = points[start_pt_idx].value
    }
    
  else
    -- The first point (Before time range)
    slice:insert {
      time = 1,
      value = interpolate_points(
        points[start_pt_idx], points[start_pt_idx+1], s_time)
    }
    
    for pt_idx = start_pt_idx+1, #points do
      local pt = points[pt_idx]
      
      -- After time range
      if pt.time >= e_time then
        local val = interpolate_points(points[pt_idx-1], pt, e_time)
        if val ~= slice[#slice].value then
          slice:insert {
            time = 1 + (e_time - s_time),
            value = val
          }
        end
        break
        
      -- In time range
      else
        slice:insert {
          time = 1 + (pt.time - s_time),
          value = pt.value
        }
      end
    end
  end
  
  return slice, start_pt_idx
end


--------------------------------------------------------------------------------
-- For debug

if false then
  local trk = renoise.song().selected_track
  local trk_idx = renoise.song().selected_track_index
  local pat_seq = renoise.song().sequencer.pattern_sequence
  
  local auto_prms = search_automated_params(trk)
  local auto_pts = table.create()
  
  for prm_idx, prm in ipairs(auto_prms) do
    auto_pts[prm_idx] = flatten_points(pat_seq, trk_idx, prm)
  end
  
  for i, v in ipairs(auto_pts[1]) do
    print(v.time, v.value)
  end
  
  print("----------")
  
  local slice = slice_points(auto_pts[1], 1, 97, 161)
  for i, v in ipairs(slice) do
    print(v.time, v.value)
  end
  
  print("----------")
end
