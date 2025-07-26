local M = {}

local grammar_repo_url = "https://github.com/rodrigoscc/tree-sitter-http2"
local grammar_repo_revision = "70c4406365333cdafc60ec56ee7fbd2494ad44d6"

local function clone_grammar_repo(path, callback)
    vim.system(
        { "git", "clone", grammar_repo_url, path },
        { text = true },
        callback
    )
end

local function install_grammar()
    local local_grammar_path = vim.fn.stdpath("data") .. "/http-nvim-grammar"

    if vim.fn.isdirectory(local_grammar_path) == 1 then
        vim.opt.runtimepath:append(local_grammar_path)
        return
    end

    clone_grammar_repo(local_grammar_path, function(obj)
        if obj.code ~= 0 then
            error("Failed to clone grammar repo: ", obj.stderr)
        end

        vim.schedule(function()
            vim.opt.runtimepath:append(local_grammar_path)
            vim.notify("http.nvim grammar installed!")
        end)
    end)
end

local function update_grammar_queries()
    local local_grammar_path = vim.fn.stdpath("data") .. "/http-nvim-grammar"

    -- Delete to clone again
    vim.cmd("silent !rm -rf " .. local_grammar_path)

    clone_grammar_repo(local_grammar_path, function(obj)
        if obj.code ~= 0 then
            error("Failed to clone grammar repo: ", obj.stderr)
        end

        vim.schedule(function()
            vim.notify("http.nvim grammar updated!")
        end)
    end)
end

local function init_parser()
    install_grammar()

    local parser_config =
        require("nvim-treesitter.parsers").get_parser_configs()
    parser_config.http2 = {
        install_info = {
            url = grammar_repo_url,
            branch = "main",
            files = { "src/parser.c" },
            revision = grammar_repo_revision,
            generate_requires_npm = false, -- if stand-alone parser without npm dependencies
            requires_generate_from_grammar = false, -- if folder contains pre-generated src/parser.c
        },
        filetype = "http",
    }

    vim.treesitter.language.register("http2", { "http", "httpnvim.http" })

    vim.filetype.add({
        extension = {
            http = "http",
        },
    })
end

-- Initializing the parser here to avoid errors when using any of these queries.
init_parser()

-- TODO: Change parser name from http2 to something else.
M.requests_query = function()
    return vim.treesitter.query.parse(
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
end

M.variables_query = function()
    return vim.treesitter.query.parse(
        "http2",
        [[
 (variable_declaration
	name: (identifier) @name (#not-lua-match? @name "request.*")
	value: (rest_of_line) @value)
]]
    )
end

M.update_grammar_queries = update_grammar_queries

return M
