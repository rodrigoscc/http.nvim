local queries = require("http-nvim.queries")

local fs = require("http-nvim.fs")
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

---@param request_node TSNode
local function find_enclosing_separators(request_node)
    local p_separator = nil
    local n_separator = nil

    local p_sibling = request_node:prev_sibling()
    while p_sibling ~= nil do
        if p_sibling:type() == tree_sitter_nodes.separator then
            p_separator = p_sibling
            break
        end

        p_sibling = p_sibling:prev_sibling()
    end

    local n_sibling = request_node:next_sibling()
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
        repr = fs.read_file(repr)
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

---Extracts the request data from the TS Node.
---@param request_node TSNode
---@return http.Request
function Source:extract_request(request_node)
    local start_line_node = request_node:named_child(0)
    assert(
        start_line_node ~= nil
            and start_line_node:type() == tree_sitter_nodes.start_line,
        "First request child must be the start line"
    )
    local start_line =
        vim.trim(vim.treesitter.get_node_text(start_line_node, self.repr))

    local method, url = extract_method_and_url(start_line)

    local domain_path, query = unpack(vim.split(url, "?"))

    local header_nodes = {}
    local request_child_count = request_node:named_child_count()

    local body_node = nil

    for i = 0, request_child_count - 1 do
        local child = request_node:named_child(i)
        assert(
            child ~= nil,
            "request node is meant to have "
                .. request_child_count
                .. " children"
        )

        if child:type() == tree_sitter_nodes.header then
            table.insert(header_nodes, child)
        elseif child:type() == tree_sitter_nodes.body then
            body_node = child
        end
    end

    local headers = {}

    for _, node in ipairs(header_nodes) do
        local name_node = node:field("name")[1]
        local value_node = node:field("value")[1]

        -- TODO: Make sure TS grammar captures only after trailing whitespace and before it.
        local name =
            vim.trim(vim.treesitter.get_node_text(name_node, self.repr))
        local value =
            vim.trim(vim.treesitter.get_node_text(value_node, self.repr))

        headers[name] = value
    end

    local body = nil

    if body_node then
        body = vim.trim(vim.treesitter.get_node_text(body_node, self.repr))
    end

    local s, s1, _ = request_node:start()
    local e, e1, _ = request_node:end_()

    local context_start_row, context_end_row =
        find_enclosing_separators(request_node)

    ---@type http.Request
    local request = {
        url = domain_path,
        method = method,
        query = query,
        headers = headers,
        body = body,
        local_context = {},
        source = self,
        start_range = { s, s1 },
        end_range = { e, e1 },
        context_start_row = context_start_row,
        context_end_row = context_end_row,
    }

    return request
end

function Source:get_requests()
    local tree = self:get_tree()

    if tree == nil then
        return {}
    end

    ---@type http.Request[]
    local requests = {}

    local above_local_context = {}

    local requests_query = queries.requests_query()

    if vim.version.lt(vim.version(), "0.11.0") then
        for _, match in requests_query:iter_matches(tree:root(), self.repr) do
            local variable = nil

            for id, node in pairs(match) do
                local capture_name = requests_query.captures[id]
                local capture_value =
                    vim.trim(vim.treesitter.get_node_text(node, self.repr))

                if capture_name == "request" then
                    local request = self:extract_request(node)
                    request.local_context = above_local_context
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
    else
        for _, match in requests_query:iter_matches(tree:root(), self.repr) do
            local variable = nil

            for id, nodes in pairs(match) do
                local capture_name = requests_query.captures[id]

                for _, node in ipairs(nodes) do
                    local capture_value =
                        vim.trim(vim.treesitter.get_node_text(node, self.repr))

                    if capture_name == "request" then
                        local request = self:extract_request(node)
                        request.local_context = above_local_context
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
            end

            if variable then
                above_local_context[variable.name] = variable.value
                variable = nil
            end
        end
    end

    return requests
end

function Source:get_closest_request_from(row)
    local requests = self:get_requests()

    for _, request in ipairs(requests) do
        local inside_context = (
            request.context_start_row == nil
            or request.context_start_row < row - 1
        )
            and (
                request.context_end_row == nil
                or row - 1 < request.context_end_row
            )

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

    local stop = unpack(request.start_range)

    local context = {}

    local variables_query = queries.variables_query()

    if vim.version.lt(vim.version(), "0.11.0") then
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
    else
        for _, match in
            variables_query:iter_matches(tree:root(), self.repr, 0, stop)
        do
            ---@type http.Variable
            local variable = { name = "", value = "" }

            for id, nodes in pairs(match) do
                local capture_name = variables_query.captures[id]

                for _, node in ipairs(nodes) do
                    local capture_value =
                        vim.trim(vim.treesitter.get_node_text(node, self.repr))

                    -- capture_name is either "name" or "value"
                    variable[capture_name] = capture_value
                end
            end

            context[variable.name] = variable.value
        end
    end

    return context
end

return { Source = Source, type = source_type }
