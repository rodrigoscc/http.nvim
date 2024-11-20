---@class http.Request
---@field method string
---@field url string
---@field query string?
---@field node TSNode
---@field local_context table
---@field source http.Source

---@class http.RequestContent
---@field headers string[]
---@field body string?
-- TODO: Should headers be parsed before getting here?

---@class http.Response
---@field ok boolean
---@field status_code number
---@field status_line string
---@field headers table
---@field body table
---@field total_time number?

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
