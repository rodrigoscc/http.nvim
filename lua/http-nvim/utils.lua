local open = require("plenary.context_manager").open
local with = require("plenary.context_manager").with

local M = {}

local function create_file(filename, mode)
    local dir = vim.fs.dirname(filename)
    vim.fn.mkdir(dir, "p", "0o755")

    with(open(filename, "w+"), function(file)
        file:write("{}")
    end)
end

M.make_sure_file_exists = function(filename)
    local exists = vim.fn.findfile(filename) ~= ""
    if not exists then
        create_file(filename)
    end
end

M.format_if_jq_installed = function(json)
    if vim.fn.executable("jq") == 1 then
        return vim.fn.system(
            "jq --sort-keys --indent 4 '.' <<< '" .. json .. "'"
        )
    else
        return json
    end
end

M.get_content_type = function(content)
    return content.headers["Content-Type"] or content.headers["content-type"]
end

local DEFAULT_BODY_TYPE = "text"

M.get_body_file_type = function(headers)
    local body_file_type = DEFAULT_BODY_TYPE

    local content_type = headers["Content-Type"] or headers["content-type"]
    if content_type == nil then
        return body_file_type
    end

    if string.find(content_type, "application/json") then
        body_file_type = "json"
    elseif
        string.find(content_type, "application/xml")
        or string.find(content_type, "text/xml")
    then
        body_file_type = "xml"
    elseif string.find(content_type, "text/html") then
        body_file_type = "html"
    end

    return body_file_type
end

return M
