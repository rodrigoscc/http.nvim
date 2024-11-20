# 🌐 http.nvim

![Run tests badge](https://github.com/rstcruzo/http.nvim/actions/workflows/tests.yml/badge.svg)

`http.nvim` lets you run HTTP requests from Neovim, manage environments and run hooks before and after each request.

## Features
- Store multiple requests in a `.http` file
- Search project requests with Telescope
- Run project requests with Telescope
- Manage multiple environments per project
- Declare global or request-scoped variables in the `.http` file
- Run last request run for easier API development iteration
- Assign before and after hooks for each request. In a hook, you can:
    - Update the current environment
    - Access the response
    - Run other request with a different context
    - etc.
- Hook functions are declared in a separate Lua file, for easier maintenance and reuse
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
        -- Run `:TSInstall http` after the setup is run for the first time and
        -- reinstall the grammar if prompted.
    end,
}
```

> [!NOTE]
>
> http.nvim uses a Tree-sitter grammar that is not yet included in nvim-treesitter. `setup()` modifies the default `http` grammar to use [this](https://github.com/rstcruzo/tree-sitter-http2) one. This grammar provides features that aren't available in the default grammar.

## Usage

Create a new `.http` file inside the `.http` directory of your project (e.g. `.http/requests.http`). Write your request in the file, and run it with `:Http run_closest`.

```http
POST https://jsonplaceholder.typicode.com/posts
Content-Type: application/json

{
    "title": "foo",
    "body": "bar",
    "userId": 1
}
```

Have multiple requests in a single file by separating them with a line containing only `###`.

```http
@request.title = Create a post
POST https://jsonplaceholder.typicode.com/posts
Content-Type: application/json

{
    "title": "foo",
    "body": "bar",
    "userId": 1
}

###

@request.title = Get all posts
GET https://jsonplaceholder.typicode.com/posts
```

Run a request from anywhere in your project with `:Http run`. Filter the requests by the `request.title`, if defined, or by the request start line.

### Variables
Variables are available anywhere below the line they were declared. Variables that start with `request.` are request-scoped and are only available in the request they were declared in.

Example:
```http
@request.title = Create a post
@userId = 1
POST https://jsonplaceholder.typicode.com/posts
Content-Type: application/json

{
    "title": "foo",
    "body": "bar",
    "userId": {{userId}}
}
```

#### Special request-scoped variables
| Variable              | Description                                                                      |
| --------------------- | -------------------------------------------------------------------------------- |
| `request.title`       | The title of the request. Generally used to search and run the request directly. |
| `request.after_hook`  | The hook function to run after the request completes.                             |
| `request.before_hook` | The hook function to run before the request completes.                           |

### Commands

| User Command      | Description                                  |
| ----------------- | -------------------------------------------- |
| `:Http run_closest` | Run request under cursor                     |
| `:Http run`         | Search request with Telescope and run it     |
| `:Http inspect`     | Inspect variable under cursor                |
| `:Http jump`        | Search request with Telescope and jump to it |
| `:Http run_last`    | Run last request                             |
| `:Http select_env`  | Select project environment                   |
| `:Http create_env`  | Create new project environment               |
| `:Http open_env`    | Open active project environment file         |
| `:Http open_hooks`  | Open project hooks file                      |

### Lualine component
Use our Lualine component to show the active environment in your statusline.

```lua
require("lualine").setup({
    sections = {
        lualine_a = { require("http-nvim").http_env_lualine_component },
    },
})
