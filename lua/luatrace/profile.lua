local trace_file = require("luatrace.trace_file")

local source_files
local stack
local stack_top
local total_time

local profile = {}


function profile.open()
  source_files, stack, stack_top, total_time = {}, {}, 0, 0
end


function profile.record(a, b, c)
  if a == "S" or a == ">" then
    filename, line = b, c
    file = source_files[filename]
    if not file then
      file = { name = filename, lines = {} }
      source_files[filename] = file
    end
    stack_top = stack_top + 1
    stack[stack_top] = { file=file, defined_line = line, frame_time = 0 }

  elseif a == "<" then
    if stack_top > 1 then
      local callee_time = stack[stack_top].frame_time
      stack[stack_top] = nil
      stack_top = stack_top - 1
      local top = stack[stack_top]
      top.file.lines[top.current_line].child_time = top.file.lines[top.current_line].child_time + callee_time
      top.frame_time = top.frame_time + callee_time
    end

  else
    local line, time = a, b
    total_time = total_time + time
    
    local top = stack[stack_top]
    local r = top.file.lines[line]
    if not r then
      r = { visits = 0, self_time = 0, child_time = 0 }
      top.file.lines[line] = r
    end
    if top.current_line ~= line then
      r.visits = r.visits + 1
    end
    r.self_time = r.self_time + time
    top.frame_time = top.frame_time + time
    top.current_line = line
  end
end


function profile.close()
  local all_lines = {}

  -- collect all the lines
  local max_visits = 0
  for _, f in pairs(source_files) do
    for i, l in pairs(f.lines) do
      all_lines[#all_lines + 1] = { filename=f.name, line_number=i, line=l }
      max_visits = math.max(max_visits, l.visits)
    end
  end
  table.sort(all_lines, function(a, b) return a.line.self_time + a.line.child_time > b.line.self_time + b.line.child_time end)
  local max_time = all_lines[1].line.self_time + all_lines[1].line.child_time
  
  local divisor, time_units
  if max_time < 10000 then
    divisor = 1
    time_units = "microseconds"
  elseif max_time < 10000000 then
    divisor = 1000
    time_units = "milliseconds"
  else
    io.stderr:write("Times in seconds\n")
    divisor = 1000000
    time_units = "seconds"
  end
  

  -- Write annotated source
  local visit_format = ("%%%dd"):format(("%d"):format(max_visits):len())
  local line_format = " "..visit_format.."%12.2f%12.2f%12.2f%5d | %-s\n"
  local asf = io.open("annotated-source.txt", "w")
  for _, f in pairs(source_files) do
    local s = io.open(f.name, "r")
    if s then
      asf:write("\n")
      asf:write("====================================================================================================\n")
      asf:write(f.name, "  ", "Times in ", time_units, "\n\n")
      local i = 1
      for l in s:lines() do
        local rec = f.lines[i]
        if rec then
          asf:write(line_format:format(rec.visits, (rec.self_time+rec.child_time) / divisor, rec.self_time / divisor, rec.child_time / divisor, i, l))
        else
          asf:write(line_format:format(0, 0, 0, 0, i, l))
        end
        i = i + 1
      end
    end
    s:close()
  end
  asf:close()

  local title_len = 0
  local file_lines = {}
  for i = 1, math.min(20, #all_lines) do
    local l = all_lines[i]

    l.title = ("%s:%d"):format(l.filename, l.line_number)
    title_len = math.max(title_len, l.title:len())
    
    -- Record the lines of the files we want to see
    local fl = file_lines[l.filename]
    if not fl then
      fl = {}
      file_lines[l.filename] = fl
    end
    fl[l.line_number] = i
  end

  -- Find the text of the lines
  for file_name, line_numbers in pairs(file_lines) do
    local f = io.open(file_name, "r")
    if f then
      local i = 1
      for l in f:lines() do
        local j = line_numbers[i]
        if j then
          all_lines[j].line_text = l
        end
        i = i + 1
      end
    end
    f:close()
  end

  io.stderr:write("Times in ", time_units, "\n")
  io.stderr:write(("Total time %.2f\n"):format(total_time / divisor))

  header_format = ("%%-%ds%%8s%%12s%%12s%%12s  Line\n"):format(title_len+2)
  line_format = ("%%-%ds%%8d%%12.2f%%12.2f%%12.2f  %%-s\n"):format(title_len+2)
  io.stderr:write(header_format:format("File:line", "Visits", "Total", "Self", "Children"))

  for i = 1, math.min(20, #all_lines) do
    local l = all_lines[i]
    io.stderr:write(line_format:format(l.title, l.line.visits,
      (l.line.self_time + l.line.child_time) / divisor, l.line.self_time/divisor, l.line.child_time/divisor,
      l.line_text or "-"))
  end
end


function profile.go()
  trace_file.read{ recorder=profile }
end


-- Main ------------------------------------------------------------------------

if arg and type(arg) == "table" and string.match(debug.getinfo(1, "S").short_src, arg[0]) then
  profile.go()
end


--------------------------------------------------------------------------------

return profile


-- EOF -------------------------------------------------------------------------

