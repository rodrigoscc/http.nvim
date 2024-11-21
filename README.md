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
    - Condition the request to run or not
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
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim"
    },
}
```

> [!NOTE]
>
> http.nvim uses a Tree-sitter grammar that is not yet included in nvim-treesitter. `setup()` replaces the default `http` grammar with [this](https://github.com/rstcruzo/tree-sitter-http2) one. This grammar provides features that aren't available in the default grammar.

> [!NOTE]
>
> http.nvim will format any JSON response if `jq` is installed.

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

#### Reserved request-scoped variables
| Variable              | Description                                                                      |
| --------------------- | -------------------------------------------------------------------------------- |
| `request.title`       | The title of the request. Generally used to search and run the request directly. |
| `request.after_hook`  | The hook function name to run after the request completes.                       |
| `request.before_hook` | The hook function name to run before the request completes.                      |


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

    update_env({
        access_token = response.body.access_token,
        refresh_token = response.body.refresh_token,
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

| User Command        | Description                                  |
| ------------------- | -------------------------------------------- |
| `:Http run_closest` | Run request under cursor                     |
| `:Http run`         | Search request with Telescope and run it     |
| `:Http inspect`     | Inspect variable under cursor                |
| `:Http jump`        | Search request with Telescope and jump to it |
| `:Http run_last`    | Run last request                             |
| `:Http select_env`  | Select project environment                   |
| `:Http create_env`  | Create new project environment               |
| `:Http open_env`    | Open active project environment file         |
| `:Http open_hooks`  | Open project hooks file                      |
| `:Http yank_curl`   | Yank the resulting curl command to clipboard |

### Lualine component
Use our Lualine component to show the active environment in your statusline.

```lua
require("lualine").setup({
    sections = {
        lualine_a = { require("http-nvim").http_env_lualine_component },
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

