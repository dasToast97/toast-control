package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local S=Sim.new({config=""});local G=Sim.env(S);G.turtle=nil;G.os.getComputerID=function()return 4 end
for _,n in ipairs({"toast_common.lua","toast_model.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
local cfg=assert(load(io.open("/home/claude/toast/toast.config.lua"):read("a"),"c","t",{}))()
cfg.devices={[5]={job="farm",name="Weizen Nord"}}
cfg=G.dofile("/toast/toast_common.lua").load(cfg)
local m=G.dofile("/toast/toast_model.lua").new(cfg)
m.ingest(5,{kind="status",version=2,id=5,label="Turtle-Name",ack=0},"toast.farm.v2")
m.ingest(6,{kind="status",version=2,id=6,label="Mine Sued",ack=0},"toast.mine.v1")
local f=m.fleet()
assert(f.entries[5].label=="Weizen Nord","Zentrale-Name gewinnt: "..tostring(f.entries[5].label))
assert(f.entries[6].label=="Mine Sued","Turtle-Name angezeigt: "..tostring(f.entries[6].label))
print("Namens-Test bestanden: #5="..f.entries[5].label.."  #6="..f.entries[6].label)
