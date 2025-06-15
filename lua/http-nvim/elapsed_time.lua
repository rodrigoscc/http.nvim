local Spinner = require("http-nvim.spinner")

local elapsed_time_ns = vim.api.nvim_create_namespace("http-nvim-elapsed-time")

---@class ElapsedTime
---@field private bufnr integer
---@field private line integer
---@field private extmark_id integer
---@field private spinner Spinner
---@field private start_time_ns number|nil
---@field private timer uv.uv_timer_t|nil
local ElapsedTime = {}
ElapsedTime.__index = ElapsedTime

function ElapsedTime.new(bufnr, line)
    return setmetatable({
        bufnr = bufnr,
        line = line,
        extmark_id = vim.uv.hrtime(),
        spinner = Spinner.new(),
    }, ElapsedTime)
end

function ElapsedTime:start()
    self.timer = vim.uv.new_timer()
    assert(self.timer ~= nil, "Timer must be created")

    self.start_time_ns = vim.uv.hrtime()

    self.timer:start(0, 50, function()
        local current_time_ns = vim.uv.hrtime()
        local seconds =
            string.format("%.2f", (current_time_ns - self.start_time_ns) / 1e9)

        vim.schedule(function()
            vim.api.nvim_buf_set_extmark(
                self.bufnr,
                elapsed_time_ns,
                self.line,
                0,
                {
                    virt_text = {
                        { self.spinner:frame(), "Number" },
                        { " " .. seconds .. "s", "LineNr" },
                    },
                    id = self.extmark_id,
                }
            )
        end)
    end)
end

function ElapsedTime:stop()
    self.timer:stop()

    vim.schedule(function()
        vim.api.nvim_buf_del_extmark(
            self.bufnr,
            elapsed_time_ns,
            self.extmark_id
        )
    end)
end

return ElapsedTime
