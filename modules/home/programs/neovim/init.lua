-- Set the leader button
vim.g.mapleader = " "

-- from lua/
require("functions")


-----------------------------------------------
-- General settings
-----------------------------------------------
vim.opt.autoindent = true                -- take indent for new line from previous line
vim.opt.smartindent = true               -- enable smart indentation
vim.opt.autoread = true                  -- reload file if the file changes on the disk
vim.opt.autowrite = true                 -- write when switching buffers
vim.opt.autowriteall = true              -- write on :quit
vim.opt.clipboard = "unnamedplus"
vim.opt.colorcolumn = "81"               -- highlight the 80th column as an indicator
vim.opt.cursorline = true                -- highlight the current line for the cursor
vim.opt.expandtab = true                 -- expands tabs to spaces
vim.opt.list = true                      -- show trailing whitespace
vim.opt.listchars = { tab = "!·", trail = "·" }
vim.opt.spell = false                    -- disable spelling
vim.opt.swapfile = false                 -- disable swapfile usage
vim.opt.wrap = false
vim.opt.errorbells = false               -- No bells!
vim.opt.visualbell = false               -- I said, no bells!
vim.opt.number = true                    -- show number ruler
vim.opt.relativenumber = true            -- show relative numbers in the ruler
vim.opt.ruler = true
vim.opt.formatoptions = "tcqronj"        -- set vims text formatting options
vim.opt.softtabstop = 2
vim.opt.tabstop = 2
vim.opt.title = true     -- let vim set the terminal title
vim.opt.diffopt:append { "iwhite" }
vim.opt.diffopt:append { "algorithm:patience" }
vim.opt.diffopt:append { "indent-heuristic" }
-- have a fixed column for the diagnostics to appear in this removes the jitter when warnings/errors flow in
vim.opt.signcolumn = "yes"
vim.opt.foldlevelstart = 99
vim.opt.wildignore:append { "*.so,*.swp,*.zip,*.idx,*.orig,*.rej" }


-- Enable mouse if possible
if vim.fn.has('mouse') then
  vim.opt.mouse = "a"
end

-- Remap colon to semicolumn. Avoids pressing shift.
l_nnoremap(";", ":")

-- Turn on fuzzy path search even if a file is in a nested directory
vim.opt.path:append { "**" }

-- Autosave buffers before leaving them
vim.api.nvim_create_autocmd("BufLeave", {
  pattern = { "*" },
  callback = function()
    vim.cmd("silent! wa")
  end,
})

-- Remove trailing white spaces on save
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*" },
  callback = function(args)
    vim.cmd([[silent! %s/\s\+$//e]])

    -- Format on save with 200ms timeout, only when a language server can format this buffer
    if #vim.lsp.get_clients({ bufnr = args.buf, method = "textDocument/formatting" }) > 0 then
      vim.lsp.buf.format({ bufnr = args.buf, timeout_ms = 200 })
    end
  end,
})

-- Center the screen quickly
l_nnoremap("<space>", "zz")

------------------------------------------------
-- Colors
------------------------------------------------
vim.cmd("colorscheme modus")
vim.opt.background = "dark"

-- Override the search highlight color with a combination that is easier to
-- read. The default PaperColor is dark green backgroun with black foreground.
--
-- Reference:
-- - http://vim.wikia.com/wiki/Xterm256_color_names_for_console_Vim
-- highlight Search guibg=DeepPink4 guifg=White ctermbg=53 ctermfg=White

-- Toggle background with <leader>bg
l_map("<leader>bg", ":let &background = (&background == 'dark' ? 'light' : 'dark')<CR>")

------------------------------------------------
-- Searching
------------------------------------------------
vim.opt.incsearch = true -- move to match as you type the search query
vim.opt.hlsearch = true  -- highlight search results

-- Clear search highlights
l_map("<leader>c", ":nohlsearch<CR>")

-- These mappings will make it so that going to the next one in a search will
-- center on the line it's found in.
l_nnoremap("n", "nzzzv")
l_nnoremap("N", "Nzzzv")

----------------------------------------------
-- Navigation
----------------------------------------------
-- Disable arrow keys
l_nnoremap("<Up>", "")
l_nnoremap("<Down>", "")
l_nnoremap("<Left>", "")
l_nnoremap("<Right>", "")

-- Move between buffers with Shift + arrow key...
l_nnoremap("<S-Left>", ":bprevious<CR>")
l_nnoremap("<S-Right>", ":bnext<CR>")

-- ... but skip the quickfix when navigating
vim.api.nvim_create_augroup("qf", { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = "qf",
  pattern = "qf",
  callback = function()
    vim.opt_local.buflisted = false
  end,
})

-- Fix some common typos
vim.keymap.set('ca', 'W!', 'w!')
vim.keymap.set('ca', 'W!', 'w!')
vim.keymap.set('ca', 'Q!', 'q!')
vim.keymap.set('ca', 'Qall!', 'qall!')
vim.keymap.set('ca', 'Wq', 'wq')
vim.keymap.set('ca', 'Wa', 'wa')
vim.keymap.set('ca', 'wQ', 'wq')
vim.keymap.set('ca', 'WQ', 'wq')
vim.keymap.set('ca', 'W', 'w')
vim.keymap.set('ca', 'Q', 'q')
vim.keymap.set('ca', 'Qall', 'qall')

------------------------------------------------
-- Hotkeys
------------------------------------------------
l_map("<C-p>", ":Files<CR>")
l_nmap("<leader>;", ":Buffers<CR>")

------------------------------------------------
-- Splits
------------------------------------------------
-- Create horizontal splits below the current window
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Creating splits
l_nnoremap("<leader>v", ":vsplit<CR>")
l_nnoremap("<leader>h", ":split<CR>")

-- Closing splits
l_nnoremap("<leader>q", ":close<CR>")

-- Jump to last edit position on opening file
vim.api.nvim_create_autocmd('BufReadPost', {
  callback = function()
    local filepath = vim.fn.expand('%:p')
    if filepath:match('/%.git/') then return end -- Skip files in .git

    local last_pos = vim.fn.line([['"]])
    local total_lines = vim.fn.line('$')

    if last_pos > 1 and last_pos <= total_lines then
      vim.cmd([[normal! g`"]])
    end
  end,
})

-----------------------------------------------
-- Language: Bash, Gitconfig, Make
-----------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sh", "gitconfig", "make" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.expandtab = false
  end,
})

-----------------------------------------------
-- Language: CSS, Fish, HTML, Javascript, JSON, SQL, TOML, YAML
-----------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "css", "fish", "html", "javascript", "json", "proto", "sql", "toml", "yaml" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.expandtab = true
  end,
})

-----------------------------------------------
-- Language: C++, C, Python, Lua, Vimscript
-----------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "cpp", "c", "python", "lua", "vim" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.expandtab = true
  end,
})

-----------------------------------------------
-- Language: Go
-----------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.expandtab = false
  end,
})

-----------------------------------------------
-- Language: Gitcommit
-----------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "gitcommit" },
  callback = function()
    vim.opt_local.textwidth = 80
    vim.opt_local.spell = true
  end,
})

-----------------------------------------------
-- Language: Rust
-----------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "rust" },
  callback = function(args)
    local map = function(lhs, rhs)
      vim.keymap.set('n', lhs, rhs, { buffer = args.buf, silent = true })
    end
    map("<leader>rf", function() vim.lsp.buf.format() end)
    map("<leader>rc", ":RustLsp flyCheck<CR>") -- cargo clippy (see check.command below)
    map("<leader>rr", ":RustLsp runnables<CR>")
    map("<leader>rt", ":RustLsp testables<CR>")
    map("<leader>rd", vim.lsp.buf.definition)
    map("<leader>rs", ":vsplit<CR>:lua vim.lsp.buf.definition()<CR>")
    map("<leader>rx", ":RustLsp openDocs<CR>")
  end,
})

vim.opt.completeopt = { "menuone", "noinsert", "noselect" }
-- Avoid showing extra messages when using completion
vim.opt.shortmess:append { c = true }

-- Enable diagnostics
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  update_in_insert = true,
  underline = false,
  severity_sort = true,
  float = {
    border = 'rounded',
    source = true,
    header = '',
    prefix = '',
  },
})


-- 100ms of no cursor movement triggers CursorHold
vim.opt.updatetime = 100
-- Show diagnostic popup on cursor hold
vim.api.nvim_create_autocmd("CursorHold", {
  pattern = "*",
  callback = function()
    vim.diagnostic.open_float(nil, { focusable = false })
  end,
})

-- Goto previous/next diagnostic warning/error
l_nnoremap_callback("g[", "", function() vim.diagnostic.jump({ count = -1, float = true }) end)
l_nnoremap_callback("g]", "", function() vim.diagnostic.jump({ count = 1, float = true }) end)


-- Code navigation shortcuts
l_nnoremap_callback("<C-]>", "", vim.lsp.buf.definition)
l_nnoremap_callback("K", "", vim.lsp.buf.hover)
l_nnoremap_callback("gD", "", vim.lsp.buf.implementation)
l_nnoremap_callback("<C-k>", "", vim.lsp.buf.signature_help)
l_nnoremap_callback("1gD", "", vim.lsp.buf.type_definition)
l_nnoremap_callback("g0", "", vim.lsp.buf.document_symbol)
l_nnoremap_callback("gW", "", vim.lsp.buf.workspace_symbol)
l_nnoremap_callback("gd", "", vim.lsp.buf.declaration)
l_nnoremap_callback("ga", "", vim.lsp.buf.code_action)


-- Setup completion
local cmp = require 'cmp'
cmp.setup({
  snippet = {
    expand = function(args)
      vim.fn["vsnip#anonymous"](args.body)
    end,
  },
  mapping = {
    ['<C-p>'] = cmp.mapping.select_prev_item(),
    ['<C-n>'] = cmp.mapping.select_next_item(),
    ['<C-d>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.close(),
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },
    ['<Tab>'] = function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      else
        fallback()
      end
    end,
    ['<S-Tab>'] = function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      else
        fallback()
      end
    end,
  },
  sources = {
    { name = "path" },
    { name = 'nvim_lsp',               keyword_length = 3 }, -- from language server
    { name = 'nvim_lsp_signature_help' },                    -- display function signatures with current parameter emphasized
    { name = 'nvim_lua',               keyword_length = 2 }, -- complete neovim's Lua runtime API such vim.lsp.*
    { name = 'buffer',                 keyword_length = 2 }, -- source current buffer
    { name = "vsnip" },
    { name = 'calc' },                                       -- source for math calculation
  },
  window = {
    completion = cmp.config.window.bordered(),
    documentation = cmp.config.window.bordered(),
  },
  formatting = {
    fields = { 'menu', 'abbr', 'kind' },
    format = function(entry, item)
      local menu_icon = {
        nvim_lsp = 'λ',
        vsnip = '⋗',
        buffer = 'Ω',
        path = '🖫',
      }
      item.menu = menu_icon[entry.source.name]
      return item
    end,
  },
})

-- Treesitter highlighting; parsers are installed by Nix.
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    local max_filesize = 100 * 1024 -- 100 KB
    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
    if ok and stats and stats.size > max_filesize then
      return
    end
    pcall(vim.treesitter.start, args.buf)
  end,
})


-- FloaTerm configuration
l_nmap("<leader>ft", ":FloatermNew --name=myfloat --height=0.8 --width=0.7 --autoclose=2 fish <CR> ")
l_nmap("t", ":FloatermToggle myfloat<CR>")
l_tmap("<Esc>", "<C-\\><C-n>:q<CR>")


-----------------------------------------------
-- Plugin: rbgrouleff/bclose.vim
-----------------------------------------------
-- Close buffers
l_nnoremap("<leader>w", ":Bclose<CR>")

-- Close quickfix
l_nnoremap("<leader>b", ":cclose<CR>")

-- Language servers are installed by Nix (or come from the project's toolchain, e.g. clangd).
-- Clangd config
vim.lsp.config('clangd', {
  cmd = { "clangd", "--background-index", "--header-insertion=never", '--header-insertion-decorators', '--clang-tidy' }
})

vim.lsp.config('ts_ls', {
  settings = {
    completions = {
      completeFunctionCalls = true
    }
  },
  on_attach = function(client, bufnr)
    client.server_capabilities.documentFormattingProvider = true;
  end,
})

-- Gopls setup
vim.lsp.config('gopls', {
  cmd = { "gopls" },
  filetypes = { "go", "gomod", "gowork", "gotmpl" },
  settings = {
    gopls = {
      experimentalPostfixCompletions = true,
      analyses                       = {
        unusedparams = true,
        unreachable = true,
        shadow = true,
      },
      staticcheck                    = true,
      gofumpt                        = true,
    }
  },
})

-- Lua, aware of neovim's runtime so editing this config gets completion
vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = {
        checkThirdParty = false,
        library = { vim.env.VIMRUNTIME },
      },
    },
  },
})

vim.lsp.enable({ "clangd", "ts_ls", "gopls", "lua_ls" })

-- Rust Analyzer setup (rust-analyzer comes from Nix)
vim.g.rustaceanvim = {
  server = {
    default_settings = {
      ['rust-analyzer'] = {
        check = {
          command = "clippy",
        },
        rustfmt = {
          rangeFormatting = { enable = true },
        },
        inlayHints = {
          locationLinks = false,
        },
        imports = {
          granularity = { group = "crate" },
          prefix = "crate",
        },
        cargo = {
          buildScripts = { enable = true },
          allFeatures = true,
        },
        procMacro = {
          enable = true,
        },
      },
    },
  },
}
