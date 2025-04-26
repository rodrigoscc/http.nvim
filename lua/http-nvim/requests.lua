---@class http.Request
---@field method string
---@field url string
---@field query string?
---@field headers table
---@field body string?
---@field local_context table
---@field source http.Source
---@field start_range table
---@field end_range table
---@field context_start_row number?
---@field context_end_row number?

---@class http.Response
---@field ok boolean
---@field status_code number
---@field status_line string
---@field headers table
---@field body string
---@field total_time number?

---@class http.Raw
---@field command string[]
---@field output string[]

local M = {}

M.url = function(request)
    local request_url = request.url
    if request.query ~= nil then
        request_url = request_url .. "?" .. request.query
    end

    return request_url
end

---Get the identifier of a request
---@param request http.Request
---@return string
M.id = function(request)
    local title = request.local_context["request.title"]

    if title == nil then
        return request.method .. " " .. M.url(request)
    else
        return title
    end
end

return M
