-- Inline ghost-text completion from a local FIM model in LM Studio. <Tab> accepts.
-- :LocalComplete [start|stop] (or <leader>ac to toggle) loads/unloads the model and
-- switches suggestions on/off in every buffer. On startup it is on only if the model
-- is already loaded. Uses a base model, not instruct: FIM needs its <|fim_*|> tokens.
local model = 'qwen2.5-coder-1.5b'
local lms = vim.fn.expand('~/.lmstudio/bin/lms')

return {
  'milanglacier/minuet-ai.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  -- Not InsertEnter: auto-trigger is switched on per buffer in a FileType autocmd,
  -- which has already fired for the open buffer by then.
  event = { 'BufReadPre', 'BufNewFile' },
  cmd = 'LocalComplete',
  keys = {
    { '<leader>ac', '<cmd>LocalComplete<cr>', desc = 'AI autocomplete toggle' },
  },
  config = function()
    require('minuet').setup({
      provider = 'openai_fim_compatible',
      n_completions = 1,
      -- Characters around the cursor; a 1.5B model gains little from more and slows down.
      context_window = 4000,
      request_timeout = 3,
      virtualtext = {
        auto_trigger_ft = { '*' },
        auto_trigger_ignore_ft = { 'vimwiki', 'codecompanion', 'TelescopePrompt', 'oil' },
        show_on_completion_menu = false,
      },
      provider_options = {
        openai_fim_compatible = {
          name = 'LM Studio',
          api_key = function()
            return 'lmstudio'
          end,
          end_point = 'http://127.0.0.1:1234/v1/completions',
          model = model,
          stream = true,
          -- FIM prompt built by hand rather than relying on LM Studio's `suffix` handling.
          template = {
            prompt = function(before, after, _)
              return '<|fim_prefix|>' .. before .. '<|fim_suffix|>' .. after .. '<|fim_middle|>'
            end,
            suffix = false,
          },
          optional = {
            max_tokens = 64,
            temperature = 0.1,
            stop = { '<|fim_pad|>', '<|endoftext|>', '<|file_sep|>', '<|fim_prefix|>' },
          },
        },
      },
    })

    local vt = require('minuet.virtualtext')
    vim.keymap.set('i', '<Tab>', function()
      if vt.action.is_visible() then
        vt.action.accept()
      else
        vim.api.nvim_feedkeys(vim.keycode('<Tab>'), 'n', false)
      end
    end, { desc = 'Accept AI suggestion' })

    -- minuet only has a per-buffer switch; this makes it global. Buffers left nil
    -- are the ignored filetypes, so they stay off either way.
    local enabled = false
    local function set_enabled(on)
      enabled = on
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.b[buf].minuet_virtual_text_auto_trigger ~= nil then
          vim.b[buf].minuet_virtual_text_auto_trigger = on
        end
      end
      if not on then
        vt.action.dismiss()
      end
    end

    -- Registered after minuet's own FileType autocmd, so it runs second and wins.
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('LocalComplete', {}),
      callback = function()
        if not enabled and vim.b.minuet_virtual_text_auto_trigger ~= nil then
          vim.b.minuet_virtual_text_auto_trigger = false
        end
      end,
    })

    -- The HTTP API, not `lms ps`: lms would wake LM Studio on every nvim start.
    local function is_loaded(cb)
      vim.system({ 'curl', '-s', '-m', '1', 'http://127.0.0.1:1234/api/v0/models/' .. model }, {}, function(r)
        local ok, info = pcall(vim.json.decode, r.stdout or '')
        vim.schedule(function()
          cb(r.code == 0 and ok and type(info) == 'table' and info.state == 'loaded')
        end)
      end)
    end

    local function notify(msg, level)
      vim.notify(msg, level or vim.log.levels.INFO, { title = 'LocalComplete' })
    end

    local function start()
      is_loaded(function(loaded)
        if loaded then
          set_enabled(true)
          return notify('on')
        end
        notify('loading ' .. model .. '…')
        vim.system({ lms, 'server', 'start' }, {}, function()
          vim.system({ lms, 'load', model, '-c', '4096', '-y' }, {}, function(r)
            vim.schedule(function()
              if r.code ~= 0 then
                return notify('load failed: ' .. vim.trim(r.stderr or ''), vim.log.levels.ERROR)
              end
              set_enabled(true)
              notify('on')
            end)
          end)
        end)
      end)
    end

    -- Leaves the server running: CodeCompanion talks to it too.
    local function stop()
      set_enabled(false)
      vim.system({ lms, 'unload', model }, {}, function()
        vim.schedule(function()
          notify('off, model unloaded')
        end)
      end)
    end

    vim.api.nvim_create_user_command('LocalComplete', function(o)
      local arg = o.args ~= '' and o.args or (enabled and 'stop' or 'start')
      if arg == 'start' then
        start()
      elseif arg == 'stop' then
        stop()
      else
        notify('usage: LocalComplete [start|stop]', vim.log.levels.ERROR)
      end
    end, {
      nargs = '?',
      complete = function()
        return { 'start', 'stop' }
      end,
    })

    is_loaded(function(loaded)
      if loaded then
        set_enabled(true)
      end
    end)
  end,
}
