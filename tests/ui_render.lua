package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local S=Sim.new({config=""});local G=Sim.env(S);do local n=0;local c={};G.colors=setmetatable({},{__index=function(_,k)if not c[k] then n=n+1;c[k]=2^n end;return c[k] end}) end;G.turtle=nil;G.os.getComputerID=function()return 4 end
for _,n in ipairs({"toast_common.lua","toast_model.lua","toast_ui.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
G.textutils.formatTime=function()return "14:05" end;G.os.time=function()return 14 end
local cfg=G.dofile("/toast/toast_common.lua").load({role="controller",controllerId=4})
local UI=G.dofile("/toast/toast_ui.lua")
local function fleet()
  local e={}
  local function add(id,job,label,on,d) e[id]={job=job,label=label,online=on,data=d} end
  add(5,"farm","Weizen Nord",true,{status="Ernte",detail="Reihe 3 / 9",total=1240,harvested=830,rounds=12,seeds=48,scanned=27,cells=81,fuel=1800,roundYield=64})
  add(6,"farm","Karotten",true,{status="Warten",detail="Naechster Feldscan startet automatisch.",total=560,harvested=400,rounds=7,seeds=60,scanned=40,cells=40,fuel=950})
  add(12,"mining","Mine Nord",true,{status="Abbau",detail="Gang 2 / 5",total=9800,harvested=12450,rounds=1,freeSlots=9,scanned=140,cells=500,fuel=1840,chunks=1,chunkFuel=2400})
  add(13,"mining","Mine Sued",true,{status="Lava erkannt",fault="Bewegung blockiert: Movement obstructed",detail="Neuer Versuch in 20s",total=300,harvested=420,rounds=0,freeSlots=12,scanned=20,cells=300,fuel=600})
  add(14,"mining","Nether Mine",false,{status="Abbau",total=0,harvested=0,scanned=0,cells=300})
  add(15,"mining","Mine Ost",true,{status="Rueckkehr",detail="Fahre zur Basis",total=2000,harvested=3100,rounds=2,freeSlots=1,scanned=200,cells=300,fuel=900})
  return {ids={5,6,12,13,14,15},entries=e}
end
local function screen(W,H,color)
  local rows,cx,cy={},1,1
  for y=1,H do rows[y]=string.rep(" ",W) end
  local bg,fg
  return {getSize=function()return W,H end,isColor=function()return color end,setBackgroundColor=function(c)bg=c end,setTextColor=function(c)fg=c end,
    clear=function()for y=1,H do rows[y]=string.rep(" ",W) end end,setCursorPos=function(x,y)cx,cy=x,y end,
    write=function(s)if cy<1 or cy>H then return end;s=s:gsub("\7","*");s=s:gsub("\143",fg==G.colors.lime and "=" or "_"):gsub("\145","(") :gsub("\157",")");if BARS and bg==G.colors.lime then s=s:gsub(" ","#") elseif BARS and (bg==G.colors.gray or bg==G.colors.brown) then s=s:gsub(" ",".") end;local r=rows[cy];rows[cy]=(r:sub(1,cx-1)..s..r:sub(cx+#s)):sub(1,W);cx=cx+#s end,
    dump=function(title)print(title);print("+"..string.rep("-",W).."+");for y=1,H do print("|"..rows[y].."|") end;print("+"..string.rep("-",W).."+")end}
end
local mode=arg[1] or "all"
BARS=os.getenv("BARS")
if mode=="pocket" or mode=="all" then
  local sc=screen(26,20,true);local ui=UI.new(sc,cfg);ui.draw(fleet(),true,"");sc.dump("POCKET 26x20 - Uebersicht")
  ui.action("id:12");ui.draw(fleet(),true,"");sc.dump("POCKET - Detail Mine")
  ui.action("id:5");ui.draw(fleet(),true,"");sc.dump("POCKET - Detail Farm")
  ui.action("group");ui.action("filter:mining");ui.draw(fleet(),true,"");sc.dump("POCKET - Reiter Mine")
end
if mode=="zentrale" or mode=="all" then
  local sc=screen(57,24,true);local ui=UI.new(sc,cfg);ui.draw(fleet(),true,"START: 3 Turtle(s), warte auf ACK");sc.dump("ZENTRALE 57x24")
end
if mode=="info" or mode=="all" then
  local sc=screen(57,24,true);UI.drawInfo(sc,fleet(),true,{});sc.dump("INFOSCREEN 57x24")
  sc=screen(29,19,true);UI.drawInfo(sc,fleet(),true,{});sc.dump("INFOSCREEN klein 29x19");sc=screen(39,13,true);UI.drawInfo(sc,fleet(),true,{});sc.dump("INFOSCREEN 39x13")
end
if mode=="sizes" then
  for _,c in ipairs({{"ZENTRALE 3x4 (Schrift 1)",39,19,"ctl"},{"ZENTRALE 4x8 (Schrift 1)",82,26,"ctl"},{"INFO 3x4 (Schrift 1)",39,19,"info"},{"INFO 4x8 (Schrift 1.5)",55,17,"info"}}) do
    local sc=screen(c[2],c[3],true)
    if c[4]=="ctl" then local ui=UI.new(sc,cfg);ui.draw(fleet(),true,"") else UI.drawInfo(sc,fleet(),true,{}) end
    sc.dump(c[1])
  end
end
if mode=="info2" then
  local f=fleet();f.entries[12].data.tunnels=5
  local sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},12);sc.dump("INFOSCREEN 3x4 - Turtle #12 (Mine)")
  sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},5);sc.dump("INFOSCREEN 3x4 - Turtle #5 (Farm)")
  sc=screen(82,26,true);UI.drawInfo(sc,f,true,{},13);sc.dump("INFOSCREEN 4x8 - Turtle #13 (Fehler)")
  sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},"farm");sc.dump("INFOSCREEN 3x4 - nur Farmen")
  sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},99);sc.dump("INFOSCREEN - unbekannte Turtle")
end
if mode=="keys" then
  for _,sz in ipairs({{26,20},{39,19},{82,26}}) do
    local sc=screen(sz[1],sz[2],true);local ui=UI.new(sc,cfg);ui.kbd=true;ui.draw(fleet(),true,"")
    ui.action(ui.key("down"));ui.action(ui.key("down"));ui.draw(fleet(),true,"");sc.dump("TASTATUR "..sz[1].."x"..sz[2].." - Markierung auf 2.")
    if sz[1]==26 then
      ui.action(ui.key("enter"));ui.draw(fleet(),true,"");sc.dump("Enter -> Detail")
      ui.action(ui.key("down"));ui.draw(fleet(),true,"");sc.dump("Runter -> naechste Turtle im Detail")
      ui.action(ui.key("left"));ui.action(ui.key("right"));ui.draw(fleet(),true,"");sc.dump("Links zurueck, Rechts -> Reiter Farm")
      assert(ui.filter=="farm")
      print(ui.action(ui.char("r")),"<- erstes R (nil erwartet)");ui.draw(fleet(),true,"");sc.dump("R -> Sicherheitsabfrage")
      assert(ui.action(ui.char("r"))=="reset","2x R = reset")
      ui.action(ui.char("h"));ui.draw(fleet(),true,"");sc.dump("Hilfe")
      assert(ui.char("x")=="redraw" and not ui.help)
    end
  end
end
if mode=="jobs" then
  local f=fleet()
  f.entries[20]={job="tree",label="Birken",online=true,data={status="Faellt Baum",detail="Baum 3 / 8",total=340,harvested=68,rounds=4,saplings=29,scanned=3,cells=8,fuel=820}}
  f.entries[21]={job="mob",label="Zombiefarm",online=true,data={status="Kampf",detail="Mobs werden besiegt",total=1520,hits=980,mobMode="farm",lastHit=2,scanned=0,cells=0,fuel=0,freeSlots=14}}
  f.entries[22]={job="mob",label="Wache Tor",online=true,data={status="Wache",detail="Halte Wache.",total=12,hits=30,mobMode="guard",scanned=0,cells=0,fuel=0,freeSlots=15}}
  f.ids={5,6,12,13,14,15,20,21,22}
  for _,sz in ipairs({{26,20},{39,19},{82,26}}) do
    local sc=screen(sz[1],sz[2],true);local ui=UI.new(sc,cfg);ui.draw(f,true,"");sc.dump("ZENTRALE "..sz[1].."x"..sz[2].." alle Jobs")
  end
  local sc=screen(26,20,true);local ui=UI.new(sc,cfg);ui.draw(f,true,"");ui.action("filter:tree");ui.draw(f,true,"");sc.dump("POCKET Reiter Holz")
  ui.action("filter:all");ui.action("id:21");ui.draw(f,true,"");sc.dump("POCKET Detail Mobfarm")
  ui.action("id:20");ui.draw(f,true,"");sc.dump("POCKET Detail Holz")
  for _,sz in ipairs({{39,19},{57,24},{82,26}}) do
    sc=screen(sz[1],sz[2],true);UI.drawInfo(sc,f,true,{});sc.dump("INFO "..sz[1].."x"..sz[2].." alle Jobs")
  end
  sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},"mob");sc.dump("INFO nur Mobs")
  sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},21);sc.dump("INFO Turtle #21 Mobfarm")
  sc=screen(39,19,true);UI.drawInfo(sc,f,true,{},20);sc.dump("INFO Turtle #20 Holz")
end
if mode=="net" then
  local f=fleet()
  f.nodes={ids={40,41,50,60},entries={
    [40]={role="repeater",label="Repeater Turm",online=true,data={toast="3.4",pos={x=120,y=200,z=-50,src="GPS"},stats={repeated=1532,gps=88}}},
    [41]={role="gps",label="",online=true,data={toast="3.3",pos={x=124,y=204,z=-50,src="Config"},stats={gps=420}}},
    [50]={role="info",label="Info Halle",online=true,data={toast="3.4",pos={x=10,y=70,z=5,src="Config"}}},
    [60]={role="pocket",label="",online=false,data={toast="3.4"}}}}
  for _,sz in ipairs({{26,20},{82,26}}) do
    local sc=screen(sz[1],sz[2],true);local ui=UI.new(sc,cfg);ui.draw(f,true,"");ui.action("filter:net");ui.draw(f,true,"");sc.dump("NETZ "..sz[1].."x"..sz[2])
    ui.action("id:41");ui.draw(f,true,"");sc.dump("NETZ Detail GPS "..sz[1].."x"..sz[2])
  end
end
