local M = {}

---Checks if file exists in given path.
---@param path string the path of the file
---@return boolean
M.file_exists = function(path)
    return vim.fn.findfile(path) ~= ""
end
---
---Checks if directory exists in given path.
---@param path string the path of the directory
---@return boolean
M.dir_exists = function(path)
    return vim.fn.finddir(path) ~= ""
end

---Read file in given path and return contents.
---@param path string the path of the file
---@return string
M.read_file = function(path)
    local fd = vim.uv.fs_open(path, "r", 438)
    if fd == nil then
        return ""
    end

    local stat = vim.uv.fs_fstat(fd)
    if stat == nil or stat.type ~= "file" then
        return ""
    end

    local contents = vim.uv.fs_read(fd, stat.size, 0)

    vim.uv.fs_close(fd)

    return contents or ""
end

M.touch_file = function(path)
    vim.uv.fs_mkdir(vim.fs.dirname(path), 493)

    if M.file_exists(path) then
        return
    end

    local fd, err = vim.uv.fs_open(path, "a", 438)
    if not fd then
        print("ERROR: ", err)
        return
    end

    vim.uv.fs_close(fd)
end

M.write_file = function(path, contents, flags)
    flags = flags or "w"

    local fd, err = vim.uv.fs_open(path, flags, 438)
    if not fd then
        print("ERROR: ", err)
        return
    end

    vim.uv.fs_write(fd, contents, -1)
    vim.uv.fs_close(fd)
end

return M
