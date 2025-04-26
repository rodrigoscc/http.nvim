local utils = require("http-nvim.utils")
local url = require("http-nvim.requests").url

local M = {}

local function minify_json(json_body)
    return vim.json.encode(vim.json.decode(json_body))
end

local function get_curl_user_flags(request)
    if request.local_context["request.curl_flags"] ~= nil then
        return vim.split(request.local_context["request.curl_flags"], " ")
    end

    return {}
end

---Build curl command arguments to run request
---@param request http.Request
M.build_command = function(request)
    local command = {
        "curl",
        "--include",
        "--location",
        "--no-progress-meter",
        "--write-out",
        "\n%{time_total}\n%{size_header}",
    }

    if request.body ~= nil then
        local body = request.body

        local file_type = utils.get_content_type(request.headers)
        if file_type == "application/json" then
            -- minifying just to minimize network load
            body = minify_json(body)
        end

        table.insert(command, "--data")
        table.insert(command, body)
    end

    for name, value in pairs(request.headers) do
        table.insert(command, "--header")
        table.insert(command, name .. ": " .. value)
    end

    table.insert(command, "--request")
    table.insert(command, request.method)

    table.insert(command, url(request))

    local curl_user_flags = get_curl_user_flags(request)

    if
        vim.list_contains(curl_user_flags, "--write-out")
        or vim.list_contains(curl_user_flags, "-w")
    then
        error(
            "You cannot set the --write-out flag, http.nvim expects a specific format.",
            0
        )
    end

    vim.list_extend(command, curl_user_flags)

    return command
end

return M
