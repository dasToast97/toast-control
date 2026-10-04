package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(n,c,i) if c then pass=pass+1;print("  PASS "..n) else failc=failc+1;print("  FAIL "..n.."  "..tostring(i)) end end
local function measure(src)
    local S=Sim.new({config=""});local G=Sim.env(S);G.turtle=nil;G.os.getComputerID=function()return 4 end
    for _,n in ipairs({"toast_common.lua","toast_model.lua"})do S.files["/toast/"..n]=io.open(src..n):read("a")end
    local bc=0;G.rednet.broadcast=function() bc=bc+1 end
    local cfg=G.dofile("/toast/toast_common.lua").load({role="controller",controllerId=4})
    local m=G.dofile("/toast/toast_model.lua").new(cfg)
    for id=10,19 do m.ingest(id,{kind="status",version=2,id=id,status="Abbau",ack=0,total=1},"toast.mine.v1") end
    for id=30,33 do m.remote(id,{kind="hello",role="pocket",version=1,controllerId=4},"toast.control.remote.v1") end
    S.sent={};bc=0
    for t=1,60 do S.T=S.T+1;m.tick()
        for id=30,33 do m.remote(id,{kind="hello",role="pocket",version=1,controllerId=4},"toast.control.remote.v1") end
    end
    return #S.sent+bc
end
print("L1 Funkverkehr der Zentrale in 60 s (10 Turtles, 4 Pockets/Infoscreens, jeder meldet sich jede Sekunde)")
local new=measure("/home/claude/toast/")
print(("    %d Nachrichten (Version 3.12.1 hatte 1380)"):format(new))
check("hoechstens 400 Nachrichten",new<=400,new)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
