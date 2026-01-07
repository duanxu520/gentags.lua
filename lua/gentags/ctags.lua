local Job = require("plenary.job")
local M = {}

-- Check if a line is a valid tag line (not header, not corrupted)
local function is_valid_tag_line(line)
  -- Tag line format: tagname<TAB>filename<TAB>pattern;"<TAB>kind
  -- Must have at least 3 tab-separated fields
  if not line or line == "" then
    return false
  end
  -- Skip header lines
  if line:match("^!") then
    return true
  end
  -- Check for basic tag format: has tabs and doesn't look like source code
  local tab_count = 0
  for _ in line:gmatch("\t") do
    tab_count = tab_count + 1
  end
  -- Valid tag lines have at least 2 tabs (tagname, filename, pattern)
  if tab_count < 2 then
    return false
  end
  -- Check if first field (tag name) is a valid identifier
  local tag_name = line:match("^([^\t]+)")
  if not tag_name then
    return false
  end
  -- Tag name should be a valid identifier (alphanumeric + underscore, not starting with number)
  if not tag_name:match("^[%a_][%w_]*$") then
    return false
  end
  return true
end

-- Validate and fix corrupted tags file
-- Returns true if file is valid or was fixed, false if couldn't fix
M.validate_tags_file = function(tag_file_path)
  local file = io.open(tag_file_path, "r")
  if not file then
    return true -- File doesn't exist, will be created
  end

  local lines = {}
  local has_invalid_lines = false
  local has_valid_tags = false

  for line in file:lines() do
    if is_valid_tag_line(line) then
      table.insert(lines, line)
      if not line:match("^!") then
        has_valid_tags = true
      end
    else
      has_invalid_lines = true
    end
  end
  file:close()

  -- If file has invalid lines, rewrite it with only valid lines
  if has_invalid_lines then
    if has_valid_tags or #lines > 0 then
      file = io.open(tag_file_path, "w")
      if file then
        for _, line in ipairs(lines) do
          file:write(line .. "\n")
        end
        file:close()
      end
    else
      -- File is completely corrupted, delete it
      os.remove(tag_file_path)
    end
    return true
  end

  return true
end

-- Clean duplicate tags that exceed max_duplicates
-- Returns the number of removed tags
M.clean_duplicates = function(tag_file_path, max_duplicates)
  max_duplicates = max_duplicates or 10

  local file = io.open(tag_file_path, "r")
  if not file then
    return 0
  end

  local lines = {}
  local tag_counts = {}
  local header_lines = {}

  -- Read all lines and count tag occurrences
  for line in file:lines() do
    if line:match("^!") then
      -- Keep header lines (lines starting with !)
      table.insert(header_lines, line)
    else
      table.insert(lines, line)
      -- Extract tag name (first field before tab)
      local tag_name = line:match("^([^\t]+)")
      if tag_name then
        tag_counts[tag_name] = (tag_counts[tag_name] or 0) + 1
      end
    end
  end
  file:close()

  -- Filter out tags that exceed max_duplicates
  local filtered_lines = {}
  local current_counts = {}
  local removed_count = 0

  for _, line in ipairs(lines) do
    local tag_name = line:match("^([^\t]+)")
    if tag_name then
      if tag_counts[tag_name] > max_duplicates then
        -- Skip tags that have too many duplicates
        current_counts[tag_name] = (current_counts[tag_name] or 0) + 1
        if current_counts[tag_name] <= max_duplicates then
          table.insert(filtered_lines, line)
        else
          removed_count = removed_count + 1
        end
      else
        table.insert(filtered_lines, line)
      end
    else
      table.insert(filtered_lines, line)
    end
  end

  -- Write back if any tags were removed
  if removed_count > 0 then
    file = io.open(tag_file_path, "w")
    if file then
      -- Write header lines first
      for _, line in ipairs(header_lines) do
        file:write(line .. "\n")
      end
      -- Write filtered tag lines
      for _, line in ipairs(filtered_lines) do
        file:write(line .. "\n")
      end
      file:close()
    end
  end

  return removed_count
end

M.generate = function(cfg, lang, tag_file, options_path, filepath)
  local tag_file_path = tag_file:expand()

  -- Validate tags file before appending (to avoid appending to corrupted file)
  if filepath then
    M.validate_tags_file(tag_file_path)
  end

  local args = {}

  -- Add user args first (may contain --langdef, --langmap, etc.)
  for _, v in ipairs(cfg.args) do
    table.insert(args, v)
  end

  -- Add options or languages after user args (so --langdef comes first)
  if options_path then
    table.insert(args, "--options=" .. options_path)
  elseif not cfg.has_langdef then
    -- Only add --languages if user didn't define custom language
    table.insert(args, "--languages=" .. lang)
  end

  -- Add output file
  table.insert(args, "-f")
  table.insert(args, tag_file_path)

  if filepath then
    table.insert(args, "-a")
    table.insert(args, filepath)
  else
    table.insert(args, "-R")
    table.insert(args, cfg.root_dir:expand())
  end

  local bin = cfg.bin
  if cfg.bin_map then
    bin = cfg.bin_map[lang] or bin
  end

  local max_duplicates = cfg.max_duplicates

  local j = Job:new({
    command = bin,
    args = args,
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        vim.print(job._stderr_results)
      else
        -- Validate and clean after generation
        M.validate_tags_file(tag_file_path)
        if max_duplicates and max_duplicates > 0 then
          M.clean_duplicates(tag_file_path, max_duplicates)
        end
      end
    end),
  })

  if cfg.async then
    j:start()
  else
    j:sync()
    -- For sync mode, also validate and clean
    M.validate_tags_file(tag_file_path)
    if max_duplicates and max_duplicates > 0 then
      M.clean_duplicates(tag_file_path, max_duplicates)
    end
  end
end

-- Generate tags for a specific subdirectory
M.generate_for_subdir = function(cfg, lang, tag_file, options_path, subdir_path)
  local tag_file_path = tag_file:expand()

  local args = {}

  -- Add user args first (may contain --langdef, --langmap, etc.)
  for _, v in ipairs(cfg.args) do
    table.insert(args, v)
  end

  -- Add options or languages after user args (so --langdef comes first)
  if options_path then
    table.insert(args, "--options=" .. options_path)
  elseif not cfg.has_langdef then
    -- Only add --languages if user didn't define custom language
    table.insert(args, "--languages=" .. lang)
  end

  -- Add output file
  table.insert(args, "-f")
  table.insert(args, tag_file_path)

  -- Use subdir_path instead of root_dir
  table.insert(args, "-R")
  table.insert(args, subdir_path:expand())

  local bin = cfg.bin
  if cfg.bin_map then
    bin = cfg.bin_map[lang] or bin
  end

  local max_duplicates = cfg.max_duplicates

  local j = Job:new({
    command = bin,
    args = args,
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        vim.print(job._stderr_results)
      else
        -- Validate and clean after generation
        M.validate_tags_file(tag_file_path)
        if max_duplicates and max_duplicates > 0 then
          M.clean_duplicates(tag_file_path, max_duplicates)
        end
      end
    end),
  })

  if cfg.async then
    j:start()
  else
    j:sync()
    -- For sync mode, also validate and clean
    M.validate_tags_file(tag_file_path)
    if max_duplicates and max_duplicates > 0 then
      M.clean_duplicates(tag_file_path, max_duplicates)
    end
  end
end

return M
