local config = require("http-nvim.config")

local M = {}

M.builtin = {
    next_buffer = function(buffers, opts)
        return function()
            local win = vim.api.nvim_get_current_win()

            local http = require("http-nvim.http")

            local current_buffer_type =
                http:get_buffer_type(vim.api.nvim_get_current_buf())

            assert(
                current_buffer_type ~= nil,
                "Current buffer must be a HTTP buffer"
            )

            local current_buffer_index = vim.iter(config.options.buffers)
                :enumerate()
                :filter(function(_, buffer)
                    return buffer[1] == current_buffer_type
                end)
                :map(function(i)
                    return i
                end)
                :next()

            if current_buffer_index == nil then
                return
            end

            local next_buffer_index = current_buffer_index + 1
            if next_buffer_index > #config.options.buffers then
                next_buffer_index = 1
            end

            local next_buffer_type =
                config.options.buffers[next_buffer_index][1]
            local next_buffer = buffers[next_buffer_type]

            if next_buffer ~= nil then
                vim.api.nvim_win_set_buf(win, next_buffer)
            end
        end
    end,
    switch_buffer = function(buffers, opts)
        return function()
            local win = vim.api.nvim_get_current_win()
            local next_buffer = buffers[opts.buffer]

            if next_buffer == nil then
                return
            end

            vim.api.nvim_win_set_buf(win, next_buffer)
        end
    end,
    rerun = function(buffers, opts)
        return function()
            local http = require("http-nvim.http")

            local buffer_request = http:get_buffer_request()
            if buffer_request == nil then
                return
            end

            http:run(buffer_request)
        end
    end,
    close = function(buffers, opts)
        return function()
            vim.cmd.close()
        end
    end,
}

return M
