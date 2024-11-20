local project = require("http-nvim.project")
local Source = require("http-nvim.source").Source
local SourceType = require("http-nvim.source").type
local tree_sitter_nodes = require("http-nvim.constants").tree_sitter_nodes

local http_source = {}

function http_source:is_available()
    local node = vim.treesitter.get_node()

    if node == nil then
        return false
    end

    local cursor_node_is_variable_ref = node:type()
        == tree_sitter_nodes.variable_ref

    local child = node:child(0)
    local child_is_variable_ref = false

    if child ~= nil then
        child_is_variable_ref = child:type() == tree_sitter_nodes.variable_ref
    end

    return cursor_node_is_variable_ref or child_is_variable_ref
end

function http_source:complete(params, callback)
    local options = {}

    local source = Source.new(SourceType.BUFFER, vim.api.nvim_get_current_buf())

    local cursor_line = unpack(vim.api.nvim_win_get_cursor(0))

    local request = source:get_closest_request_from(cursor_line)
    if request == nil then
        callback(options)
        return
    end

    local request_context = source:get_request_context(request)
    local env_context = project:get_env_variables()

    local context = vim.tbl_extend(
        "force",
        env_context,
        request_context,
        request.local_context
    )

    for variable, value in pairs(context) do
        table.insert(options, {
            label = variable,
            detail = value,
            kind = 6, -- variable
        })
    end

    callback(options)
end

function http_source:get_debug_name()
    return "http source"
end

return http_source
