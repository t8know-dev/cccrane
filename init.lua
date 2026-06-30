-- init.lua — Bootstrap loader for the cccrane project
--
-- Adds /cccrane/ to the Lua module search path so all require() calls resolve
-- using slash-based module names that mirror the filesystem layout.
-- Every cccrane script starts with dofile("/cccrane/init.lua") before any require.
--
-- Usage from command line:
--   dofile("/cccrane/init.lua")
--   local e = require "ecnet2"
--   e.open("top")
--   local i = e.Identity("/.ecnet2")
--   print(i.address)
--
-- Module resolution examples:
--   require "ecnet2"                     → /cccrane/ecnet2.lua (shim → dofile into ecnet/ecnet2/init.lua)
--   require "ecnet/ecnet2/constants"     → /cccrane/ecnet/ecnet2/constants.lua
--   require "ccryptolib/ccryptolib/random" → /cccrane/ccryptolib/ccryptolib/random.lua

package.path = package.path
    .. ";/cccrane/?.lua"
