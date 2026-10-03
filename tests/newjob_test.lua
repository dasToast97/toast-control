package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
local function tail(S,n)local t={}for i=math.max(1,#S.log-(n or 8)),#S.log do t[#t+1]=S.log[i]end;return table.concat(t," | ")end
local CFG=[[return {role="turtle",job="mining",controllerId=4,name="Mine A",
  network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
  mine={length=4,height=2,tunnels=1,gap=1,side="right",fuelTarget=100,radioTimeout=10,freeSlots=2,digRetries=16,protectedBlocks={}},
  base={set=true,x=100,y=64,z=-20,facing="north"}}]]
print("N1 Mine fertig -> an der Turtle N -> Menue -> neue Laenge -> neuer Auftrag laeuft")
local S=Sim.new({config=CFG,actions={
    {t=2,fn=function(S)Sim.cmd(S,"start",10)end},
    {t=120,fn=function(S)S.doneBefore=S.last and S.last.status
        -- Menue: 3 = Mine, Laenge 7, Rest Enter, Kohle/Kisten Enter; dann Enter = starten; Basis? j
        S.input={"3","7","","","","","","","j"}
        table.insert(S.queue,table.pack("char","n")) end},
    {t=200,fn=function(S)Sim.cmd(S,"start",11)end}}})
S.files["/toast/toast_setup.lua"]=io.open("/home/claude/toast/toast_setup.lua"):read("a")
S.protocol="toast.mine.v1"
Sim.run(S,600)
local st=load("return "..S.files["/toast_mining_state"])()
local cfg=load(S.files["/toast.config.lua"])()
check("vorher fertig",S.doneBefore=="Fertig",S.doneBefore)
check("Config: neue Laenge 7",cfg.mine.length==7,cfg.mine.length)
check("neuer Auftrag komplett abgebaut",st.next and st.next>7 and S.last and S.last.status=="Fertig",tostring(st.next).." "..tail(S))
check("gaenge bis z=7 frei",S.world[S.key(0,0,7)]==false,tostring(S.world[S.key(0,0,7)]))
check("Position: an der Basis",S.last and S.last.rel and S.last.rel.fwd==0)

print("P1 Positionsrechnung")
local G=Sim.env(S)
local common=G.dofile("/toast/toast_common.lua")
local c={base={set=true,x=100,y=64,z=-20,facing="north"},mine={side="right"},farm={side="left"},tree={side="right"},mob={side="right"}}
local rel,abs=common.position(c,"mining",3,-2,10)       -- 10 vor, 3 rechts, 2 hoch
check("Mine rel",rel.fwd==10 and rel.right==3 and rel.up==2)
check("Mine abs (Norden: vor=-Z, rechts=+X)",abs.x==103 and abs.y==66 and abs.z==-30,abs.x..","..abs.y..","..abs.z)
rel,abs=common.position(c,"farm",2,0,5)                  -- Feld links
check("Farm links: rechts=-2",rel.right==-2 and abs.x==98 and abs.z==-25,rel.right.." "..abs.x..","..abs.z)
c.base.facing="east"
rel,abs=common.position(c,"tree",1,4,6)                  -- Osten: vor=+X, rechts=+Z
check("Holz Osten",abs.x==106 and abs.z==-19 and abs.y==68,abs.x..","..abs.y..","..abs.z)
c.base.set=false
rel,abs=common.position(c,"mob",0,0,0)
check("ohne Basis keine Koordinaten",abs==nil)
S.files["/toast/toast_ui.lua"]=io.open("/home/claude/toast/toast_ui.lua"):read("a");G.colors=setmetatable({},{__index=function()return 1 end});G.term=G.term or {}
local UI=G.dofile("/toast/toast_ui.lua")
check("Text",UI.posText({rel={fwd=12,right=-3,up=5}})=="12 vor 3 li 5 hoch",UI.posText({rel={fwd=12,right=-3,up=5}}))
check("Koordinaten-Text",UI.coordText({pos={x=1,y=2,z=3}})=="X1 Y2 Z3")
print(pass.." bestanden, "..failc.." fehlgeschlagen")
