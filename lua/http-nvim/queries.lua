local M = {}

-- TODO: Change parser name from http2 to something else.
M.requests_query = vim.treesitter.query.parse(
    "http2",
    [[
[
 (variable_declaration
	name: (_) @variable_name (#lua-match? @variable_name "request.*")
	value: (_) @variable_value)
 (request) @request
]
]]
)

M.requests_only_query = vim.treesitter.query.parse(
    "http2",
    [[
 (request) @request
]]
)

M.variables_query = vim.treesitter.query.parse(
    "http2",
    [[
 (variable_declaration
	name: (identifier) @name (#not-lua-match? @name "request.*")
	value: (rest_of_line) @value)
]]
)

return M
