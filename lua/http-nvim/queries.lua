local M = {}

local function init_parser()
    local parser_config =
        require("nvim-treesitter.parsers").get_parser_configs()
    parser_config.http2 = {
        install_info = {
            url = "https://github.com/rstcruzo/tree-sitter-http2",
            branch = "main",
            files = { "src/parser.c" },
        },
        filetype = "http",
    }

    vim.treesitter.language.register("http2", "http")

    vim.filetype.add({
        extension = {
            http = "http",
        },
    })
end

-- Initializing the parser here to avoid errors when using any of these queries.
init_parser()

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
