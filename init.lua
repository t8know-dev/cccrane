-- init.lua — Bootstrap loader for the cccrane project
--
-- Adds module search paths under /cccrane/ so all require() calls resolve.
-- Every cccrane script starts with dofile("/cccrane/init.lua") before any require.
--
-- Usage from command line:
--   dofile("/cccrane/init.lua")
--   local e = require "ecnet2"
--   e.open("top")
--   local i = e.Identity("/.ecnet2")
--   print(i.address)

-- /cccrane/?.lua              → require "ecnet2"          → /cccrane/ecnet2.lua (shim)
-- /cccrane/ecnet/?.lua        → require "ecnet2.constants" → /cccrane/ecnet/ecnet2/constants.lua
-- /cccrane/ccryptolib/?.lua   → require "ccryptolib.random"→ /cccrane/ccryptolib/ccryptolib/random.lua
package.path = package.path
    .. ";/cccrane/?.lua"
    .. ";/cccrane/ecnet/?.lua"
    .. ";/cccrane/ccryptolib/?.lua"
