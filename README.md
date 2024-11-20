# 🌐 http.nvim

![Run tests badge](https://github.com/rstcruzo/http.nvim/actions/workflows/tests.yml/badge.svg)

`http.nvim` lets you run HTTP requests from Neovim, manage environments and run hooks before and after each request.

## Features
- Store multiple requests in a `.http` file
- Search project requests with Telescope
- Run project requests with Telescope
- Manage multiple environments per project
- Declare global or request-scoped variables in the `.http` file
- Run last request run for easier iteration
- Declare before and after hooks for each request
- Autocomplete variables with cmp
- Inspect variables current value
- Lualine component to show current environment

## Installation

Install the plugin with your preferred plugin manager:

```lua
-- lazy.nvim
{
    "rstcruzo/http.nvim",
    config = function()
        require("http-nvim").setup()
    end,
}
```

> [!NOTE]
>
> http.nvim uses a Tree-sitter grammar that is not yet included in nvim-treesitter. `setup()` modifies the default `http` grammar to use [this](https://github.com/rstcruzo/tree-sitter-http2) one.
