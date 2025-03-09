local utils = require("http-nvim.utils")

---@class http.Parser
local Parser = {}
Parser.__index = Parser

function Parser.new()
    local obj = setmetatable({}, Parser)
    return obj
end

---Parse raw response into http.Response object.
---@param raw_response string[]
---@return http.Response
function Parser:parse_response(raw_response)
    local headers_lines, body_lines, total_time =
        self:split_header_and_body(raw_response)

    local status_line = self:parse_status_line(headers_lines)
    local parsed_headers = self:parse_http_headers_lines(headers_lines)

    local body_joined = table.concat(body_lines, "\n")

    local parsed_status_code = self:parse_status_code(raw_response[1])

    ---@type http.Response
    local response = {
        status_code = parsed_status_code,
        status_line = status_line,
        body = body_joined,
        headers = parsed_headers,
        ok = parsed_status_code >= 200 and parsed_status_code <= 299,
        total_time = tonumber(total_time),
    }

    return response
end

function Parser:split_header_and_body(result)
    local last_line = result[#result] -- last line is the header size because of the --write-out option
    local header_size = tonumber(last_line)

    if header_size == nil then
        error("could not parse curl output, header size not found")
    end

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

function Parser:parse_status_line(headers_lines)
    local status_line = headers_lines[1]
    return status_line
end

function Parser:parse_status_code(status_code_line)
    local splits = vim.split(status_code_line, " ")

    return tonumber(splits[2])
end

function Parser:parse_http_headers_lines(headers_lines)
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

return { Parser = Parser }
