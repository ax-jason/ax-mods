--[[
local random=require("random")
local r1, r2 = random.new(), random.new(32)
print(r1:random(1, 100), r2:random(1, 100))
]]--
local t={}
local RAND_MAX = 0x7FFF;
local rand_meta = {__index={}}
function rand_meta.__index:rand()
    local quotient, remainder, t

    quotient = self.seed / 127773

    remainder = self.seed % 127773

    t = 16807 * remainder - 2836 * quotient

    if (t <= 0) then
        t = t+ RAND_MAX
    end
    self.seed = math.floor(t)
    return t % (RAND_MAX + 1)
end

function rand_meta.__index:randomseed(seed)
    self.seed = seed
end

function rand_meta.__index:random(a,b)
    local r = self:rand()
    r = (r%RAND_MAX) / RAND_MAX
    if(a and b) then
        return math.floor((r*(b-a+1))+a)
    elseif(a) then
        return math.floor(a*r)+1
    else
        return r
    end
end

t.new = function(seed)
    return setmetatable({seed = seed or os.time()},rand_meta)
end

t.test = function()
  local r1, r2 = t.new(), t.new(32)
  print(r1:random(1, 100), r2:random(1, 100))
end

return t
