local ui = require("http-nvim.ui")
local utils = require("http-nvim.utils")
local url = require("http-nvim.requests").url
local log = require("http-nvim.log")

local M = {}

local function parse_http_headers_lines(headers_lines)
    local parsed_headers = {}
    for _, header_line in ipairs(headers_lines) do
        local is_a_header_line = not vim.startswith(header_line, "HTTP/")

        if is_a_header_line then
            local colon_pos = string.find(header_line, ":")

            if colon_pos ~= nil then
                local name = string.sub(header_line, 1, colon_pos - 1)
                local value = string.sub(header_line, colon_pos + 1)

                name = vim.trim(name)
                value = vim.trim(value)

                parsed_headers[name] = value
            else
                local name = vim.trim(header_line)
                parsed_headers[name] = ""
            end
        end
    end

    return parsed_headers
end

local function parse_status_line(headers_lines)
    local status_line = headers_lines[1]
    return status_line
end

local function parse_status_code(status_code_line)
    local splits = vim.split(status_code_line, " ")

    return tonumber(splits[2])
end

local function split_header_and_body(result)
    local last_line = result[#result] -- last line is the header size because of the --write-out option
    local header_size = tonumber(last_line)

    local total_time = result[#result - 1] -- total size is the line before the header size

    for index, line in ipairs(result) do
        header_size = header_size - #line - 2 -- new line characters \r\n

        if header_size <= 0 then
            local separation_line = index

            local headers_lines = vim.list_slice(result, 0, separation_line - 1) -- Exclude empty line
            local body_lines =
                vim.list_slice(result, separation_line + 1, #result - 2) -- Exclude time total, header size line, empty line

            return headers_lines, body_lines, total_time
        end
    end

    -- All the output is headers
    return vim.list_slice(result, 0, #result - 2), {}, total_time
end

---Parse vim.system() result and get http response from it
---@param output string[]
---@return http.Response
local function parse_response(output)
    local headers_lines, body_lines, total_time = split_header_and_body(output)

    local status_line = parse_status_line(headers_lines)
    local parsed_headers = parse_http_headers_lines(headers_lines)

    local parsed_body = ""
    local body_joined = table.concat(body_lines, "\n")

    local body_file_type = utils.get_body_file_type(parsed_headers)

    if body_file_type == "json" then
        parsed_body = vim.json.decode(body_joined)
    else
        parsed_body = body_joined
    end

    local parsed_status_code = parse_status_code(output[1])

    ---@type http.Response
    local response = {
        status_code = parsed_status_code,
        status_line = status_line,
        body = parsed_body,
        headers = parsed_headers,
        ok = true,
        total_time = tonumber(total_time),
    }

    return response
end

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
M.build_curl_command = function(request, content)
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

        local file_type = utils.get_content_type(content)
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

local function error_handler(err)
    log.fmt_error("Error parsing response %s\n" .. debug.traceback(), err)
end

M.on_exit_func = function(request, after_hook)
    return function(obj)
        local stdout = vim.split(obj.stdout, "\n")
        local stderr = vim.split(obj.stderr, "\n")
        local output = vim.list_extend(stdout, stderr)

        local response = nil
        local status_ok = obj.code == 0

        ---@type http.RequestState
        local state = "error"

        if status_ok then
            local status, result = xpcall(parse_response, error_handler, output)

            if status then
                response = result
            end

            state = "finished"
        end

        vim.schedule(function()
            ui.set_request_state(request, state)
        end)

        if after_hook == nil then
            vim.schedule(function()
                ui.show(request, response, output)
            end)
        else
            after_hook(request, response, output)
        end
    end
end

return M
