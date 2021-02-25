if( GetLocale() ~= "zhTW" ) then return end
local L = {}

local ABS = select(2, ...)
ABS.L = setmetatable(L, {__index = ABS.L})
