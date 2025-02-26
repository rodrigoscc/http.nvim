local hooks = require("http-nvim.hooks")
local project = require("http-nvim.project")
local ui = require("http-nvim.ui")
local curl = require("http-nvim.curl")
local Parser = require("http-nvim.parser").Parser
local log = require("http-nvim.log")

---@class Http
---@field last_request http.Request
---@field last_override_context table?
local Http = {}
Http.__index = Http

function Http.new()
    return setmetatable({
        last_request = nil,
        last_override_context = nil,
    }, Http)
end

local function interp(s, tab)
    return (
        s:gsub("({%b{}})", function(w)
            return tab[w:sub(3, -3)] or w
        end)
    )
end

---Use context to complete the request content
---@param content http.RequestContent
---@param context table
function Http:complete_content(content, context)
    ---@type http.RequestContent
    local completed_content = { headers = {} }

    if content.body ~= nil then
        completed_content.body = interp(content.body, context)
    end

    if content.headers ~= nil then
        local replaced_headers = {}

        for _, header in ipairs(content.headers) do
            table.insert(replaced_headers, interp(header, context))
        end

        completed_content.headers = replaced_headers
    end

    return completed_content
end

---Use context to complete request data
---@param request http.Request
---@param context table
---@return http.Request
function Http:complete_request(request, context)
    local completed_request = {
        method = request.method,
        url = interp(request.url, context),
        query = request.query and interp(request.query, context),
        node = request.node,
        local_context = request.local_context,
        source = request.source,
    }

    return completed_request
end

function Http:get_aggregate_context(request)
    local source = request.source

    local env_context = project.get_env_variables()
    local request_context = source:get_request_context(request)

    local context = vim.tbl_extend(
        "force",
        env_context,
        request_context,
        request.local_context
    )

    return context
end

local function error_handler(err)
    log.fmt_error("Error parsing response %s\n" .. debug.traceback(), err)
end

function Http:_request_callback(command, request, after_hook)
    return function(obj)
        local stdout = vim.split(obj.stdout, "\n", { trimempty = true })
        local stderr = vim.split(obj.stderr, "\n", { trimempty = true })
        local output = vim.list_extend(stdout, stderr)

        local response = nil
        local status_ok = obj.code == 0

        ---@type http.RequestState
        local state = "error"

        if status_ok then
            local parser = Parser.new()
            local status, result =
                xpcall(parser.parse_response, error_handler, parser, output)

            if status then
                response = result
            end

            state = "finished"
        end

        vim.schedule(function()
            ui.set_request_state(request, state)
        end)

        ---@type http.Raw
        local raw = {
            command = command,
            output = output,
        }

        if after_hook == nil then
            vim.schedule(function()
                ui.show(request, response, raw)
            end)
        else
            after_hook(request, response, raw)
        end
    end
end

---Runs a request
---@param request http.Request
---@param override_context table?
function Http:run(request, override_context)
    self.last_request = request
    self.last_override_context = override_context

    local source = request.source

    if not source:verify_tree() then
        return
    end

    local content = source:get_request_content(request)

    local context = self:get_aggregate_context(request)

    request = self:complete_request(request, context)
    content = self:complete_content(content, context)

    local before_hook, after_hook = hooks.load_hook_functions(
        request.local_context["request.before_hook"],
        request.local_context["request.after_hook"]
    )

    local command = curl.build_command(request, content)

    local start_request = function()
        ui.set_request_state(request, "running")

        vim.system(
            command,
            { text = true },
            self:_request_callback(command, request, after_hook)
        )
    end

    if before_hook ~= nil then
        before_hook(request, start_request)
    else
        start_request()
    end
end

function Http:run_last()
    if self.last_request == nil then
        return
    end

    self:run(self.last_request, self.last_override_context)
end

function Http:run_with_title(title, override_context)
    local requests = project.get_requests()

    local request_with_title = nil

    for _, request in ipairs(requests) do
        local r_title = request.local_context["request.title"]
        if r_title == title then
            request_with_title = request
            break
        end
    end

    if request_with_title == nil then
        error("request not found")
    end

    self:run(request_with_title, override_context)
end

return Http.new()
