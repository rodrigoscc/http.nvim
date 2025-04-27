# 🌐 http.nvim

![Run tests badge](https://github.com/rodrigoscc/http.nvim/actions/workflows/tests.yml/badge.svg)

`http.nvim` lets you run HTTP requests from Neovim, manage environments and run hooks before and after each request.

https://github.com/user-attachments/assets/5b74c2c1-8dff-4611-8be9-00281ee9e366

## Features
- Store multiple requests in a `.http` file
- Search project requests with Telescope or fzf-lua or snacks
- Run project requests with Telescope or fzf-lua or snacks
- Manage multiple environments per project
- Declare global or request-scoped variables in the `.http` file
- Run last request run for easier API development iteration
- Assign before and after hooks for each request. In a hook, you can:
    - Update the current environment
    - Access the response
    - Run other request with a different context
    - Condition the request to run or not
    - etc.
- Hook functions are declared in a separate Lua file, for easier maintenance and reuse
- Autocomplete variables with cmp
- Inspect variables current value
- See the raw curl command and output in a separate buffer
- Copy the equivalent curl command of request under the cursor
- Lualine component to show current environment

## Installation

Install the plugin with your preferred plugin manager:

```lua
-- lazy.nvim
{
    "rodrigoscc/http.nvim",
    config = function()
        require("http-nvim").setup()
    end,
    build = {":TSUpdate http2", ":Http update_grammar_queries"},
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
        "nvim-telescope/telescope.nvim", -- optional: uses it as picker
        "ibhagwan/fzf-lua", -- optional: uses it as picker
        "folke/snacks.nvim" -- optional: uses it as picker
    },
}
```

> [!NOTE]
>
> http.nvim uses a Tree-sitter grammar that is not yet included in nvim-treesitter. When loading this plugin the default `http` grammar is replaced with [this](https://github.com/rodrigoscc/tree-sitter-http2). This grammar provides features that aren't available in the default grammar.

> [!NOTE]
>
> http.nvim will format any JSON response if `jq` is installed.

## Configuration

Override any of the following defaults by passing a table to the `setup()` call.

```lua
---@class http.Opts
local defaults = {
    ---Http files must be stored in this directory for http.nvim to find them
    ---@type string
    http_dir = ".http",
    ---File that contains the hooks to be executed before and after each request.
    ---This file will be inside the directory defined by `http_dir`.
    ---@type string
    hooks_file = "hooks.lua",
    ---File that contains each project environment. This file will
    ---be inside the directory defined by `http_dir`.
    ---@type string
    environments_file = "environments.json",
    ---File that contains each of the projects active environment
    ---@type string
    active_envs_file = vim.fn.stdpath("data") .. "/http/envs.json",
    ---Window config for the response window. Refer to :help nvim_open_win for the available keys.
    ---@type table
    win_config = { split = "below" },
    ---Set compound filetypes in the response buffers (e.g. "httpnvim.json", "httpnvim.text").
    ---This is primarily useful for blacklisting the buffers in plugins like Lualine.
    ---@type boolean
    use_compound_filetypes = false,
    ---Disable builtin winbar if you are explicitly using the public
    ---winbar functions with plugins like lualine and want to avoid flickering.
    ---@type boolean
    builtin_winbar = true,
}
```

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

### Response windows

The response of the request is parsed and then displayed in a bottom split. One buffer shows the response body and other one shows the headers.

| Action                          | Keymap  |
| ------------------------------- | ------- |
| Close Window                    | `q`     |
| Switch between Body and Headers | `<Tab>` |

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

#### Reserved request-scoped variables
| Variable              | Description                                                                      |
| --------------------- | -------------------------------------------------------------------------------- |
| `request.title`       | The title of the request. Generally used to search and run the request directly. |
| `request.after_hook`  | The hook function name to run after the request completes.                       |
| `request.before_hook` | The hook function name to run before the request completes.                      |
| `request.curl_flags`  | Additional flags to include in the generated curl command.                       |


### Hooks
Hooks are declared in a separate Lua file, for easier maintenance and reuse. Enter the hooks file with `:Http open_hooks` and declare your hooks in the file.

```lua
local show_result = require("http-nvim.hooks_utils").show
local update_env = require("http-nvim.hooks_utils").update_env

local function ask_for_confirmation(request, start_request)
    local confirmation =
        vim.fn.input("Are you sure you want to run this request? [y/N] ")

    if confirmation == "y" or confirmation == "Y" then
        start_request()
    end
end

local function save_access_token(request, response, stdout)
    show_result(request, response)

    if response.status_code ~= 200 then
        return
    end

    local body = vim.json.decode(response.body)

    update_env({
        access_token = body.access_token,
        refresh_token = body.refresh_token,
    })
end

return {
    save_access_token = save_access_token,
    ask_for_confirmation = ask_for_confirmation,
}
```

```http
@request.title = Login
@request.before_hook = ask_for_confirmation
@request.after_hook = save_access_token
POST {{api_url}}/login
Content-Type: application/json

{
    "username": "{{username}}",
    "password": "{{password}}"
}
```

The above, once the `Login` request is run, will ask for confirmation and then update the environment with the access and refresh token if a 200 status code is returned.

### Environments
Environments hold variables that are available to all requests in the project. To create a new environment, run `:Http create_env`. A `.json` file will be opened with each environment variables. For instance, the following environments file has the `local` and `staging` environments.

```json
{
    "local": {
        "password": "password123",
        "username": "localuser",
	"api_url": "http://localhost:3000"
    },
    "staging": {
        "password": "password456",
        "username": "staginguser",
	"api_url": "https://staging.api.com"
    }
}
```

Then, select an environment with `:Http select_env`. Now, all the variables in the environment will be available to all requests.

### Commands

| User Command        | Description                                   |
| ------------------- | --------------------------------------------- |
| `:Http run_closest` | Run request under cursor                      |
| `:Http run`         | Search request with Telescope and run it      |
| `:Http inspect`     | Inspect variable under cursor                 |
| `:Http jump`        | Search request with Telescope and jump to it  |
| `:Http run_last`    | Run last request                              |
| `:Http select_env`  | Select project environment                    |
| `:Http create_env`  | Create new project environment                |
| `:Http open_env`    | Open active project environment file          |
| `:Http open_hooks`  | Open project hooks file                       |
| `:Http yank_curl`   | Yank the actual curl command to the clipboard |

### Lualine component
Use our Lualine component to show the active environment in your statusline.

```lua
require("lualine").setup({
    sections = {
        lualine_a = { require("http-nvim").http_env_lualine_component },
    },
})
```

### Lualine winbar
If you are using the lualine winbar, we provide two functions to include the response info in it.

```lua
require("lualine").setup({
    winbar = {
        lualine_a = {
            {
                require("http-nvim").http_response_left_winbar,
            },
        },
        lualine_z = {
            {
                require("http-nvim").http_response_right_winbar,
            },
        },
    },
    inactive_winbar = {
        lualine_a = {
            {
                require("http-nvim").http_response_left_winbar,
            },
        },
        lualine_z = {
            {
                require("http-nvim").http_response_right_winbar,
            },
        },
    }
})
```

You can hide other winbar components in the response buffers using the function `require("http-nvim").is_http_response_buffer()`, which returns true if the current buffer is a http.nvim response buffer.

```lua
            --- ...
            {
                "filename",
                cond = function()
                    return not require("http-nvim").is_http_response_buffer()
                end,
            },
            --- ...
```

If you see flickering when switching between the response buffers, that is the builtin winbar getting overridden by lualine, so go ahead and disable the http.nvim builtin winbar.

```lua
local http = require("http-nvim")
http.setup({
    builtin_winbar = false,
})
```

### Cmp source

You can use the cmp source to complete variables in your requests.

```lua
local cmp = require("cmp")

cmp.setup({
    sources = {
        { name = "http" },
    },
})
```

# Feature Roadmap
- [ ] Auto execute request at specified intervals
- [ ] Keep a history of requests and responses
- [ ] Support filtering responses with jq
- [ ] Format other types of response (xml, html, etc.)
- [ ] Export/import to postman
- [ ] Jump to definition of variable
- [ ] Test scripts
- [ ] Pipelining requests

