local utils = require("http-nvim.utils")
local request_id = require("http-nvim.requests").id
local status_namespace = vim.api.nvim_create_namespace("http-nvim-status")
local config = require("http-nvim.config")

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

---Compute the winbar for this request
---@param request http.Request
---@param response http.Response
local function get_winbar(request, response)
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

            local escaped = vim.fn.shellescape(p)
            local result, _ = string.gsub(escaped, "\n", "\\n")
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

local function setup_buffer(buf, buftype, filetype)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'http-buf-' .. buftype)
    vim.api.nvim_buf_call(buf, function()
        vim.cmd('syntax on')
        vim.cmd('setlocal syntax=' .. filetype)
    end)
end

---Display http response in buffers
---@param request http.Request
---@param response http.Response
---@param raw http.Raw
local function show_response(request, response, raw)
    local winbar = get_winbar(request, response)

    local body_winbar = winbar
        .. "%=%#@comment.info# Body %*%#@comment# Headers %*%#@comment# Raw %*"
    local headers_winbar = winbar
        .. "%=%#@comment# Body %*%#@comment.info# Headers %*%#@comment# Raw %*"
    local raw_winbar = winbar
        .. "%=%#@comment# Body %*%#@comment# Headers %*%#@comment.info# Raw %*"

    local header_lines =
        headers_to_lines(response.status_line, response.headers)

    local body_file_type = utils.get_body_file_type(response.headers)
    local body_lines = body_to_lines(response)

    local body_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(body_buf, 0, -1, true, body_lines)
    -- Set filetype after adding lines for better performance with large bodies.
    setup_buffer(body_buf, 'body', body_file_type)

    local win =
        vim.api.nvim_open_win(body_buf, false, config.options.win_config)

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = body_buf })

    local headers_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(headers_buf, 0, -1, false, header_lines)
    setup_buffer(headers_buf, 'headers', 'http')

    local curl_command = M.present_command(raw.command)

    local raw_lines = {}
    vim.list_extend(raw_lines, { curl_command, "" })
    vim.list_extend(raw_lines, raw.output)

    local raw_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(raw_buf, 0, -1, true, raw_lines)
    setup_buffer(raw_buf, 'raw', 'text')

    vim.keymap.set("n", "<Tab>", function()
        vim.api.nvim_win_set_buf(win, headers_buf)
        vim.wo[win][headers_buf].winbar = headers_winbar
        -- setup_buffer(headers_buf, 'headers', 'http')
    end, { buffer = body_buf })

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = headers_buf })
    vim.keymap.set("n", "<Tab>", function()
        vim.api.nvim_win_set_buf(win, raw_buf)
        vim.wo[win][raw_buf].winbar = raw_winbar
        -- setup_buffer(raw_buf, 'raw', 'text')
    end, { buffer = headers_buf })

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = raw_buf })
    vim.keymap.set("n", "<Tab>", function()
        vim.api.nvim_win_set_buf(win, body_buf)
        -- setup_buffer(body_buf, 'body', 'html')
    end, { buffer = raw_buf })

    vim.wo[win][body_buf].winbar = body_winbar

    format_response(body_buf, response.body, body_file_type)
end

local function show_raw_output(request, raw)
    local winbar = get_error_winbar(request, raw)

    local curl_command = M.present_command(raw.command)

    local raw_lines = {}
    vim.list_extend(raw_lines, { curl_command, "" })
    vim.list_extend(raw_lines, raw.output)

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_option_value("filetype", "text", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, raw_lines)

    local win = vim.api.nvim_open_win(buf, false, config.options.win_config)
    vim.wo[win][buf].winbar = winbar

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = buf })
end

M.show = function(request, response, raw)
    if response ~= nil then
        show_response(request, response, raw)
    else
        show_raw_output(request, raw)
    end
end

---@enum http.RequestState
local State = {
    Running = "running",
    Finished = "finished",
    Error = "error",
}

local Icons = {
    [State.Running] = "󰄰",
    [State.Finished] = "󰪥",
    [State.Error] = "󰪥",
}

local Highlights = {
    [State.Running] = config.highlights.running,
    [State.Finished] = config.highlights.finished,
    [State.Error] = config.highlights.error,
}

---Set the request state
---@param request http.Request
---@param state http.RequestState
M.set_request_state = function(request, state)
    if request.source.type ~= "buffer" then
        return
    end

    local request_line, _, _, _ = request.node:range()

    local icon = Icons[state]
    local highlight = Highlights[state]

    local extmark_id = request_line + 1 -- +1 to avoid passing 0, it errors out

    local bufnr = request.source.route
    ---@cast bufnr integer

    vim.api.nvim_buf_set_extmark(bufnr, status_namespace, request_line, 0, {
        virt_text = { { icon, highlight } },
        id = extmark_id,
    })

    if state == State.Finished then
        vim.defer_fn(function()
            vim.api.nvim_buf_del_extmark(bufnr, status_namespace, extmark_id)
        end, 10000)
    end
end

return M
