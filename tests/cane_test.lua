package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local cfg=[[return {role="auto",job="farm",controllerId=4,label="Rohr",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=3,length=4,crop="sugarcane",interval=5,seedReserve=0,radioTimeout=10,water={{column=2,row=2},{column=2,row=3}}},
    mine={length=4,height=2,tunnels=2,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={}}}]]
-- Turtle faehrt auf y=0 (Hoehe 3. Block), y=1 = 2. Block, y=2 = unterster Block, y=3 = Erde
local CANE="minecraft:sugar_cane"
print("Z1 Zuckerrohr: 3. + 2. Block ernten, unterster bleibt, nichts nachpflanzen, keine Saatgutkiste")
local tall,mid,low={},{},{}
local S=Sim.new({config=cfg,default=false,actions={{t=2,fn=function(S)Sim.cmd(S,"once",10)end}},
    world=function(S)
        for x=0,2 do for z=1,4 do
            if x==1 and (z==2 or z==3) then S.world[S.key(x,2,z)]="minecraft:water"
            else
                S.world[S.key(x,3,z)]="minecraft:dirt";S.world[S.key(x,2,z)]=CANE
                local h=(x+z)%3   -- 0: nur unten, 1: 2 hoch, 2: 3 hoch
                if h>=1 then S.world[S.key(x,1,z)]=CANE;mid[#mid+1]={x,z} end
                if h>=2 then S.world[S.key(x,0,z)]=CANE;tall[#tall+1]={x,z} end
                low[#low+1]={x,z}
            end
        end end
    end})
S.protocol="toast.farm.v2";Sim.run(S,300)
local bottom,upper=0,0
for _,p in ipairs(low) do if S.world[S.key(p[1],2,p[2])]==CANE then bottom=bottom+1 end end
for x=0,2 do for z=1,4 do for y=0,1 do if S.world[S.key(x,y,z)]==CANE then upper=upper+1 end end end end
local inv=0;for i=1,16 do local it=S.inv[i];if it and it.name==CANE then inv=inv+it.count end end
local expect=#mid+#tall
check("unterste Bloecke stehen alle noch ("..#low..")",bottom==#low,bottom)
check("2. und 3. Bloecke alle geerntet",upper==0,upper)
check("Zuckerrohr abgeliefert, nichts behalten",S.chestNames and S.chestNames[CANE]==true and inv==0,inv)
check("Ertrag = "..expect.." Zuckerrohr",S.last and S.last.total==expect,S.last and S.last.total)
check("Geerntet = "..#mid.." Pflanzen",S.last and S.last.harvested==#mid,S.last and S.last.harvested)
check("kein Fehler, fertig zu Hause",not (S.last and S.last.fault) and S.p.x==0 and S.p.z==0,tostring(S.last and S.last.fault).." "..tostring(S.last and S.last.status))
check("kein Saatgut-Hinweis",S.last and S.last.cane==true and S.last.seeds==nil)
print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
