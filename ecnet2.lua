-- ecnet2.lua — Shim to make require("ecnet2") find the framework
--
-- The framework lives in /cccrane/ecnet/ecnet2/init.lua.  This shim at
-- /cccrane/ecnet2.lua is found by package.path pattern /cccrane/?.lua and
-- delegates via dofile so that internal require("ecnet2.constants") etc
-- resolve through the /cccrane/ecnet/?.lua pattern already set in init.lua.

return dofile("/cccrane/ecnet/ecnet2/init.lua")
