local M = {}

-- Helper function to get git root directory
local function get_git_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 then return nil end
  return git_root
end

-- Helper function to get git remote origin URL
local function get_git_remote_url()
  local remote_url = vim.fn.systemlist("git config --get remote.origin.url")[1]
  if vim.v.shell_error ~= 0 then return nil end
  return remote_url
end

-- Helper function to get list of local git branches
local function get_local_branches()
  local branches = vim.fn.systemlist "git branch --format='%(refname:short)'"
  if vim.v.shell_error ~= 0 then return nil end
  return branches
end

-- Helper function to strip a trailing ".git" from a repo segment
local function strip_git_suffix(s) return (s:gsub("%.git$", "")) end

-- Percent-encode a string for use in a URL query value (RFC 3986 unreserved chars kept)
local function url_encode(s)
  return (s:gsub("([^A-Za-z0-9%-_%.~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- Helper function to parse git remote URL and extract host, owner, repo, kind.
-- kind is one of: "bitbucket-server", "generic" (GitHub/GitLab-style).
local function parse_git_url(url)
  if not url then return nil end

  local host, owner, repo, kind

  -- Bitbucket Server SSH: ssh://git@host:PORT/project/repo(.git)?
  -- Port is typically 7999 for Bitbucket Server.
  host, owner, repo = url:match "^ssh://git@([^:/]+):%d+/([^/]+)/(.+)$"
  if host then
    kind = "bitbucket-server"
    return { host = host, owner = owner, repo = strip_git_suffix(repo), kind = kind }
  end

  -- Bitbucket Server HTTPS: https://host/scm/project/repo(.git)?
  host, owner, repo = url:match "^https?://[^/]*[^@/]*@?([^/]+)/scm/([^/]+)/(.+)$"
  if not host then
    host, owner, repo = url:match "^https?://([^/]+)/scm/([^/]+)/(.+)$"
  end
  if host then
    kind = "bitbucket-server"
    return { host = host, owner = owner, repo = strip_git_suffix(repo), kind = kind }
  end

  -- Generic SSH: git@host:owner/repo(.git)?
  host, owner, repo = url:match "^git@([^:]+):([^/]+)/(.+)$"
  if host then
    kind = "generic"
    return { host = host, owner = owner, repo = strip_git_suffix(repo), kind = kind }
  end

  -- Generic HTTPS: https://host/owner/repo(.git)?
  host, owner, repo = url:match "^https?://([^/]+)/([^/]+)/(.+)$"
  if host then
    kind = "generic"
    return { host = host, owner = owner, repo = strip_git_suffix(repo), kind = kind }
  end

  return nil
end

-- Yank the relative path of current buffer (relative to git root)
function M.yank_path()
  local filepath = vim.fn.expand "%:p"
  if filepath == "" then
    vim.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  -- Get relative path from git root
  local relative_path = filepath:sub(#git_root + 2) -- +2 to skip the trailing slash

  -- Copy to system clipboard
  vim.fn.setreg("+", relative_path)
  vim.notify("Yanked path: " .. relative_path, vim.log.levels.INFO)
end

-- Yank the GitHub/GitLab URL for current buffer
-- Optional start_line and end_line parameters for visual mode ranges
-- Optional branch parameter to specify a specific branch
function M.yank_url(start_line, end_line, branch)
  local filepath = vim.fn.expand "%:p"
  if filepath == "" then
    vim.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  local remote_url = get_git_remote_url()
  if not remote_url then
    vim.notify("No git remote origin configured", vim.log.levels.WARN)
    return
  end

  local git_info = parse_git_url(remote_url)
  if not git_info then
    vim.notify("Could not parse git remote URL: " .. remote_url, vim.log.levels.ERROR)
    return
  end

  -- Get branch (use provided branch or current branch)
  if not branch then
    branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]
    if vim.v.shell_error ~= 0 then
      branch = "main" -- fallback to main
    end
  end

  -- Get relative path from git root
  local relative_path = filepath:sub(#git_root + 2)

  -- Determine line number or range
  local line_fragment
  if start_line and end_line and start_line ~= end_line then
    if git_info.kind == "bitbucket-server" then
      -- Bitbucket Server uses a single anchor per-range: #34-36
      line_fragment = string.format("%d-%d", start_line, end_line)
    else
      line_fragment = string.format("L%d-L%d", start_line, end_line)
    end
  else
    local line_number = start_line or vim.fn.line "."
    if git_info.kind == "bitbucket-server" then
      line_fragment = tostring(line_number)
    else
      line_fragment = string.format("L%d", line_number)
    end
  end

  -- Construct URL based on remote kind
  local url
  if git_info.kind == "bitbucket-server" then
    -- Bitbucket Server: https://host/projects/KEY/repos/REPO/browse/PATH?at=refs/heads/BRANCH#LINE
    -- The branch ref is percent-encoded because branches may contain '/'.
    url = string.format(
      "https://%s/projects/%s/repos/%s/browse/%s?at=%s#%s",
      git_info.host,
      git_info.owner:upper(),
      git_info.repo,
      relative_path,
      url_encode("refs/heads/" .. branch),
      line_fragment
    )
  else
    -- GitHub/GitLab style
    url = string.format(
      "https://%s/%s/%s/blob/%s/%s#%s",
      git_info.host,
      git_info.owner,
      git_info.repo,
      branch,
      relative_path,
      line_fragment
    )
  end

  -- Copy to system clipboard
  vim.fn.setreg("+", url)
  vim.notify("Yanked URL: " .. url, vim.log.levels.INFO)
end

-- Yank URL with branch selector
function M.yank_url_with_branch_selector(start_line, end_line)
  -- Check if we're in a git repo first
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  -- Get list of local branches
  local branches = get_local_branches()
  if not branches or #branches == 0 then
    vim.notify("No local branches found", vim.log.levels.WARN)
    return
  end

  -- Get current branch to set as default
  local current_branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]

  -- Show branch selector
  vim.ui.select(branches, {
    prompt = "Select branch for URL:",
    format_item = function(item)
      if item == current_branch then return item .. " (current)" end
      return item
    end,
  }, function(selected_branch)
    if selected_branch then
      -- Call yank_url with the selected branch
      M.yank_url(start_line, end_line, selected_branch)
    end
  end)
end

-- Yank the absolute path of current buffer
function M.yank_absolute_path()
  local filepath = vim.fn.expand "%:p"
  if filepath == "" then
    vim.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", filepath)
  vim.notify("Yanked absolute path: " .. filepath, vim.log.levels.INFO)
end

-- Yank the absolute path of the git repo root
function M.yank_repo_path()
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", git_root)
  vim.notify("Yanked repo path: " .. git_root, vim.log.levels.INFO)
end

return M
