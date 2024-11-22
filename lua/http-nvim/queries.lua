local Job = require("plenary.job")

local M = {}

local grammar_repo_url = "https://github.com/rstcruzo/tree-sitter-http2"
local grammar_repo_revision = "f75345b15efdf2a4e652e2202060edd6aa9c4096"

local function clone_grammar_repo(path, callback)
    local job = Job:new({
        command = "git",
        args = { "clone", grammar_repo_url, path },
        on_exit = function(job, code)
            callback(job, code)
        end,
    })

    job:start()
end

local function install_grammar()
    local local_grammar_path = vim.fn.stdpath("data") .. "/http-nvim-grammar"

    if vim.fn.isdirectory(local_grammar_path) == 1 then
        vim.opt.runtimepath:append(local_grammar_path)
        return
    end

    clone_grammar_repo(local_grammar_path, function(job, code)
        if code ~= 0 then
            error("Failed to clone grammar repo")
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

    clone_grammar_repo(local_grammar_path, function(job, code)
        if code ~= 0 then
            error("Failed to clone grammar repo")
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

M.update_grammar_queries = update_grammar_queries

return M
