-- Chat and inline edits against LM Studio by default. `ga` in a chat switches to
-- OpenCode Go or to the Claude / ChatGPT subscriptions (ACP agents, chat only).
-- Bridges: npm i -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp
-- (the @zed-industries packages are abandoned and break on current settings).
-- Claude needs CODECOMPANION_CLAUDE_TOKEN (from `claude setup-token`) in ~/.zshrc.local.
return {
  'olimorris/codecompanion.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = { 'CodeCompanion', 'CodeCompanionChat', 'CodeCompanionActions' },
  keys = {
    { '<leader>ai', '<cmd>CodeCompanionChat Toggle<cr>', mode = { 'n', 'v' }, desc = 'AI chat' },
    { '<leader>aa', '<cmd>CodeCompanionChat Add<cr>', mode = 'v', desc = 'AI add selection to chat' },
    { '<leader>ap', '<cmd>CodeCompanionActions<cr>', mode = { 'n', 'v' }, desc = 'AI actions' },
    { '<leader>ae', ':CodeCompanion ', mode = { 'n', 'v' }, desc = 'AI inline edit' },
  },
  -- Winbar on chat windows: current adapter and model, following `ga` switches.
  init = function()
    function _G.CodeCompanionWinbar()
      local meta = (_G.codecompanion_chat_metadata or {})[vim.api.nvim_win_get_buf(vim.g.statusline_winid)]
      if not meta then
        return ''
      end
      return ' ' .. meta.adapter.name .. ' · ' .. (meta.adapter.model or '?')
    end
    local group = vim.api.nvim_create_augroup('CodeCompanionWinbar', {})
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = 'codecompanion',
      callback = function()
        vim.wo.winbar = '%!v:lua.CodeCompanionWinbar()'
      end,
    })
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = { 'CodeCompanionChatOpened', 'CodeCompanionChatAdapter', 'CodeCompanionChatModel', 'CodeCompanionRequestFinished' },
      callback = vim.schedule_wrap(function()
        vim.cmd('redrawstatus!')
      end),
    })
  end,
  opts = {
    adapters = {
      http = {
        -- Load first: lms load gemma-4-e4b-it-mlx -c 32768 --parallel 1
        lmstudio = function()
          return require('codecompanion.adapters').extend('openai_compatible', {
            formatted_name = 'LM Studio',
            env = { url = 'http://127.0.0.1:1234', api_key = 'lmstudio', chat_url = '/v1/chat/completions' },
            schema = { model = { default = 'gemma-4-e4b-it-mlx' } },
          })
        end,
        -- Same endpoint and auth helper as the opencode-go provider in pi/models.json.
        opencode_go = function()
          local auth = vim.fn.expand('~/.local/bin/opencode-console-auth')
          return require('codecompanion.adapters').extend('openai_compatible', {
            formatted_name = 'OpenCode Go',
            env = {
              url = 'https://opencode.ai/inference/go/openai',
              chat_url = '/v1/chat/completions',
              api_key = 'cmd:' .. auth .. ' token',
            },
            -- Go rejects requests without a session id (MissingSessionID); one per nvim process.
            headers = {
              ['x-opencode-org-id'] = vim.trim(vim.fn.system({ auth, 'org' })),
              ['x-opencode-session'] = vim.trim(vim.fn.system({ 'uuidgen' })):lower(),
            },
            schema = {
              model = {
                default = 'longcat-2.5-preview-free',
                choices = {
                  'longcat-2.5-preview-free',
                  'glm-5.3',
                  'kimi-k3',
                  'qwen3.8-max',
                  'gpt-6-luna',
                  'grok-4.7',
                  'glm-5.3-flash',
                  'qwen3.8-flash',
                },
              },
            },
          })
        end,
      },
      acp = {
        claude_code = function()
          return require('codecompanion.adapters').extend('claude_code', {
            -- Not CLAUDE_CODE_OAUTH_TOKEN itself: exported in zsh it would override the claude CLI login.
            env = { CLAUDE_CODE_OAUTH_TOKEN = 'CODECOMPANION_CLAUDE_TOKEN' },
          })
        end,
        codex = function()
          return require('codecompanion.adapters').extend('codex', {
            defaults = { auth_method = 'chat-gpt' },
          })
        end,
      },
    },
    interactions = {
      chat = { adapter = 'lmstudio' },
      inline = { adapter = 'lmstudio' },
    },
  },
}
