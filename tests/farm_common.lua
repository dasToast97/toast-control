local M={protocol="toast.farm.v2",remoteProtocol="toast.farm.remote.v2"}
function M.load(c) assert(type(c)=="table" and c.farm,"farm fehlt");c.role="turtle";return c end
function M.refreshModems() return 1 end
function M.modem() end
function M.contains(l,id) for _,v in ipairs(l) do if v==id then return true end end return false end
function M.number(n) return type(n)=="number" and n or 0 end
function M.serial(n) return type(n)=="number" and n>=1 and n%1==0 end
return M
