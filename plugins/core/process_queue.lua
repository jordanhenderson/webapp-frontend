--Handles the background process queue.
local ffi = require("ffi")
ffi.cdef[[
typedef struct { 
  const char* data; 
  uint32_t len; 
  int allocated;
} webapp_str_t;
typedef struct Process {
  webapp_str_t* func; 
  webapp_str_t* vars;
} Process;
Process* GetNextProcess(void*);
void FinishProcess(Process*);
]]
c = ffi.C
common = require "common"
local process = c.GetNextProcess(bgworker)
while process ~= nil do
  local f = common.appstr(process.func)
  local v = common.appstr(process.vars)
  
  c.FinishProcess(process)
  process = c.GetNextProcess(bgworker)
end
