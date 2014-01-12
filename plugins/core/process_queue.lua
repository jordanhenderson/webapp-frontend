--Handles the background process queue.
local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; long long len; } webapp_str_t;
typedef struct Process {webapp_str_t* func; webapp_str_t* vars;} Process;
void QueueProcess(void* queue, webapp_str_t* func, webapp_str_t* vars);
Process* GetNextProcess(void* queue);
]]
c = ffi.C
common = require "common"
local process = c.GetNextProcess(queue)
while process ~= nil do
  local f = common.appstr(process.func)
  local v = common.appstr(process.vars)
  process = c.GetNextProcess(queue)
end
