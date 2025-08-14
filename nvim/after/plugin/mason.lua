require("mason").setup({
  height = 0.5,
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗"
    },
  },
  registries = {
    "github:mason-org/mason-registry",
  }
})
