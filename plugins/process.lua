macro = require("macro")
require 'macro.builtin'
require 'macro.ifelse'
require 'macro.all'
require 'macro_functions'

local f = io.open(file)
local out, err = macro.substitute_tostring(f)
return out or ""
