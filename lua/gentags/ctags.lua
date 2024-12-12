local Job = require("plenary.job")
local M = {}

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

  local j = Job:new({
    command = bin,
    args = args,
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        vim.print(job._stderr_results)
      end
    end),
  })

  if cfg.async then
    j:start()
  else
    j:sync()
  end
end

return M
