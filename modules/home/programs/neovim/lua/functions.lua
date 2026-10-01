l_nnoremap = function(lhs, rhs)
    vim.keymap.set('n', lhs, rhs, { noremap = true, silent = true })
end

l_nnoremap_callback = function(lhs, rhs, callback)
    vim.keymap.set('n', lhs, rhs, { noremap = true, callback = callback, silent = true })
end

l_map = function(lhs, rhs)
    vim.keymap.set('', lhs, rhs, { noremap = false, silent = true })
end

l_map_callback = function(lhs, rhs, callback)
    vim.keymap.set('', lhs, rhs, { noremap = false, silent = true, callback = callback })
end

l_nmap = function(lhs, rhs)
    vim.keymap.set('n', lhs, rhs, { noremap = false, silent = true })
end

l_nmap_callback = function(lhs, rhs, callback)
    vim.keymap.set('n', lhs, rhs, { noremap = false, silent = true, callback = callback })
end


l_tmap = function(lhs, rhs)
    vim.keymap.set('t', lhs, rhs, { noremap = false, silent = true })
end

l_tmap_callback = function(lhs, rhs, callback)
    vim.keymap.set('t', lhs, rhs, { noremap = false, silent = true, callback = callback })
end
