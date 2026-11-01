-- nvim 0.12 workaround for the archived nvim-treesitter markdown query.
--
-- The plugin (master) ships queries/markdown/injections.scm that uses the
-- `set-lang-from-info-string!` directive, whose handler calls get_node_text()
-- on a TSNode that 0.12 has already freed mid-injection-parse. Result when a
-- markdown buffer with a fenced code block is highlighted (very visible in the
-- telescope preview): "attempt to call method 'range' (a nil value)" crashing
-- the decoration provider.
--
-- Replace that injections query with the nvim 0.12 core equivalent (plain
-- @injection.language capture, no directives) so code-fence injection still
-- works and the freed-node path is gone. Wrapped in pcall since this only
-- matters while the pinned plugin is in use.
pcall(function()
  vim.treesitter.query.set('markdown', 'injections', [[
(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)

((html_block) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined)
  (#set! injection.include-children))

((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

((plus_metadata) @injection.content
  (#set! injection.language "toml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))
]])
end)