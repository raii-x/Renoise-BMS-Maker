-- search_automated_params(search_trk_idx)
-- flatten_points(pat_seq, trk_idx, prm, linear)
-- slice_points(linear, points, start_pt_idx, s_time, e_time)

local function parent_table_part(tbl, par_idx, members)
  local idx = par_idx - 1
  
  while idx >= par_idx - members do
    local trk = renoise.song():track(idx)
    
    tbl[idx] = par_idx
    
    if trk.type == renoise.Track.TRACK_TYPE_GROUP then
      idx = parent_table_part(tbl, idx, #trk.members)
    else
      idx = idx - 1
    end
  end
  
  return idx
end

-- Make a table of track indices of group parents
-- The parent of top level tracks is the master track.
-- Index of the master track and send tracks is 0.
local function get_parent_table()
  local tbl = table.create()
  for i = 1, #renoise.song().tracks do
    tbl:insert(0)
  end
  
  local idx = #renoise.song().tracks
  
  for idx, trk in ripairs(renoise.song().tracks) do
    if trk.type == renoise.Track.TRACK_TYPE_MASTER then
      parent_table_part(tbl, idx, idx - 1)
      break
    end
  end
  
  return tbl
end

-- The returned params may contain command controled param
-- Returns array of { trk_idx, param }
function search_automated_params(search_trk_idx)
  local t = table.create()
  local parent_table = get_parent_table()
  
  for trk_idx, trk in ipairs(renoise.song().tracks) do
    if trk_idx == search_trk_idx then

      for dev_idx, dev in ipairs(trk.devices) do
        for prm_idx, prm in ipairs(dev.parameters) do
          if prm.is_automated then

            local linear = true
            local tag = nil

            if prm.value_quantum ~= 0 then
              linear = false
            end
            
            if trk.type == renoise.Track.TRACK_TYPE_MASTER and dev_idx == 1 then
              if prm_idx == 6 then
                linear = false
                tag = "BPM"
              elseif prm_idx == 7 then
                tag = "LPB"
              elseif prm_idx == 8 then
                tag = "TPL"
              end
            end
            
            t:insert {
              trk_idx = trk_idx,
              param = prm,
              linear = linear,
              tag = tag,
            }
          end
        end
      end
      
      search_trk_idx = parent_table[trk_idx]
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


local function add_point_quantum(table, point)
  -- Same value 2 points -> 1 point
  if #table >= 1 then
    if table[#table].value == point.value then
      return
    end
  end
  
  table:insert(point)
end


local function flatten_points_quantum(pat_seq, trk_idx, prm)
  local fpts = table.create()
  
  do
    local val = get_first_value(pat_seq, trk_idx, prm)
    -- If there's no automation, return nil
    if not val then
      return nil
    end
    -- Add first point at the head of song
    add_point_quantum(fpts, {
      time = 1,
      value = val
    })
  end

  -- If parameter is BPM, LPB, or TPL, Renoise changes value
  -- to first value of pattern automations on heads of each patterns.
  -- Otherwise Renoise keeps current value on heads of each patterns.
  -- If error, return false.
  local head_write = false
  if prm.name == "BPM" or prm.name == "LPB" or prm.name == "TPL" then
    head_write = true;
  end

  -- Iterate sequences
  local seq_time = 0
  for seq_idx, pat_idx in ipairs(pat_seq) do
    local pat = renoise.song():pattern(pat_idx)
    local pattrk = pat:track(trk_idx)
    
    local nlines = pat.number_of_lines
    
    local auto = pattrk:find_automation(prm)

    if auto then
      local pts = auto.points
      
      if auto.playmode ~= renoise.PatternTrackAutomation.PLAYMODE_POINTS then
        renoise.app():show_error(
          ("Track %02d: %s, Sequence %d: Interpolation mode needs to be \"Points\".")
          :format(trk_idx, renoise.song():track(trk_idx).name, seq_idx - 1))
        return false
      end
      
      if head_write then
        -- If there's no point at the head, add point there
        if not auto:has_point_at(1) then
          add_point_quantum(fpts, {
            time = seq_time + 1,
            value = pts[1].value
          })
        end        
      end

      -- Flatten points
      for pt_idx, pt in ipairs(auto.points) do
        pt.time = pt.time + seq_time
        add_point_quantum(fpts, pt)
      end
    end
    
    seq_time = seq_time + nlines
  end
  
  return fpts
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


-- If there's no automation, return nil.
-- If error, return false.
function flatten_points(pat_seq, trk_idx, prm, linear)
  if not linear then
    return flatten_points_quantum(pat_seq, trk_idx, prm)
  end

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
      
      if auto.playmode == renoise.PatternTrackAutomation.PLAYMODE_LINEAR then
      
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

      elseif auto.playmode == renoise.PatternTrackAutomation.PLAYMODE_POINTS then

        -- If there's no point at the head of song, add point there
        if seq_idx == 1 and not auto:has_point_at(1) then
          local val = get_first_value(pat_seq, trk_idx, prm)
          add_point(fpts, {
            time = 1,
            value = pts[1].value
          })
        end
      
        -- Flatten points
        for pt_idx, pt in ipairs(auto.points) do
          -- If it's not at the head and there's no point behind time_quantum, add point there
          if pt.time > 1 and not auto:has_point_at(pt.time - prm.time_quantum) and #fpts > 0 then
            add_point(fpts, {
              time = seq_time + pt.time - prm.time_quantum,
              value = fpts[#fpts].value
            })
          end

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

      else
        renoise.app():show_error(
          ("Track %02d: %s, Sequence %d: \"Curve\" interpolation mode isn't supported.")
          :format(trk_idx, renoise.song():track(trk_idx).name, seq_idx - 1))
        return false

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


local function get_first_slice_point(points, start_pt_idx, s_time)
  -- Search the necessary point to get the start value
  -- in the time range given by s_time and e_time (Update start_pt_idx)
  -- The search start from start_pt_idx
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

  return start_pt_idx
end


local function slice_points_quantum(points, start_pt_idx, s_time, e_time)
  start_pt_idx = get_first_slice_point(points, start_pt_idx, s_time)
  
  local slice = table.create()

  -- Slice
  slice:insert {
    time = 1,
    value = points[start_pt_idx].value
  }

  for pt_idx = start_pt_idx+1, #points do
    local pt = points[pt_idx]
    
    if pt.time > e_time then
      break
    end
      
    -- Get a value in the time range and make a point
    slice:insert {
      time = 1 + (pt.time - s_time),
      value = pt.value
    }
  end

  return slice, start_pt_idx
end


local function interpolate_points(pt1, pt2, time)
  return pt1.value + (time - pt1.time) *
    ((pt2.value - pt1.value) / (pt2.time - pt1.time))
end


-- s_time and e_time are inclusive
function slice_points(linear, points, start_pt_idx, s_time, e_time)
  if not linear then
    return slice_points_quantum(points, start_pt_idx, s_time, e_time)
  end

  start_pt_idx = get_first_slice_point(points, start_pt_idx, s_time)
  
  local slice = table.create()

  -- Slice
  -- When all points come before the time range
  -- or the last point comes on start of the time range
  -- or there's only one point
  if start_pt_idx == #points then
    slice:insert {
      time = 1,
      value = points[start_pt_idx].value
    }
    
  else
    -- Get the start value in the range and make the first point
    slice:insert {
      time = 1,
      value = interpolate_points(
        points[start_pt_idx], points[start_pt_idx+1], s_time)
    }
    
    for pt_idx = start_pt_idx+1, #points do
      local pt = points[pt_idx]
      
      -- Get the end value in the range and make the last point
      if pt.time >= e_time then
        local val = interpolate_points(points[pt_idx-1], pt, e_time)
        if val ~= slice[#slice].value then
          slice:insert {
            time = 1 + (e_time - s_time),
            value = val
          }
        end
        break
        
      -- Get a value in the time range and make a point
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
-- Test

if TEST then
  do
    local function remove_param(prms)
      for i, v in ipairs(prms) do
        prms[i] = v.trk_idx
      end
      return prms
    end

    setup_test(1)

    renoise.song():insert_track_at(2)
    renoise.song():insert_track_at(3)
    renoise.song():insert_group_at(4)
    renoise.song():add_track_to_group(2, 4)
    renoise.song():add_track_to_group(2, 4)
    renoise.song():insert_track_at(5)
    renoise.song():insert_group_at(6)
    renoise.song():add_track_to_group(4, 6)
    renoise.song():add_track_to_group(2, 6)

    local pat = renoise.song():pattern(1)
    for i = 1, 7 do
      local pattrk = pat:track(i)
      local prm = renoise.song():track(i):device(1):parameter(1)
      local auto = pattrk:create_automation(prm)
      auto:add_point_at(1, 0)
    end

    -- Group & master track automation test

    assert(table_eq_deep(
      remove_param(search_automated_params(1)),
      { 1, 7 }
    ))
    assert(table_eq_deep(
      remove_param(search_automated_params(2)),
      { 2, 4, 6, 7 }
    ))
    assert(table_eq_deep(
      remove_param(search_automated_params(3)),
      { 3, 4, 6, 7 }
    ))
    assert(table_eq_deep(
      remove_param(search_automated_params(5)),
      { 5, 6, 7 }
    ))
  end

  do
    setup_test(5)

    local pat_seq = renoise.song().sequencer.pattern_sequence

    local pattrk = {}
    for i = 1, 5 do
      pattrk[i] = renoise.song():pattern(i):track(1)
    end

    do
      local prm = renoise.song():track(1):device(1):parameter(1)

      local auto = {}
      auto[1] = pattrk[1]:create_automation(prm)
      auto[3] = pattrk[3]:create_automation(prm)
      auto[4] = pattrk[4]:create_automation(prm)
      auto[5] = pattrk[5]:create_automation(prm)

      auto[4].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS
      auto[5].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS

      auto[1]:add_point_at(3, 0)
      auto[1]:add_point_at(7, 1)
      auto[1]:add_point_at(11, 0.5)
      auto[3]:add_point_at(9, 1)
      auto[4]:add_point_at(1, 0)
      auto[4]:add_point_at(2.5, 0.5)
      auto[5]:add_point_at(5, 1)
      
      local env = flatten_points(pat_seq, 1, prm, true)

      -- Flatten test
      local q = prm.time_quantum
      assert(table_eq_deep(env, {
        { time = 1, value = 0 },
        { time = 3, value = 0 },
        { time = 7, value = 1 },
        { time = 11, value = 0.5 },
        { time = 129 - q, value = 0.5 },
        { time = 129, value = 1 },
        { time = 193 - q, value = 1 },
        { time = 193, value = 0 },
        { time = 194.5 - q, value = 0 },
        { time = 194.5, value = 0.5 },
        { time = 261 - q, value = 0.5 },
        { time = 261, value = 1 },
      }))

      -- Slice tests

      assert(table_eq_deep(
        slice_points(true, env, 1, 1, 2), {
          { time = 1, value = 0 },
        }))

      assert(table_eq_deep(
        slice_points(true, env, 1, 2, 4.5), {
          { time = 1, value = 0 },
          { time = 2, value = 0 },
          { time = 3.5, value = 0.375 },
        }))

      assert(table_eq_deep(
        slice_points(true, env, 1, 6, 12), {
          { time = 1, value = 0.75 },
          { time = 2, value = 1 },
          { time = 6, value = 0.5 },
        }))
      
      assert(table_eq_deep(
        slice_points(true, env, 1, 12, 13), {
          { time = 1, value = 0.5 },
        }))
    end

    do
      local prm = renoise.song():track(1):device(1):parameter(2)
      local auto = {}
      auto[1] = pattrk[1]:create_automation(prm)
      auto[1].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS

      auto[1]:add_point_at(3, 0)
      
      local env = flatten_points(pat_seq, 1, prm, true)
      -- Flatten test
      assert(table_eq_deep(env, {
        { time = 1, value = 0 },
      }))
    end
  end

  do
    setup_test(3)

    local pat_seq = renoise.song().sequencer.pattern_sequence

    local pattrk = {}
    for i = 1, 3 do
      pattrk[i] = renoise.song():pattern(i):track(2)
    end

    do
      local prm = renoise.song():track(2):device(1):parameter(1)

      local auto = {}
      auto[1] = pattrk[1]:create_automation(prm)
      auto[3] = pattrk[3]:create_automation(prm)

      auto[1].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS
      auto[3].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS

      auto[1]:add_point_at(3, 0)
      auto[1]:add_point_at(7, 1)
      auto[1]:add_point_at(11, 0.5)
      auto[3]:add_point_at(9, 1)
      
      local env = flatten_points(pat_seq, 2, prm, false)

      -- Flatten test
      assert(table_eq_deep(env, {
        { time = 1, value = 0 },
        { time = 7, value = 1 },
        { time = 11, value = 0.5 },
        { time = 137, value = 1 },
      }))
    
      -- Slice tests

      assert(table_eq_deep(
        slice_points(false, env, 1, 1, 2), {
          { time = 1, value = 0 },
        }))
  
      assert(table_eq_deep(
        slice_points(false, env, 1, 6, 12), {
          { time = 1, value = 0 },
          { time = 2, value = 1 },
          { time = 6, value = 0.5 },
        }))

      assert(table_eq_deep(
        slice_points(false, env, 1, 12, 13), {
          { time = 1, value = 0.5 },
        }))
  
    end

    do
      local prm = renoise.song():track(2):device(1):parameter(6) -- BPM

      local auto = {}
      auto[1] = pattrk[1]:create_automation(prm)
      auto[3] = pattrk[3]:create_automation(prm)

      auto[1].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS
      auto[3].playmode = renoise.PatternTrackAutomation.PLAYMODE_POINTS

      auto[1]:add_point_at(3, 0)
      auto[1]:add_point_at(7, 1)
      auto[1]:add_point_at(11, 0.5)
      auto[3]:add_point_at(9, 1)
      
      local env = flatten_points(pat_seq, 2, prm, false)

      -- Flatten test
      assert(table_eq_deep(env, {
        { time = 1, value = 0 },
        { time = 7, value = 1 },
        { time = 11, value = 0.5 },
        { time = 129, value = 1 }, -- Not at the point but at the head of the pattern
      }))
    end
  end

  print("All automation tests passed.")
end
