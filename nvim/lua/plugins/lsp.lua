return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'williamboman/mason.nvim',
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      -- vim.fs.root replaces lspconfig.util.root_pattern. Touching
      -- `require('lspconfig')` at all -- even for the .util submodule --
      -- triggers the deprecation warning and a full traceback on startup.
      local function root_pattern(...)
        local patterns = { ... }
        return function(bufnr)
          return vim.fs.root(bufnr, patterns)
        end
      end

      local border = {
        {"🭽", "FloatBorder"},
        {"▔", "FloatBorder"},
        {"🭾", "FloatBorder"},
        {"▕", "FloatBorder"},
        {"🭿", "FloatBorder"},
        {" ", "FloatBorder"},
        {"🭼", "FloatBorder"},
        {"▏", "FloatBorder"},
      }

      -- Path to Volar's node_modules for the TypeScript plugin
      local volar_language_server_path = vim.fn.stdpath('data') .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"

      local vue_typescript_plugin = {
        name = '@vue/typescript-plugin',
        location = volar_language_server_path,
        languages = { 'vue' },
        configNamespace = 'typescript',
      }

      -- Define capabilities for nvim-cmp if it's available
      local capabilities = nil
      if pcall(require, 'cmp_nvim_lsp') then
        capabilities = require('cmp_nvim_lsp').default_capabilities()
      end

      -- Common on_attach for every LSP client
      local lsp_attach = function(client, bufnr)
        local opts = {buffer = bufnr}
        vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
        vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
        vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
        vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
        vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', opts)
        vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)
        vim.keymap.set('n', '<F2>', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
        vim.keymap.set({'n', 'x'}, '<F3>', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)
        vim.keymap.set('n', '<F4>', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
      end

      -- Defaults applied to every server, so the per-server setup() calls below
      -- no longer have to repeat capabilities and on_attach.
      vim.lsp.config('*', {
        capabilities = capabilities,
        on_attach = lsp_attach,
      })

      -- Directly set global LSP handlers with border options
      local default_hover_handler = vim.lsp.handlers.hover
      vim.lsp.handlers["textDocument/hover"] = function(err, result, ctx, config)
        config = config or {}
        config.border = border
        return default_hover_handler(err, result, ctx, config)
      end

      local default_signature_help_handler = vim.lsp.handlers.signature_help
      vim.lsp.handlers["textDocument/signatureHelp"] = function(err, result, ctx, config)
        config = config or {}
        config.border = border
        return default_signature_help_handler(err, result, ctx, config)
      end

      local tsdk = vim.fn.stdpath("data") .. "/mason/packages/typescript-language-server/node_modules/typescript/lib"
      local js_root = root_pattern('tsconfig.json', 'jsconfig.json', 'package.json', '.git')

      -- ts_ls (TypeScript Language Server) configuration
      vim.lsp.config('ts_ls', {
        filetypes = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'vue' },
        tsdk = tsdk,
        init_options = {
          plugins = {
            vue_typescript_plugin,
          },
        },
        root_dir = js_root,
      })

      -- vue_ls is the current name for the server the old config enabled as
      -- `volar`; the two are the same package.
      vim.lsp.config('vue_ls', {
        filetypes = { 'vue' },
        settings = {
          vue = {
            complete = {
              casing = {
                props = 'camelCase',
                tags = 'kebabCase',
              },
            },
          },
          typescript = {
            tsdk = tsdk,
          },
          javascript = {
            validate = true,
          },
        },
        root_dir = js_root,
      })

      -- Other server configurations
      vim.lsp.config('eslint', {})
      vim.lsp.config('jsonls', {})
      vim.lsp.config('cssls', {})
      vim.lsp.config('html', {})

      -- lua_ls configuration
      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
              special = {
                import = 'require',
              },
            },
            workspace = {
              checkThirdParty = false,
              library = vim.api.nvim_get_runtime_file("", true),
              maxPreload = 10000,
              preloadFileSize = 10000,
            },
            diagnostics = {
              globals = { 'vim', 'use', 'fs_stat' },
            },
            completion = {
              callSnippet = 'Replace',
              keywordSnippet = 'Replace',
            },
            hint = {
              enable = true,
              setType = true,
            },
            telemetry = {
              enable = false,
            },
          },
        },
      })

      -- mason-lspconfig runs with automatic_enable = false, so this is the
      -- single place that actually starts servers.
      vim.lsp.enable({
        'ts_ls',
        'vue_ls',
        'eslint',
        'jsonls',
        'cssls',
        'html',
        'lua_ls',
      })
    end
  },
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim' },
    config = function ()
      require('mason').setup({})
      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls',
          'ts_ls',
          'cssls',
          'html',
          'jsonls',
          'eslint',
          'vue_ls'
        },
        automatic_enable = false,
        automatic_installation = true,
      })
    end
  },
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    dependencies = { 'williamboman/mason.nvim' },
  },
}