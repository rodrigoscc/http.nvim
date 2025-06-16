local utils = require("http-nvim.utils")
local request_id = require("http-nvim.requests").id
local keymaps = require("http-nvim.keymaps")
local config = require("http-nvim.config")

---@class http.Buffer
---@field bufnr integer
---@field type http.BufferType

local M = {}

M.show_in_floating = function(contents)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, { contents })

    local win = vim.api.nvim_open_win(buf, false, {
        relative = "cursor",
        width = math.max(#contents, 8),
        height = 1,
        col = 0,
        row = 1,
        anchor = "NW",
        style = "minimal",
        border = "single",
    })

    vim.api.nvim_create_autocmd({ "WinLeave", "CursorMoved" }, {
        callback = function()
            if vim.api.nvim_win_is_valid(win) then -- Needed in case window is already closed.
                vim.api.nvim_win_close(win, false)
            end
        end,
        once = true,
        buffer = 0,
    })
end

local function headers_to_lines(status_line, headers)
    local lines = { status_line }
    for key, value in pairs(headers) do
        table.insert(lines, key .. ": " .. value)
    end

    return lines
end

local function body_to_lines(response)
    return vim.split(response.body, "\n", { trimempty = true })
end

local function sanitize_time_total(time_total)
    return math.floor(time_total * 100) / 100 -- keep two decimal places
end

---Compute the left side of the winbar for this request and response
---@param request http.Request
---@param response http.Response
M.get_left_winbar = function(request, response)
    local id = request_id(request)

    local status_highlight = config.highlights.success_code
    if response.status_code >= 400 and response.status_code <= 599 then
        status_highlight = config.highlights.error_code
    end

    local total_time = ""
    if response.total_time then
        total_time = "(took "
            .. sanitize_time_total(response.total_time)
            .. "s)"
    end

    return string.format(
        "%%#%s# %s %%* %%<%s %s",
        status_highlight,
        response.status_code,
        id,
        total_time
    )
end

---Compute the winbar when there's an error running the curl command
---@param request http.Request
---@param raw http.Raw
---@return string
local function get_error_winbar(request, raw)
    local id = request_id(request)

    local status_highlight = config.highlights.error_code

    return string.format("%%#%s# %s %%* %%<%s", status_highlight, "ERROR", id)
end

M.present_command = function(command)
    return vim.iter(ipairs(command))
        :map(function(i, p)
            if i == 1 then
                -- Do not escape executable.
                return p
            end

            return vim.fn.shellescape(p)
        end)
        :join(" ")
end

M.printable_command = function(command)
    return vim.iter(ipairs(command))
        :map(function(i, p)
            if i == 1 then
                -- Do not escape executable.
                return p
            end

            local escaped = vim.fn.shellescape(p)
            local result, _ = string.gsub(escaped, "\n", "\r")
            return result
        end)
        :join(" ")
end

--- Formats response body in the given buffer.
---@param response_buf integer
---@param response_body string
---@param response_filetype string
local function format_response(response_buf, response_body, response_filetype)
    if response_filetype == "json" and vim.fn.executable("jq") then
        vim.system(
            { "jq", "--sort-keys", "--indent", "4", "." },
            { text = true, stdin = response_body },
            function(obj)
                if obj.code == 0 then
                    local formatted_lines =
                        vim.split(obj.stdout, "\n", { trimempty = true })

                    vim.schedule(function()
                        vim.api.nvim_buf_set_lines(
                            response_buf,
                            0,
                            -1,
                            true,
                            formatted_lines
                        )
                    end)
                end
            end
        )
    end
end

---@enum http.BufferType
local Buffer = {
    Body = "body",
    Headers = "headers",
    Raw = "raw",
}

local function create_body_buffer(request, response)
    local body_file_type = utils.get_body_file_type(response.headers)
    local body_lines = body_to_lines(response)

    local body_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(body_buf, 0, -1, true, body_lines)

    -- Set filetype after adding lines for better performance with large bodies.
    if config.options.use_compound_filetypes then
        vim.api.nvim_set_option_value(
            "filetype",
            "httpnvim." .. body_file_type,
            { buf = body_buf }
        )
    else
        vim.api.nvim_set_option_value(
            "filetype",
            body_file_type,
            { buf = body_buf }
        )
    end

    format_response(body_buf, response.body, body_file_type)

    return body_buf
end

local function create_headers_buffer(request, response)
    local header_lines =
        headers_to_lines(response.status_line, response.headers)

    local headers_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(headers_buf, 0, -1, false, header_lines)

    if config.options.use_compound_filetypes then
        vim.api.nvim_set_option_value(
            "filetype",
            "httpnvim.http",
            { buf = headers_buf }
        )
    else
        vim.api.nvim_set_option_value("filetype", "http", { buf = headers_buf })
    end

    return headers_buf
end

local function create_raw_buffer(request, response, raw)
    local curl_command = M.printable_command(raw.command)

    local raw_lines = {}
    vim.list_extend(raw_lines, { curl_command, "" })
    vim.list_extend(raw_lines, raw.output)

    local raw_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(raw_buf, 0, -1, true, raw_lines)

    if config.options.use_compound_filetypes then
        vim.api.nvim_set_option_value(
            "filetype",
            "httpnvim.text",
            { buf = raw_buf }
        )
    else
        vim.api.nvim_set_option_value("filetype", "text", { buf = raw_buf })
    end

    return raw_buf
end

--- Convert text into a title.
---@param text string
---@return string
local function title(text)
    local new_text = text:gsub("^%l", string.upper)
    return new_text
end

---Computes the right side of the winbar depending on the active buffer type.
---@param buffer_type http.BufferType
---@return string
M.get_right_winbar = function(buffer_type)
    local winbar = ""

    for _, buffer in ipairs(config.options.buffers) do
        local is_current_buffer = buffer[1] == buffer_type
        if is_current_buffer then
            winbar = winbar .. "%#@comment.info# " .. title(buffer[1]) .. " %*"
        else
            winbar = winbar .. "%#@comment# " .. title(buffer[1]) .. " %*"
        end
    end

    return winbar
end

---Display http response in buffers
---@param request http.Request
---@param response http.Response
---@param raw http.Raw
local function create_buffers(request, response, raw)
    local left_winbar = M.get_left_winbar(request, response)

    local body_buf = create_body_buffer(request, response)
    local headers_buf = create_headers_buffer(request, response)
    local raw_buf = create_raw_buffer(request, response, raw)

    local body_winbar = left_winbar .. "%=" .. M.get_right_winbar(Buffer.Body)
    local headers_winbar = left_winbar
        .. "%="
        .. M.get_right_winbar(Buffer.Headers)
    local raw_winbar = left_winbar .. "%=" .. M.get_right_winbar(Buffer.Raw)

    if config.options.builtin_winbar then
        vim.api.nvim_create_autocmd("BufWinEnter", {
            buffer = body_buf,
            callback = function()
                local win = vim.api.nvim_get_current_win()
                vim.wo[win][0].winbar = body_winbar
            end,
            once = true,
        })

        vim.api.nvim_create_autocmd("BufWinEnter", {
            buffer = headers_buf,
            callback = function()
                local win = vim.api.nvim_get_current_win()
                vim.wo[win][0].winbar = headers_winbar
            end,
            once = true,
        })

        vim.api.nvim_create_autocmd("BufWinEnter", {
            buffer = raw_buf,
            callback = function()
                local win = vim.api.nvim_get_current_win()
                vim.wo[win][0].winbar = raw_winbar
            end,
            once = true,
        })
    end

    ---@type table<http.BufferType, integer>
    local buffers_map = {
        [Buffer.Body] = body_buf,
        [Buffer.Headers] = headers_buf,
        [Buffer.Raw] = raw_buf,
    }

    ---@type http.Buffer[]
    local buffers = {}

    for _, buffer in ipairs(config.options.buffers) do
        local buffer_name = buffer[1]
        local bufnr = buffers_map[buffer_name]

        table.insert(buffers, { bufnr = bufnr, type = buffer_name })

        for lhs, rhs in pairs(buffer.keys) do
            if type(rhs) == "string" then
                rhs = keymaps.builtin[rhs](buffers_map, {})
            elseif type(rhs) == "table" then
                rhs = keymaps.builtin[rhs[1]](buffers_map, rhs.opts or {})
            end

            vim.keymap.set("n", lhs, rhs, { buffer = bufnr })
        end
    end

    return buffers
end

local function create_buffers_from_error(request, response, raw)
    local bufnr = create_raw_buffer(request, response, raw)
    local winbar = get_error_winbar(request, raw)

    if config.options.builtin_winbar then
        vim.api.nvim_create_autocmd("BufWinEnter", {
            buffer = bufnr,
            callback = function()
                local win = vim.api.nvim_get_current_win()
                vim.wo[win][0].winbar = winbar
            end,
            once = true,
        })
    end

    ---@type table<http.BufferType, integer>
    local buffers_map = {
        [Buffer.Raw] = bufnr,
    }
    ---@type http.Buffer[]
    local buffers = {}

    table.insert(buffers, { bufnr = bufnr, type = Buffer.Raw })

    local buffer_opts = vim.iter(config.options.buffers)
        :filter(function(v)
            return v[1] == Buffer.Raw
        end)
        :next()

    if buffer_opts == nil then
        return {}, {}
    end

    for lhs, rhs in pairs(buffer_opts.keys) do
        if type(rhs) == "string" then
            rhs = keymaps.builtin[rhs](buffers_map, {})
        elseif type(rhs) == "table" then
            rhs = keymaps.builtin[rhs[1]](buffers_map, rhs.opts or {})
        end

        vim.keymap.set("n", lhs, rhs, { buffer = bufnr })
    end

    return buffers
end

M.create_buffers = function(request, response, raw)
    if response ~= nil then
        return create_buffers(request, response, raw)
    else
        return create_buffers_from_error(request, response, raw)
    end
end

M.show_buffer = function(buffer)
    vim.api.nvim_open_win(buffer.bufnr, false, config.options.win_config)
end

return M
