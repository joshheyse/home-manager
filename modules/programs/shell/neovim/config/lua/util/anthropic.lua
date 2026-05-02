-- Shared Anthropic API config.
-- Detects work vs home environment via ANTHROPIC_BASE_URL: when set, route
-- through the CTC litellm proxy with ANTHROPIC_AUTH_TOKEN; otherwise use the
-- public Anthropic API with ANTHROPIC_API_KEY.

local work_base_url = os.getenv "ANTHROPIC_BASE_URL"
local is_work = work_base_url ~= nil and work_base_url ~= ""

local M = {
  is_work = is_work,
  api_key_env = is_work and "ANTHROPIC_AUTH_TOKEN" or "ANTHROPIC_API_KEY",
  models = {
    sonnet = "claude-sonnet-4-6",
    haiku = is_work and "anthropic.claude-v4-5-haiku" or "claude-haiku-4-5-20251001",
  },
}

--- Messages endpoint URL. Returns the public API URL at home, or the proxy
--- URL at work. Always returns an absolute URL.
function M.messages_url()
  if not is_work then return "https://api.anthropic.com/v1/messages" end
  return work_base_url:gsub("/+$", "") .. "/v1/messages"
end

--- Messages endpoint URL, but nil at home (for callers like codecompanion's
--- adapter override that only want to set `url` when overriding the default).
function M.messages_url_override()
  if not is_work then return nil end
  return M.messages_url()
end

return M
