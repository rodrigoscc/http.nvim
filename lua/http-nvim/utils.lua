local M = {}

M.format_if_jq_installed = function(json)
    if vim.fn.executable("jq") == 1 then
        json = vim.fn.shellescape(json)
        return vim.fn.system("jq --sort-keys --indent 4 '.' <<< " .. json)
    else
        return json
    end
end

M.get_content_type = function(headers)
    for name in pairs(headers) do
        if string.lower(name) == "content-type" then
            return headers[name]
        end
    end

    return nil
end

local DEFAULT_BODY_TYPE = "text"

M.get_body_file_type = function(headers)
    local body_file_type = DEFAULT_BODY_TYPE

    local content_type = M.get_content_type(headers)
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
