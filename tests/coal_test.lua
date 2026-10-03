package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function cfg(use)
    return [[return {role="auto",job="mining",controllerId=4,label="Test",autoDiscover=true,autoPairPockets=true,
    devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},
    network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
    farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
    mine={length=6,height=2,tunnels=1,gap=1,fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,useCoal=]]..tostring(use)..[[,
      protectedBlocks={}}}]]
end
local function world(S)
    for z=1,6 do S.world[S.key(0,0,z)]="minecraft:coal_ore";S.world[S.key(0,-1,z)]="minecraft:deepslate_coal_ore" end
end
local function state(S)local s=S.files["/toast_mining_state"];return s and load("return "..s)() or {} end
for _,use in ipairs({true,false}) do
    print("Kohle als Fuel: "..tostring(use))
    local S=Sim.new({config=cfg(use),world=world,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
    S.protocol="toast.mine.v1";local fuel0=S.fuel;Sim.run(S,400)
    local st=state(S)
    check("fertig + zu Hause",st.next and st.next>1 and S.p.x==0 and S.p.y==0 and S.p.z==0,tostring(st.next).." "..S.p.z)
    local coalInChest=S.chestNames["minecraft:coal"]==true
    if use then
        check("12 Kohle verbrannt",(st.coal or 0)==12,st.coal)
        check("keine Kohle in Ausgabekiste",not coalInChest)
        check("Status meldet coal",S.last and S.last.coal==12 and S.last.useCoal==true)
    else
        check("nichts verbrannt",(st.coal or 0)==0,st.coal)
        check("Kohle abgeliefert",coalInChest)
    end
    print("  Fuel Ende: "..S.fuel.."  (Start "..fuel0..")")
end
print(pass.." bestanden, "..failc.." fehlgeschlagen")
