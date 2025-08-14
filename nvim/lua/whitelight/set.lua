vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.softtabstop = 2
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.wildmenu = true

vim.opt.termguicolors = true

vim.opt.cmdheight = 0
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

-- folding
vim.opt.foldmethod = 'indent'
vim.opt.foldnestmax = 30
vim.opt.foldlevelstart = 7

-- path
vim.opt.path:append '**'
vim.opt.wildignore:append '*/node_modules/*'
vim.opt.suffixesadd:append '.vue,.ts,.js'
vim.cmd("set includeexpr=substitute(v:fname,'^@/','','g')")

vim.opt.showmatch = true

-- performance optimizations
vim.opt.lazyredraw = true
vim.opt.ttyfast = true

vim.opt.encoding = 'utf8'
vim.opt.expandtab = true

vim.opt.lbr = true
vim.opt.tw = 500
vim.opt.wrap = true
vim.opt.si = true
vim.opt.ai = true

vim.opt.title = true
vim.opt.titlelen = 0
vim.opt.titlestring = 'nvim %{expand("%:p")}'
vim.opt.autoread = true
