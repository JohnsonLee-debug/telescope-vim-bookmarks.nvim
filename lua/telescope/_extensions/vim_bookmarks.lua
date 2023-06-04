local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local entry_display = require('telescope.pickers.entry_display')
local conf = require('telescope.config').values
local make_entry = require('telescope.make_entry')

local utils = require('telescope.utils')

local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local bookmark_actions = require('telescope._extensions.vim_bookmarks.actions')

local function get_bookmarks(files, opts)
        opts = opts or {}
        local bookmarks = {}

        for _, file in ipairs(files) do
                for _, line in ipairs(vim.fn['bm#all_lines'](file)) do
                        local bookmark = vim.fn['bm#get_bookmark_by_line'](file, line)

                        local text = bookmark.annotation ~= "" and "Annotation: " .. bookmark.annotation or
                            bookmark.content
                        if text == "" then
                                text = "(empty line)"
                        end

                        local only_annotated = opts.only_annotated or false

                        if not (only_annotated and bookmark.annotation == "") then
                                table.insert(bookmarks, {
                                        filename = file,
                                        lnum = tonumber(line),
                                        col = 1,
                                        text = text,
                                        sign_idx = bookmark.sign_idx,
                                })
                        end
                end
        end

        return bookmarks
end

local function make_entry_from_bookmarks(opts)
        opts = opts or {}
        opts.tail_path = vim.F.if_nil(opts.tail_path, true)

        local displayer = entry_display.create {
                separator = "▏",
                items = {
                        { width = opts.width_line or 5 },
                        { width = opts.width_text or 60 },
                        { remaining = true }
                }
        }

        local make_display = function(entry)
                local filename
                if not opts.path_display then
                        filename = entry.filename
                        if opts.tail_path then
                                filename = utils.path_tail(filename)
                        elseif opts.shorten_path then
                                filename = utils.path_shorten(filename)
                        end
                end

                local line_info = { entry.lnum, "TelescopeResultsLineNr" }

                return displayer {
                        line_info,
                        entry.text:gsub(".* | ", ""),
                        filename,
                }
        end

        return function(entry)
                return {
                        valid = true,

                        value = entry,
                        ordinal = (
                                not opts.ignore_filename and filename
                                or ''
                        ) .. ' ' .. entry.text,
                        display = make_display,

                        filename = entry.filename,
                        lnum = entry.lnum,
                        col = 1,
                        text = entry.text,
                }
        end
end

local function make_bookmark_picker(filenames, opts)
        opts = opts or {}

        local make_finder = function()
                local bookmarks = get_bookmarks(filenames, opts)

                if vim.tbl_isempty(bookmarks) then
                        print("No bookmarks!")
                        return
                end

                return finders.new_table {
                        results = bookmarks,
                        entry_maker = make_entry_from_bookmarks(opts),
                }
        end

        local initial_finder = make_finder()
        if not initial_finder then return end

        pickers.new(opts, {
                prompt_title = opts.prompt_title or "vim-bookmarks",
                finder = initial_finder,
                previewer = conf.qflist_previewer(opts),
                sorter = conf.generic_sorter(opts),

                attach_mappings = function(prompt_bufnr, map)
                        local refresh_picker = function()
                                local new_finder = make_finder()
                                if new_finder then
                                        action_state.get_current_picker(prompt_bufnr):refresh(make_finder())
                                else
                                        actions.close(prompt_bufnr)
                                end
                        end
                        local function bookmark_save_file(file)
                                if vim.g.bookmark_manage_per_buffer == 1 then
                                        return vim.fn['g:BMBufferFileLocation'](file) or
                                            vim.loop.cwd() .. '/.vim-bookmarks'
                                elseif vim.g.bookmark_save_per_working_dir == 1 then
                                        return vim.fn['g:BMWorkDirFileLocation']() or vim.loop.cwd() .. '/.vim-bookmarks'
                                end
                                return vim.g.bookmark_auto_save_file
                        end
                        local post = function()
                                vim.fn['BookmarkSave'](bookmark_save_file(vim.g.bm_current_file), 1)
                                refresh_picker()
                        end
                        bookmark_actions.delete_selected:enhance { post = post }
                        bookmark_actions.delete_at_cursor:enhance { post = post }
                        bookmark_actions.delete_all:enhance { post = post }
                        bookmark_actions.delete_selected_or_at_cursor:enhance { post = post }
                        for _, mode in pairs({ "i", "n" }) do
                                for key, action in pairs(opts.mappings[mode] or {}) do
                                        map(mode, key, action)
                                end
                        end

                        return true
                end
        })
            :find()
end

-- default config
local all_config = {
        hide_filename = true,
        tail_path = require('telescope.config').tail_path and true,
        shorten_path = true,
        prompt_title = 'vim-bookmarks',
        width_line = 5,
        width_text = 60,
        only_annotated = false,
        mappings = {}
}
local current_config = {
        hide_filename = false,
        tail_path = require('telescope.config').tail_path and true,
        shorten_path = true,
        prompt_title = 'vim-bookmarks',
        width_line = 5,
        width_text = 60,
        only_annotated = false,
        mappings = {}
}

local all = function()
        make_bookmark_picker(vim.fn['bm#all_files'](), all_config)
end

local current_file = function()
        local opts = vim.tbl_extend('keep', current_config, { path_display = true })

        make_bookmark_picker({ vim.fn.expand('%:p') }, opts)
end

return require('telescope').register_extension {
        setup = function(extension_config, telescope_config)
                if extension_config.all ~= nil then
                        all_config = vim.tbl_extend("force", all_config, extension_config.all)
                end
                if extension_config.current ~= nil then
                        current_config = vim.tbl_extend("force", current_config, extension_config.all)
                end
                extension_config.all = nil
                extension_config.current = nil
                all_config = vim.tbl_extend("force", all_config, extension_config)
                current_config = vim.tbl_extend("force", current_config, extension_config)
        end,
        exports = {
                -- Default when to argument is given, i.e. :Telescope vim_bookmarks
                vim_bookmarks = all,

                all = all,
                current_file = current_file,
                actions = bookmark_actions
        }
}
