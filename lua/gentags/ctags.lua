local Job = require("plenary.job")
local M = {}

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
  local args = {
    "-f",
    tag_file:expand(),
  }

  if options_path then
    table.insert(args, 1, "--options="..options_path)
  else
    table.insert(args, 1, "--languages=" .. lang)
  end

  for _, v in ipairs(cfg.args) do
    table.insert(args, v)
  end

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

  local tag_file_path = tag_file:expand()
  local max_duplicates = cfg.max_duplicates

  local j = Job:new({
    command = bin,
    args = args,
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        vim.print(job._stderr_results)
      elseif max_duplicates and max_duplicates > 0 then
        -- Clean duplicates after successful generation
        local removed = M.clean_duplicates(tag_file_path, max_duplicates)
        if removed > 0 then
          vim.print(string.format("[gentags] Removed %d duplicate tags (max: %d)", removed, max_duplicates))
        end
      end
    end),
  })

  if cfg.async then
    j:start()
  else
    j:sync()
    -- For sync mode, also clean duplicates
    if max_duplicates and max_duplicates > 0 then
      M.clean_duplicates(tag_file_path, max_duplicates)
    end
  end
end

-- Generate tags for a specific subdirectory
M.generate_for_subdir = function(cfg, lang, tag_file, options_path, subdir_path)
  local args = {
    "-f",
    tag_file:expand(),
  }

  if options_path then
    table.insert(args, 1, "--options="..options_path)
  else
    table.insert(args, 1, "--languages=" .. lang)
  end

  for _, v in ipairs(cfg.args) do
    table.insert(args, v)
  end

  -- Use subdir_path instead of root_dir
  table.insert(args, "-R")
  table.insert(args, subdir_path:expand())

  local bin = cfg.bin
  if cfg.bin_map then
    bin = cfg.bin_map[lang] or bin
  end

  local tag_file_path = tag_file:expand()
  local max_duplicates = cfg.max_duplicates

  local j = Job:new({
    command = bin,
    args = args,
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        vim.print(job._stderr_results)
      elseif max_duplicates and max_duplicates > 0 then
        -- Clean duplicates after successful generation
        local removed = M.clean_duplicates(tag_file_path, max_duplicates)
        if removed > 0 then
          vim.print(string.format("[gentags] Removed %d duplicate tags (max: %d)", removed, max_duplicates))
        end
      end
    end),
  })

  if cfg.async then
    j:start()
  else
    j:sync()
    -- For sync mode, also clean duplicates
    if max_duplicates and max_duplicates > 0 then
      M.clean_duplicates(tag_file_path, max_duplicates)
    end
  end
end

return M