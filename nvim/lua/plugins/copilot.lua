return {
  "zbirenbaum/copilot.lua",
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "main",
    dependencies = {
      { "whitel1ght/copilot.lua",
        config = function()
          vim.g.copilot_proxy = os.getenv("HTTP_PROXY")
        end
      },
      { "nvim-lua/plenary.nvim" },
    },
    build = "make tiktoken",
    opts = {
      proxy = os.getenv("HTTP_PROXY"),
      allow_insecure = true
    },
  },
}