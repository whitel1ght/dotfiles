return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'williamboman/mason.nvim',
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
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

      -- Common on_attach function for LSP clients
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

      -- ts_ls (TypeScript Language Server) configuration
      require('lspconfig').ts_ls.setup({
        capabilities = capabilities,
        filetypes = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'vue' },
        tsdk = vim.fn.stdpath("data") .. "/mason/packages/typescript-language-server/node_modules/typescript/lib",
        init_options = {
          plugins = {
            vue_typescript_plugin,
          },
        },
        on_attach = lsp_attach,
        root_dir = require('lspconfig.util').root_pattern('tsconfig.json', 'jsconfig.json', 'package.json', '.git'),
      })

      -- volar (Vue Language Server) configuration
      require('lspconfig').volar.setup({
        capabilities = capabilities,
        filetypes = { 'vue', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' },
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
            tsdk = vim.fn.stdpath("data") .. "/mason/packages/typescript-language-server/node_modules/typescript/lib",
          },
        },
        on_attach = function(client, bufnr)
          lsp_attach(client, bufnr)
        end,
        root_dir = require('lspconfig.util').root_pattern('tsconfig.json', 'jsconfig.json', 'package.json', '.git'),
      })

      -- Other server configurations
      require('lspconfig').eslint.setup({
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      require('lspconfig').jsonls.setup({
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      require('lspconfig').cssls.setup({
        capabilities = capabilities,
        on_attach = lsp_attach,
      })
      require('lspconfig').html.setup({
        capabilities = capabilities,
        on_attach = lsp_attach,
      })

      -- lua_ls configuration
      require('lspconfig').lua_ls.setup({
        capabilities = capabilities,
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
        on_attach = function(client, bufnr)
          lsp_attach(client, bufnr)
        end,
      })

      require('lspconfig').ruby_lsp.setup({
        capabilities = capabilities,
        on_attach = lsp_attach,
      })

      -- Elixir LS configuration
      require('lspconfig').elixirls.setup({
        capabilities = capabilities,
        cmd = { vim.fn.stdpath("data") .. "/mason/packages/elixir-ls/language_server.sh" },
        settings = {
          elixirLS = {
            -- I choose to disable dialyzer for now, I can enable it as needed
            dialyzerEnabled = false,
            -- I also choose to turn off the auto dep fetching feature.
            -- It often get things wrong and I'd rather do it manually
            fetchDeps = false,
            enableTestLenses = false,
            suggestSpecs = false,
          }
        },
        on_attach = function(client, bufnr)
          lsp_attach(client, bufnr)

          -- Optional: Disable formatting if you prefer to use a dedicated formatter
          -- client.server_capabilities.documentFormattingProvider = false
          -- client.server_capabilities.documentRangeFormattingProvider = false
        end,
        root_dir = require('lspconfig.util').root_pattern('mix.exs', '.git'),
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
          'vue_ls',
          'ruby_lsp',
          'elixirls'
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
