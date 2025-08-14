return {
  'vimwiki/vimwiki',
  init = function ()
    vim.g.vimwiki_list = {
      {
        path='$HOME'..'/wiki',
        syntax='markdown',
        ext='.md',
        auto_tags=1,
        auto_diary_index=1
      }
    }
    vim.g.wiki_root = '$HOME'..'/wiki'
    vim.g.vimwiki_markdown_link_ext = 1
  end
}