package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local FILE=os.getenv("MINEFILE")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1;print("  PASS "..n)else fail=fail+1;print("  FAIL "..n.."  "..tostring(i))end end
local function cfg(H,L,T,G)return ([[return {role="auto",job="mining",controllerId=4,name="R",autoDiscover=true,autoPairPockets=true,
 devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
 mine={length=%d,height=%d,tunnels=%d,gap=%d,fuelTarget=2000,radioTimeout=0,freeSlots=2,digRetries=16,protectedBlocks={}}}]]):format(L,H,T,G)end
-- Jeder abgebaute Block ergibt eine von 40 Sorten -> Inventar laeuft schnell voll -> viele Heimfahrten
local function oreify(S)
  local n=0
  for _,k in ipairs({"dig","digUp","digDown"})do local f=S.turtle[k];S.turtle[k]=function()local ok,w=f();if ok then n=n+1
    for i=1,16 do local it=S.inv[i];if it and it.name=="minecraft:cobblestone" then it.name="minecraft:ore"..(n%40) end end end;return ok,w end end
end
local total={}
print(("%-10s %8s %8s %8s %s"):format("Mine","Fuel","Heim","Ergebnis",""))
for _,c in ipairs({{3,30,3,2},{6,25,3,2},{9,20,4,1},{20,15,3,2},{64,8,3,2},{4,30,2,0}}) do
  local H,L,T,G=table.unpack(c)
  local S=Sim.new({config=cfg(H,L,T,G),fuel=100000,mineFile=FILE,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
  S.protocol="toast.mine.v1";oreify(S)
  local homes=0;local du=S.turtle.dropDown;S.turtle.dropDown=function(...)if S.p.x==0 and S.p.z==0 and S.p.y==0 then homes=homes+1 end;return du(...)end
  Sim.run(S,20000)
  local st=load("return "..S.files["/toast_mining_state"])()
  local miss=0
  for t=0,T-1 do for z=1,L do for y=0,-(H-1),-1 do if S.world[S.key(t*(G+1),y,z)]~=false then miss=miss+1 end end end end
  local wall,above=0,0
  for t=0,T-2 do for gx=1,G do for z=2,L-1 do for y=0,-(H-1),-1 do
    if S.world[S.key(t*(G+1)+gx,y,z)]==false then wall=wall+1 end end end end end
  for x=0,(T-1)*(G+1) do for z=0,L+1 do if S.world[S.key(x,-H,z)]==false then above=above+1 end end end
  for x=0,(T-1)*(G+1) do for y=-(H-1),0 do if x>0 and S.world[S.key(x,y,0)]==false then wall=wall+1 end end end
  local done=st.next==math.ceil(H/3)*L*T+1 and miss==0 and S.p.x==0 and S.p.z==0 and wall==0 and above==0
  if wall>0 or above>0 then print("    Waende durchbrochen: "..wall.."  ueber Ganghoehe: "..above) end
  local res=done and "fertig" or ("HAENGT: "..tostring(S.last and S.last.status).." / "..tostring(S.last and S.last.detail))
  print(("%-10s %8d %8d   %s"):format(H.."x"..L.."x"..T,S.moves,homes,res))
  check(H.."x"..L.."x"..T.." fertig",done,res)
end
print("Kies im Rueckweg + volles Inventar")
local S=Sim.new({config=cfg(3,20,2,2),fuel=100000,mineFile=FILE,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
S.protocol="toast.mine.v1"
-- Inventar komplett voll mit Muell, dann Kies in den bereits freien Gang werfen
S.actions[#S.actions+1]={t=25,fn=function(S)
  for i=1,15 do S.inv[i]={name="minecraft:junk"..i,count=64} end
  for z=1,20 do if S.world[S.key(0,-1,z)]==false and not (S.p.x==0 and S.p.z==z) then S.world[S.key(0,-1,z)]="minecraft:gravel" end end
  for x=0,3 do if S.world[S.key(x,-1,1)]==false and not (S.p.x==x and S.p.z==1) then S.world[S.key(x,-1,1)]="minecraft:gravel" end end end}
Sim.run(S,100000);local st=load("return "..S.files["/toast_mining_state"])()
check("trotz Kies + vollem Inventar heimgekommen und fertig",st.next==41 and S.p.x==0 and S.p.z==0,
  tostring(S.last and S.last.status).." / "..tostring(S.last and S.last.detail))
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
