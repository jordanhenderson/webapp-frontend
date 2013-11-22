--Handles the background process queue.
handlers = require "core/handlers"
local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
typedef struct Process {webapp_str_t* func; webapp_str_t* vars;} Process;
void QueueProcess(void* app, webapp_str_t* func, webapp_str_t* vars);
Process* GetNextProcess(void* app);
]]
c = ffi.C

local process = c.GetNextProcess(app)
while process do
  --NYI
  process = c.GetNextProcess(app)
end
