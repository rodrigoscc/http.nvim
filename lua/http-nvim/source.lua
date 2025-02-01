local queries = require("http-nvim.queries")

local open = require("plenary.context_manager").open
local with = require("plenary.context_manager").with
local tree_sitter_nodes = require("http-nvim.constants").tree_sitter_nodes

local function extract_method_and_url(method_url)
    local valid_methods = {
        "GET",
        "POST",
        "PUT",
        "PATCH",
        "DELETE",
        "OPTIONS",
        "HEAD",
        "CONNECT",
        "TRACE",
    }

    local space_separated = vim.split(method_url, " ")

    local method = space_separated[1]
    local url = method_url:sub(#method + 2) -- Url is after method string and a space.

    local starts_with_method = vim.tbl_contains(valid_methods, method)

    if not starts_with_method then
        method = "GET"
        url = method_url
    end

    return method, url
end

---@enum http.SourceType
local source_type = {
    BUFFER = "buffer",
    FILE = "file",
}

---@class http.Source
---@field type http.SourceType
---@field repr string|integer
---@field route string|integer
local Source = {}
Source.__index = Source

function Source.new(type, repr)
    local route = repr

    if type == source_type.FILE then
        route = repr
        repr = with(open(repr, "r"), function(reader)
            return reader:read("*a")
        end)
    end

    local obj = setmetatable({
        type = type,
        repr = repr,
        route = route,
    }, Source)

    return obj
end

function Source:get_parser()
    if self.type == source_type.BUFFER then
        return vim.treesitter.get_parser(self.repr, "http2")
    elseif self.type == source_type.FILE then
        return vim.treesitter.get_string_parser(self.repr, "http2")
    end
end

function Source:get_tree()
    local parser = self:get_parser()
    local tree = parser:parse()[1]

    if tree == nil then
        return nil
    end

    return tree
end

function Source:verify_tree()
    local parser = self:get_parser()
    local tree = parser:parse()[1]

    if tree == nil then
        vim.notify(
            "Tree-sitter tree not found in "
                .. self.type
                .. " "
                .. self.route
                .. ": please fix that before continuing!",
            vim.log.levels.ERROR
        )
        return false
    end

    local root_node = tree:root()
    if root_node:has_error() then
        vim.notify(
            "Tree-sitter found syntax errors in "
                .. self.type
                .. " "
                .. self.route
                .. ": please fix them before continuing!",
            vim.log.levels.ERROR
        )
        return false
    end

    return true
end

function Source:get_buffer_requests()
    local tree = self:get_tree()

    if tree == nil then
        return {}
    end

    ---@type http.Request[]
    local requests = {}

    local above_local_context = {}

    local requests_query = queries.requests_query()

    for _, match in requests_query:iter_matches(tree:root(), self.repr) do
        local variable = nil

        for id, node in pairs(match) do
            local capture_name = requests_query.captures[id]
            local capture_value =
                vim.trim(vim.treesitter.get_node_text(node, self.repr))

            if capture_name == "request" then
                local start_line_node = node:named_child(0)
                local start_line = vim.trim(
                    vim.treesitter.get_node_text(start_line_node, self.repr)
                )

                local method, url = extract_method_and_url(start_line)

                local domain_path, query = unpack(vim.split(url, "?"))

                ---@type http.Request
                local request = {
                    url = domain_path,
                    method = method,
                    query = query,
                    node = node,
                    local_context = above_local_context,
                    source = self,
                }

                table.insert(requests, request)
                above_local_context = {}
            elseif capture_name == "variable_name" then
                variable = { name = capture_value, value = "" }
            elseif capture_name == "variable_value" then
                if variable then
                    variable.value = capture_value
                end
            end
        end

        if variable then
            above_local_context[variable.name] = variable.value
            variable = nil
        end
    end

    return requests
end

function Source:get_file_requests()
    local tree = self:get_tree()

    if tree == nil then
        return {}
    end

    ---@type http.Request[]
    local requests = {}

    local above_local_context = {}

    local requests_query = queries.requests_query()

    for _, match in requests_query:iter_matches(tree:root(), self.repr) do
        local variable = nil

        for id, node in pairs(match) do
            local capture_name = requests_query.captures[id]
            local capture_value =
                vim.trim(vim.treesitter.get_node_text(node, self.repr))

            if capture_name == "request" then
                local start_line_node = node:named_child(0)
                local start_line = vim.trim(
                    vim.treesitter.get_node_text(start_line_node, self.repr)
                )

                local method, url = extract_method_and_url(start_line)

                local domain_path, query = unpack(vim.split(url, "?"))

                local request = {
                    url = domain_path,
                    method = method,
                    query = query,
                    node = node,
                    local_context = above_local_context,
                    source = self,
                }

                above_local_context = {}

                table.insert(requests, request)
            elseif capture_name == "variable_name" then
                variable = { name = capture_value, value = "" }
            elseif capture_name == "variable_value" then
                if variable then
                    variable.value = capture_value
                end
            end
        end

        if variable then
            above_local_context[variable.name] = variable.value
            variable = nil
        end
    end

    return requests
end

function Source:get_requests()
    if Source.type == source_type.BUFFER then
        return self:get_buffer_requests()
    else
        return self:get_file_requests()
    end
end

---@param request http.Request
local function find_enclosing_separators(request)
    local p_separator = nil
    local n_separator = nil

    local node = request.node

    local p_sibling = node:prev_sibling()
    while p_sibling ~= nil do
        if p_sibling:type() == tree_sitter_nodes.separator then
            p_separator = p_sibling
            break
        end

        p_sibling = p_sibling:prev_sibling()
    end

    local n_sibling = node:next_sibling()
    while n_sibling ~= nil do
        if n_sibling:type() == tree_sitter_nodes.separator then
            n_separator = n_sibling
            break
        end

        n_sibling = n_sibling:next_sibling()
    end

    local p_separator_line = nil
    local n_separator_line = nil

    if p_separator then
        p_separator_line, _, _, _ = p_separator:range()
    end

    if n_separator then
        n_separator_line, _, _, _ = n_separator:range()
    end

    return p_separator_line, n_separator_line
end

function Source:get_closest_request_from(row)
    local requests = self:get_requests()

    for _, request in ipairs(requests) do
        local context_start, context_end = find_enclosing_separators(request)

        local inside_context = (context_start == nil or context_start < row - 1)
            and (context_end == nil or row - 1 < context_end)

        if inside_context then
            return request
        end
    end

    return nil
end

---@class http.Variable
---@field name string
---@field value string

---Gets request context from this source.
---@param request http.Request
function Source:get_request_context(request)
    local tree = self:get_tree()

    if tree == nil then
        return {}
    end

    local stop, _, _, _ = request.node:range()

    local context = {}

    local variables_query = queries.variables_query()

    for _, match in
        variables_query:iter_matches(tree:root(), self.repr, 0, stop)
    do
        ---@type http.Variable
        local variable = { name = "", value = "" }

        for id, node in pairs(match) do
            local capture_name = variables_query.captures[id]
            local capture_value =
                vim.trim(vim.treesitter.get_node_text(node, self.repr))

            -- capture_name is either "name" or "value"
            variable[capture_name] = capture_value
        end

        context[variable.name] = variable.value
    end

    return context
end

function Source:get_request_content(request)
    ---@type http.RequestContent
    local content = { headers = {} }

    local header_nodes = {}
    local request_child_count = request.node:named_child_count()

    local body_node = nil

    for i = 0, request_child_count - 1 do
        local child = request.node:named_child(i)

        if child:type() == tree_sitter_nodes.header then
            table.insert(header_nodes, child)
        elseif child:type() == tree_sitter_nodes.body then
            body_node = child
        end
    end

    for _, node in ipairs(header_nodes) do
        content.headers[#content.headers + 1] =
            vim.trim(vim.treesitter.get_node_text(node, self.repr))
    end

    if body_node then
        content.body =
            vim.trim(vim.treesitter.get_node_text(body_node, self.repr))
    end

    return content
end

return { Source = Source, type = source_type }
