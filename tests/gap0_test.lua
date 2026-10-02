package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,fail=0,0
local function check(n,c,i)if c then pass=pass+1 else fail=fail+1;print("  FAIL "..n.."  "..tostring(i))end end
local function cfg(H,L,T,side)return ([[return {role="auto",job="mining",controllerId=4,name="G0",autoDiscover=true,autoPairPockets=true,
 devices={},pocketIds={},display={monitor="auto",textScale=0.5,pageSize=0},network={pollInterval=1,staleAfter=15,commandTimeout=10,maxDevices=256},
 farm={width=3,length=3,crop="wheat",interval=5,seedReserve=16,radioTimeout=10,water={}},
 mine={length=%d,height=%d,tunnels=%d,gap=0,side="%s",fuelTarget=2000,radioTimeout=0,freeSlots=2,digRetries=16,protectedBlocks={}}}]]):format(L,H,T,side or "right")end
local function oreify(S)
  local n=0
  for _,k in ipairs({"dig","digUp","digDown"})do local f=S.turtle[k];S.turtle[k]=function()local ok,w=f();if ok then n=n+1
    for i=1,16 do local it=S.inv[i];if it and it.name=="minecraft:cobblestone" then it.name="minecraft:ore"..(n%40) end end end;return ok,w end end
end
local function run(H,L,T,opts)
  opts=opts or {}
  local S=Sim.new({config=cfg(H,L,T,opts.side),fuel=200000,actions={{t=2,fn=function(S)Sim.cmd(S,"start",10)end}}})
  S.protocol="toast.mine.v1";if opts.full then oreify(S) end
  if opts.crash then S.crashAtMove=opts.crash end
  Sim.run(S,20000)
  local st=load("return "..S.files["/toast_mining_state"])()
  local sx=opts.side=="left" and -1 or 1
  local miss,outside=0,0
  for x=0,T-1 do for z=1,L do for y=0,-(H-1),-1 do if S.world[S.key(sx*x,y,z)]~=false then miss=miss+1 end end end end
  -- nichts ausserhalb des Blocks: Ganghoehe, Seiten, hinten, vorne (ausser Basis)
  for x=-1,T do for z=0,L+1 do for y=1,-H,-1 do
    local inside=x>=0 and x<T and z>=1 and z<=L and y<=0 and y>=-(H-1)
    local base=x==0 and z==0 and y==0
    if not inside and not base and S.world[S.key(sx*x,y,z)]==false then outside=outside+1 end
  end end end
  local ok=st.next==math.ceil(H/3)*L*T+1 and miss==0 and outside==0 and S.p.x==0 and S.p.y==0 and S.p.z==0
  return ok,S,st,miss,outside
end
print(("%-14s %8s %10s %s"):format("Mine","Fuel","Fuel/Blk","Ergebnis"))
for _,H in ipairs({1,2,3,4,6,9,20,64}) do
  for _,T in ipairs({2,3,5}) do
    local L=H>=20 and 6 or 12
    for _,full in ipairs({false,true}) do
      local ok,S,st,miss,out=run(H,L,T,{full=full})
      local name=H.."x"..L.."x"..T..(full and " voll" or "")
      if full or T==5 then print(("%-14s %8d %10.2f %s"):format(name,S.moves,S.moves/(H*L*T),ok and "fertig" or ("FEHLER miss="..miss.." aussen="..out.." "..tostring(S.last and S.last.status).." "..tostring(S.last and S.last.detail)))) end
      check(name,ok,"miss="..miss.." aussen="..out.." "..tostring(S.last and S.last.detail))
    end
  end
end
print("Abstand 0, Seite links, volles Inventar")
local ok,S,st,miss,out=run(6,12,4,{side="left",full=true})
check("links",ok,"miss="..miss.." aussen="..out.." "..tostring(S.last and S.last.detail))
print("Abstand 0, Absturz mitten im Schritt")
for _,c in ipairs({17,60,133}) do
  ok,S,st,miss,out=run(9,10,3,{crash=c,full=true})
  check("Absturz bei Zug "..c,ok,"miss="..miss.." aussen="..out.." "..tostring(S.last and S.last.detail))
end
print(("\n%d bestanden, %d fehlgeschlagen"):format(pass,fail))
