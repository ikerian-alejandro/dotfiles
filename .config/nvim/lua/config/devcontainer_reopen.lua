-- Implements a `:DevcontainerReopen` command that connects the host and container
-- together with devcontainer-bridge (dbr), and then hands the current editor over
-- to a Neovim server running in the container, performing the following steps:
--
--   1. Ensure the dbr host daemon is up (`dbr ensure`, idempotent) and read the
--      auth token it persists at ~/.config/dbr/auth-token.
--   2. Start the dbr container daemon in the devcontainer. It watches for new TCP
--      listen sockets on it and auto-forwards them to the same port on the host
--      loopback interface.
--   3. Start a headless `nvim --listen 127.0.0.1:<port>` server in the container.
--   4. Once dbr has forwarded that port to the host, hand this session over to
--      the server: a terminal Neovim exec-replaces itself in place with a
--      `--server` remote-UI client, while a GUI (Neovide, nvim-qt) is relaunched
--      against `--server` and this session quits.
--
-- Both container-side processes are launched through the `devcontainer` CLI and
-- run detached so they outlive this Neovim. Requires `dbr` on the host and in
-- the container, the `devcontainer` CLI, and the erichlf/devcontainer-cli.nvim
-- plugin (to resolve the workspace folder).

local M = {}

local CONTAINER_LOG = "/var/log/devcontainer-bridge-container-daemon.log"

local function notify(msg, level)
  vim.notify("[DevcontainerReopen] " .. msg, level or vim.log.levels.INFO)
end

-- Prefer stderr, falling back to stdout, for reporting a failed command.
---@param res vim.SystemCompleted
local function output(res)
  local text = res.stderr
  if text == nil or text == "" then
    text = res.stdout
  end
  return vim.trim(text or "")
end

-- The workspace folder devcontainer-cli.nvim brought the container up in,
-- required for `devcontainer exec` to resolve to that same container.
local function workspace_folder()
  return require("devcontainer-cli.folder_utils").get_root(require("devcontainer-cli.config").toplevel)
end

-- True once something accepts TCP connections at `addr` (i.e. dbr has forwarded
-- the container's port onto host loopback).
---@param addr string
local function port_reachable(addr)
  local ok, chan = pcall(vim.fn.sockconnect, "tcp", addr)
  if ok and chan ~= 0 then
    pcall(vim.fn.chanclose, chan)
    return true
  end
  return false
end

-- Pick a free loopback port for the container Neovim server. dbr forwards it to
-- the same port on the host, so a free port on the host side should also translate
-- to a free port on the container side.
local function free_server_addr()
  local sock = vim.uv.new_tcp()
  if not sock then
    -- Fall back to a port that should be available at least once
    return "127.0.0.1:6666"
  end

  -- This is theoretically vulnerable to TOCTOU, but that's not a concern for an
  -- interactive dev command like this
  sock:bind("127.0.0.1", 0)
  local port = sock:getsockname().port
  sock:close()
  return "127.0.0.1:" .. port
end

-- Ensure the host daemon is running and return the auth token it persisted.
-- `dbr ensure` is idempotent and creates ~/.config/dbr/auth-token on first run.
local function ensure_host_dbr_daemon()
  local res = vim.system({ "dbr", "ensure" }):wait(10000)
  if res.code ~= 0 then
    notify("`dbr ensure` failed: " .. output(res), vim.log.levels.ERROR)
    return nil
  end
  local token_file = vim.fn.expand("~/.config/dbr/auth-token")
  local ok, lines = pcall(vim.fn.readfile, token_file)
  if not ok or not lines[1] or vim.trim(lines[1]) == "" then
    notify("Could not read the dbr auth token at " .. token_file, vim.log.levels.ERROR)
    return nil
  end
  return vim.trim(lines[1])
end

-- Replace the running process image with `argv` via a `execvp`, inheriting
-- the controlling terminal. Only returns (with an error) if the exec fails.
---@param argv string[]
local function execvp(argv)
  local ffi = require("ffi")
  pcall(ffi.cdef, "int execvp(const char *file, char *const argv[]);")
  local c_argv = ffi.new("char *[?]", #argv + 1)
  for i, arg in ipairs(argv) do
    c_argv[i - 1] = ffi.cast("char *", arg)
  end
  c_argv[#argv] = nil
  ffi.C.execvp(argv[1], c_argv)
  notify("Failed to exec " .. table.concat(argv, " "), vim.log.levels.ERROR)
end

-- Returns the executable path of the supported GUI embedder that spawned this
-- Neovim instance, taking advantage of the fact that every supported GUI
-- announces itself over RPC via nvim_set_client_info(). More robust than
-- checking global Lua state.
local function detect_gui()
  local SUPPORTED_GUIS = { neovide = true, ["nvim-qt"] = true }

  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local ok, info = pcall(vim.api.nvim_get_chan_info, ui.chan or 0)
    local name = ok and info.client and info.client.name
    if name and SUPPORTED_GUIS[name] then
      return vim.fn.exepath(name)
    end
  end
end

-- Hand this session over to the container server. UI embedders (Neovide, nvim-qt,
-- ...) launch Neovim themselves with a well-known client name, while a terminal
-- Neovim can exec-replace itself in place.
local function handoff(server_addr)
  local gui_exe = detect_gui()
  if gui_exe then
    -- Spawn a new GUI process, and quit the current process
    vim.system({ gui_exe, "--server", server_addr }, { detach = true })
    vim.cmd("quitall")
  else
    -- Replace the current process in place with a remote-UI client for the server
    execvp({ vim.v.progpath, "--server", server_addr, "--remote-ui" })
  end
end

--

function M.reopen()
  -- Switching Neovim processes may be a lossy operation, so make sure any open buffers are saved
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buftype == "" then
      return notify("Unsaved changes, save or discard them before switching", vim.log.levels.ERROR)
    end
  end

  local folder = workspace_folder()
  if not folder then
    return notify("No devcontainer found for the current directory", vim.log.levels.ERROR)
  end

  -- 1. Host dbr daemon + auth token.
  notify("Spawning dbr host daemon...")
  local token = ensure_host_dbr_daemon()
  if not token then
    return
  end

  -- Confirm the container is up (and dbr is installed in it) before we background
  -- anything, so failures due to that are reported more eagerly.
  local function devcontainer_exec(cmd)
    return vim.list_extend({ "devcontainer", "exec", "--workspace-folder", folder }, cmd)
  end
  local dbr_check = vim.system(devcontainer_exec({ "dbr", "--version" }), { text = true }):wait(20000)
  if dbr_check.code ~= 0 then
    return notify(
      "`dbr` version check failed to run in devcontainer, is it installed? " .. output(dbr_check),
      vim.log.levels.ERROR
    )
  end

  -- 2. Container daemon: auto-forwards new TCP listeners to host loopback. Make sure
  --    only one is ever spawned, as otherwise they will fight each other for the sockets.
  vim.system(
    devcontainer_exec({
      "sh",
      "-c",
      "ps -A -o comm= | grep -qF dbr || exec dbr container-daemon --auth-token "
        .. vim.fn.shellescape(token)
        .. " --log-file "
        .. vim.fn.shellescape(CONTAINER_LOG),
    }),
    { detach = true, stdout = false, stderr = false }
  )

  -- 3. Headless Neovim server on a free loopback port inside the container.
  local server_addr = free_server_addr()
  vim.system(
    devcontainer_exec({ "nvim", "--headless", "--listen", server_addr }),
    { detach = true, stdout = false, stderr = false }
  )

  -- 4. Wait for dbr to forward the port to the host, then hand off.
  notify("Waiting for the Neovim server at " .. server_addr .. "...")
  if not vim.wait(20000, function()
    return port_reachable(server_addr)
  end, 200) then
    return notify(
      ("Neovim server at %s not reachable, check %s on the container"):format(server_addr, CONTAINER_LOG),
      vim.log.levels.ERROR
    )
  end
  handoff(server_addr)
end

function M.setup()
  vim.api.nvim_create_user_command("DevcontainerReopen", M.reopen, {
    desc = "Switch this editor to a Neovim server running in the devcontainer",
  })
end

return M
