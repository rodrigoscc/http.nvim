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

local function body_to_lines(response, file_type)
    if file_type == "json" then
        local json_body = vim.fn.json_encode(response.body)
        local formatted_body = utils.format_if_jq_installed(json_body)
        return vim.split(formatted_body, "\n")
    end

    return vim.split(response.body, "\n")
end

local function sanitize_time_total(time_total)
    return math.floor(time_total * 100) / 100 -- keep two decimal places
end

---Display http response in buffers
---@param request http.Request
---@param response http.Response
local function show_response(request, response)
    local winbar = request_id(request)
    if response.total_time then
        winbar = winbar
            .. " (took "
            .. sanitize_time_total(response.total_time)
            .. "s)"
    end

    local header_lines =
        headers_to_lines(response.status_line, response.headers)

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_option_value("filetype", "http", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, header_lines)

    vim.cmd([[15split]])

    vim.api.nvim_set_current_buf(buf)

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = true })

    vim.opt_local.winbar = winbar .. " (1/2)"

    local body_file_type = utils.get_body_file_type(response.headers)
    local body_lines = body_to_lines(response, body_file_type)

    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_option_value("filetype", body_file_type, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, body_lines)

    vim.cmd([[vsplit]])

    vim.api.nvim_set_current_buf(buf)

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = true })

    vim.opt_local.winbar = winbar .. " (2/2)"
end

local function show_raw_output(request, stderr)
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_option_value("filetype", "text", { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, stderr)

    vim.cmd([[15split]])

    vim.api.nvim_set_current_buf(buf)

    vim.keymap.set("n", "q", vim.cmd.close, { buffer = true })
end

M.show = function(request, response, output)
    if response ~= nil then
        show_response(request, response)
    else
        show_raw_output(request, output)
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
