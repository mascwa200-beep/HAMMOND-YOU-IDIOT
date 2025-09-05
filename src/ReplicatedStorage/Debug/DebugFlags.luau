local M = {}

M.flags = {
    flight = false,
    anim = false,
}

function M.set(flag: string, value: boolean)
    M.flags[flag] = value and true or false
end

function M.get(flag: string): boolean
    return M.flags[flag] == true
end

function M.log(flag: string, ...)
    if M.get(flag) then
        print("[DEBUG:" .. flag .. "]", ...)
    end
end

return M

