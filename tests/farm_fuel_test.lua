package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(maxI) return ([[return {role="auto",job="farm",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=5,length=5,crop="wheat",interval=10,maxInterval=%d,seedReserve=0,radioTimeout=0,water={}},
    mine={length=4,height=2,tunnels=2,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={}}}]]):format(maxI) end
local function field(S,name) for x=0,4 do for z=1,5 do S.world[S.key(x,1,z)]=name end end end
local function run(maxI,ripenAt)
    local acts={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}
    if ripenAt then acts[#acts+1]={t=ripenAt,fn=function(S)field(S,"minecraft:wheat_ripe")end} end
    local S=Sim.new({config=cfg(maxI),default=false,fuel=20000,actions=acts,world=function(S)field(S,"minecraft:wheat_planted_young")end})
    S.inv[1]={name="minecraft:wheat_seeds",count=64};S.protocol="toast.farm.v2";S.seedDrops=1
    local f0=S.fuel
    Sim.run(S,3600)
    local st=load("return "..S.files["/toast_farm_state"])()
    return S,st,f0-S.fuel
end
print("F1 Nichts reif: alte feste Pause (10 s) vs. Spar-Pause (bis 20 min)")
local _,stOld,fuelOld=run(0)
local S,st,fuelNew=run(1200)
print(("    Runden in 1 h: alt %d, neu %d | Fuel: alt %d, neu %d"):format(stOld.rounds or 0,st.rounds or 0,fuelOld,fuelNew))
check("deutlich weniger Runden",(st.rounds or 0)*5<=(stOld.rounds or 0),(st.rounds or 0).." vs "..(stOld.rounds or 0))
check("mind. 5x weniger Fuel",fuelNew*5<=fuelOld,fuelNew.." vs "..fuelOld)
check("Pause bis 20 min gewachsen",st.pause==1200,st.pause)
check("Status zeigt Pause",S.last and S.last.pause==1200 and S.last.lastRipe==0,S.last and S.last.pause)
print("F2 Alles reif -> Pause wird wieder kuerzer")
S,st=run(1200,1500)
check("geerntet",S.chestNames["minecraft:wheat"]==true)
local minP=99999;for _,m in ipairs(S.sent) do if type(m.msg)=="table" and m.msg.pause and (m.msg.lastRipe or 0)>=90 then minP=math.min(minP,m.msg.pause) end end
check("nach voller Ernte kuerzere Pause",minP<1200,minP)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
