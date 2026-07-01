local a=require"ccryptolib.random"local b,c;return function()if not c or b>=2^32 then c=a.random(28)b=0 end;b=b+1;return("<I4"):pack(b)..c end
