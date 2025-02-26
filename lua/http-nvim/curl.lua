local utils = require("http-nvim.utils")
local url = require("http-nvim.requests").url

local M = {}

local function minify_json(json_body)
    return vim.json.encode(vim.json.decode(json_body))
end

local function get_additional_args(request)
    if request.local_context["request.flags"] ~= nil then
        return vim.split(request.local_context["request.flags"], " ")
    end

    return {}
end

---Build curl command arguments to run request
---@param request http.Request
---@param content http.RequestContent
M.build_command = function(request, content)
    local command = {
        "curl",
        "--include",
        "--location",
        "--no-progress-meter",
        "--write-out",
        "\n%{time_total}\n%{size_header}",
    }

    if content.body ~= nil then
        local body = content.body

        local file_type = utils.get_content_type(content.headers)
        if file_type == "application/json" then
            -- minifying just to minimize network load
            body = minify_json(body)
        end

        table.insert(command, "--data")
        table.insert(command, body)
    end

    if content.headers ~= nil then
        for _, header in ipairs(content.headers) do
            table.insert(command, "--header")
            table.insert(command, header)
        end
    end

    table.insert(command, "--request")
    table.insert(command, request.method)

    table.insert(command, url(request))

    local additional_args = get_additional_args(request)
    vim.list_extend(command, additional_args)

    return command
end

return M
