local util = require('util')
local log  = require('log')

local git = {}

local config = {}
git.set_config = function(cmd, subcommands, base_dir, default_pkg)
  config.git = cmd
  config.cmds = subcommands
  config.base_dir = base_dir
  config.default_base_dir = util.join_paths(base_dir, default_pkg)
end

git.make_installer = function(plugin)
  local needs_checkout = plugin.rev ~= nil or plugin.branch ~= nil
  local base_dir = nil
  if plugin.package then
    base_dir = util.join_paths(config.base_dir, plugin.package)
  else
    base_dir = config.default_base_dir
  end

  base_dir = util.join_paths(base_dir, plugin.type)

  local install_to = util.join_paths(base_dir, plugin.name)
  local install_cmd = config.git .. ' ' .. vim.fn.printf(config.cmds.install, plugin.url, install_to)
  if plugin.branch then
    install_cmd = install_cmd .. ' --branch ' .. plugin.branch
  end

  -- TODO: Fix callbacks here so that failure chains appropriately
  plugin.installer = function(display_win, job_ctx)
    local job = job_ctx:new_job({
      task = install_cmd,
      callbacks = {
        exit = function(exit_code, _)
          if needs_checkout then
            return exit_code == 0
          end

          if exit_code ~= 0 then
            log.error('Installing ' .. plugin.name .. ' failed!')
            display_win:task_failed(plugin.name, 'Installing')
            return false
          end

          display_win:task_succeeded(plugin.name, 'Installing')
          return true
        end
      }})

    if needs_checkout then
      local callbacks = {
        exit = function(exit_code, signal)
          if exit_code ~= 0 then
            log.error(vim.fn.printf('Installing %s%s failed!', plugin.name, branch_rev))
            display_win:task_failed(plugin.name, 'Installing')
            return false
          end

          return true
        end
      }

      job = job * job_ctx:new_job({
        task = config.git .. ' ' .. vim.fn.printf(config.cmds.fetch, install_to),
        callbacks = callbacks
      })

      if plugin.branch then
        job = job *
          job_ctx:new_job({
            task = config.git .. ' ' .. vim.fn.printf(config.cmds.update_branch, install_to),
            callbacks = callbacks
          }) *
          job_ctx:new_job({
            task = config.git .. ' ' .. vim.fn.printf(config.cmds.checkout, install_to, plugin.branch),
            callbacks = callbacks
          })
      end

      if plugin.rev then
        job = job * job_ctx:new_job({
          task = config.cmd .. ' ' .. vim.fn.printf(config.cmds.checkout, install_to, plugin.rev),
          callbacks = {
            exit = function(_, exit_code)
              local branch_rev = ''
              if plugin.branch then
                branch_rev = ':' .. plugin.branch
              end

              if plugin.rev then
                branch_rev = branch_rev .. '@' .. plugin.rev
              end

              if exit_code ~= 0 then
                log.error(vim.fn.printf('Installing %s%s failed!', plugin.name, branch_rev))
                display_win:task_failed(plugin.name, 'Installing')
                return false
              end

              display_win:task_succeeded(plugin.name .. branch_rev, 'Installing')
              return true
            end
          }
        })
      end
    end

    return job
  end

  -- TODO: The updater should do a fetch, then make sure we're on the expected branch, then make
  -- sure we're on the expected rev
  local update_cmd = config.git .. ' ' .. vim.fn.printf(config.cmds.update, plugin.url, install_to)
  if plugin.branch then
    install_cmd = install_cmd .. ' --branch ' .. plugin.branch
  end
  plugin.updater = function(display_win, job_ctx)
  end
end

return git
