---@class Spinner
---@field private frames string[]
---@field private current_frame integer
local Spinner = {}
Spinner.__index = Spinner

function Spinner.new()
    return setmetatable({
        current_frame = 1,
        frames = {
            "⠋",
            "⠙",
            "⠹",
            "⠸",
            "⠼",
            "⠴",
            "⠦",
            "⠧",
            "⠇",
            "⠏",
        },
    }, Spinner)
end

function Spinner:frame()
    local frame = self.frames[self.current_frame]
    self:advance_frame()
    return frame
end

function Spinner:advance_frame()
    self.current_frame = (self.current_frame % #self.frames) + 1
end

return Spinner
