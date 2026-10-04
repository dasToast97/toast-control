package.path="/home/claude/toast/test/?.lua;"..package.path
local Sim=require("sim")
local pass,failc=0,0
local function check(name,cond,info)
    if cond then pass=pass+1;print("  PASS "..name) else failc=failc+1;print("  FAIL "..name.."  "..tostring(info or "")) end
end
-- Bildschirm, der den Text mitschreibt
local function screen(G,W,H)
    local rows,cx,cy={},1,1
    for y=1,H do rows[y]=string.rep(" ",W) end
    local sc={getSize=function()return W,H end,isColor=function()return true end,setBackgroundColor=function()end,setTextColor=function()end,
        clear=function()for y=1,H do rows[y]=string.rep(" ",W) end end,setCursorPos=function(x,y)cx,cy=x,y end,
        setCursorBlink=function()end,
        write=function(s)if cy<1 or cy>H then return end;s=tostring(s):gsub("[\128-\255]","="):gsub("[\1-\31]","*");local r=rows[cy];rows[cy]=(r:sub(1,cx-1)..s..r:sub(cx+#s)):sub(1,W);cx=cx+#s end,
        text=function() return table.concat(rows,"\n") end,rows=rows}
    return sc
end
-- Kisten-Nachbau (Generic Inventory API)
local function chest(size,slots)
    local inv={}
    function inv.size() return size end
    function inv.list() local t={};for s,it in pairs(slots) do t[s]={name=it[1],count=it[2]} end;return t end
    function inv.getItemDetail(s) local it=slots[s];if not it then return nil end
        local names={["minecraft:iron_ingot"]="Iron Ingot",["minecraft:cobblestone"]="Cobblestone",["minecraft:diamond"]="Diamond",["minecraft:ender_pearl"]="Ender Pearl"}
        return {name=it[1],count=it[2],displayName=names[it[1]] or it[1],maxCount=it[1]=="minecraft:ender_pearl" and 16 or 64} end
    return inv
end
local A={};for i=1,27 do A[i]={"minecraft:cobblestone",64} end          -- voll
local B={[1]={"minecraft:iron_ingot",64},[2]={"minecraft:iron_ingot",10},[5]={"minecraft:diamond",3}}
local Cc={[1]={"minecraft:iron_ingot",30},[2]={"minecraft:ender_pearl",16}}
local PER={top="modem",["minecraft:chest_0"]="minecraft:chest",["minecraft:barrel_1"]="minecraft:barrel",["minecraft:chest_2"]="minecraft:chest",
    ["turtle_3"]="turtle"}
local INV={["minecraft:chest_0"]=chest(27,A),["minecraft:barrel_1"]=chest(27,B),["minecraft:chest_2"]=chest(54,Cc)}

print("L1 Lager-Computer liest Kisten, meldet sich bei der Zentrale")
local S=Sim.new({config=[[return {role="storage",name="Hauptlager",controllerId=4,gps={host=false},storage={interval=10,warnAt=90,names={["minecraft:chest_2"]="Erze"}}}]]})
S.files["/toast/toast_storage.lua"]=io.open("/home/claude/toast/toast_storage.lua"):read("a")
S.files["/toast/toast_ui.lua"]=io.open("/home/claude/toast/toast_ui.lua"):read("a")
S.polling=false
local TERM
local orig=Sim.env
Sim.env=function(S2) local G=orig(S2);G.turtle=nil;G.os.getComputerID=function()return 60 end
    do local n=0;local c={};G.colors=setmetatable({},{__index=function(_,k)if not c[k] then n=n+1;c[k]=2^n end;return c[k] end}) end
    TERM=screen(G,39,13);for k,v in pairs(TERM) do G.term[k]=v end
    G.textutils.formatTime=function()return "9:15" end;G.os.time=function()return 9 end
    G.os.pullEventRaw=G.os.pullEvent
    G.rednet.broadcast=function(msg,p) S2.beacons=(S2.beacons or 0)+1;S2.lastBeacon=msg end
    G.peripheral.getNames=function() local t={};for n in pairs(PER) do t[#t+1]=n end;table.sort(t);return t end
    G.peripheral.getType=function(n) return PER[n] end
    G.peripheral.hasType=function(n,t) return t=="inventory" and INV[n]~=nil end
    G.peripheral.find=function(t,fl) if t=="modem" then local m={isWireless=function()return true end,_side="top"};if not fl or fl("top",m) then return m end end end
    G.peripheral.wrap=function(n) if n=="top" then return {isWireless=function()return true end,open=function()end,close=function()end,isOpen=function()return false end,transmit=function()end} end;return INV[n] end
    G.keys.getName=function(k) return k end
    return G end
S.actions={{t=12,fn=function(S) table.insert(S.queue,table.pack("char","i")) ;table.insert(S.queue,table.pack("char","r")) end}}
Sim.run(S,30)
Sim.env=orig
local b=S.lastBeacon
local st=b and b.info and b.info.stats or {}
check("meldet sich als Lager",b and b.info.role=="storage" and b.controllerId==4,tostring(S.beacons))
check("3 Kisten, Turtle ignoriert",st.count==3,st.count)
local byN={};for _,c in ipairs(st.chests or {}) do byN[c.n]=c end
check("volle Kiste = 100%",byN["Kiste 0"] and byN["Kiste 0"].p==100,byN["Kiste 0"] and byN["Kiste 0"].p)
check("eigener Name",byN["Erze"]~=nil)
check("Fass erkannt",byN["Fass 1"]~=nil)
local iron;for _,it in ipairs(st.items or {}) do if it.id=="minecraft:iron_ingot" then iron=it end end
check("Eisen zusammengezaehlt (104) in 2 Kisten",iron and iron.c==104 and #iron.w==2 and iron.n=="Iron Ingot",iron and iron.c)
local pearl=byN["Erze"]
check("Enderperlen: 16er-Stapel zaehlt als voll",pearl and pearl.p==math.floor((30/64+1)/54*100+0.5),pearl and pearl.p)
local scr=TERM.text()
print(scr)
check("Anzeige: Kopf mit Fuellstand + Uhr",scr:find("TOAST LAGER",1,true) and scr:find("09:15",1,true),scr)
check("Suche per Tastatur (\"ir\" -> Iron)",scr:find("Suche: ir",1,true) and scr:find("Iron Ingot",1,true) and not scr:find("Cobblestone",1,true),scr)

print("L2 Zentrale: Reiter Lager, Inhalt suchen, wo liegt es")
S=Sim.new({config=""});local G=Sim.env(S)
do local n=0;local c={};G.colors=setmetatable({},{__index=function(_,k)if not c[k] then n=n+1;c[k]=2^n end;return c[k] end}) end
for _,n in ipairs({"toast_common.lua","toast_model.lua","toast_ui.lua"})do S.files["/toast/"..n]=io.open("/home/claude/toast/"..n):read("a")end
G.os.getComputerID=function()return 4 end;G.turtle=nil
G.textutils.formatTime=function()return "9:15" end;G.os.time=function()return 9 end
local cfg=G.dofile("/toast/toast_common.lua").load({role="controller",controllerId=4})
local model=G.dofile("/toast/toast_model.lua").new(cfg)
check("Beacon angenommen",model.remote(60,b,"toast.control.remote.v1"))
local UI=G.dofile("/toast/toast_ui.lua")
local sc=screen(G,39,19)
local ui=UI.new(sc,cfg)
ui.draw(model.fleet(),true,"")
check("Reiter Lager da",sc.text():find("Lager",1,true)~=nil,sc.text())
ui.action("filter:store");ui.draw(model.fleet(),true,"")
local t=sc.text()
check("Kisten mit Prozent",t:find("Hauptlager",1,true) and t:find("Erze",1,true) and t:find("100%",1,true),t)
ui.action("sview:items");ui.draw(model.fleet(),true,"")
t=sc.text()
check("Inhalt: Cobblestone oben (meiste)",t:find("Cobblestone",1,true) and t:find("Iron Ingot",1,true),t)
ui.char("d");ui.char("i");ui.draw(model.fleet(),true,"")
t=sc.text()
check("Suche \"di\" -> nur Diamant",t:find("Diamond",1,true) and not t:find("Iron Ingot",1,true),t)
local act;for _,bt in ipairs(ui.buttons) do if bt.action=="sitem:minecraft:diamond" then act=bt end end
check("Item antippbar",act~=nil)
ui.action(ui.click(act.x,act.y));ui.draw(model.fleet(),true,"")
t=sc.text()
check("Wo liegt es: Fass 1",t:find("Fass 1",1,true) and t:find("Gesamt",1,true),t)
check("q beendet im Lager-Reiter nicht (Suche)",ui.textInput()==true)
ui.action(ui.key("backspace"));ui.draw(model.fleet(),true,"")
check("zurueck zur Liste",ui.storeItem==nil)
check("Netz zeigt Lager",model.fleet().nodes.entries[60].role=="storage")
-- Pocket-Breite
local ps=screen(G,26,20);local pui=UI.new(ps,cfg);pui.action("filter:store");pui.draw(model.fleet(),true,"")
check("Pocket: Kisten passen",ps.text():find("Erze",1,true)~=nil,ps.text())
print(ps.text())
-- Update erreicht das Lager
S.sent={};model.startUpdate(nil,"9.9")
local up=0;for _,m in ipairs(S.sent) do if m.id==60 and m.msg.kind=="update" then up=up+1 end end
check("Update auch fuers Lager",up==1,up)

print("L3 Langsames Auslesen (viele Kisten): Lebenszeichen kommt trotzdem regelmaessig")
S=Sim.new({config=[[return {role="storage",name="Hauptlager",controllerId=4,gps={host=false},storage={interval=10,warnAt=90,names={}}}]]})
S.files["/toast/toast_storage.lua"]=io.open("/home/claude/toast/toast_storage.lua"):read("a")
S.files["/toast/toast_ui.lua"]=io.open("/home/claude/toast/toast_ui.lua"):read("a")
S.polling=false
local beaconTimes={}
Sim.env=function(S2) local G=orig(S2);G.turtle=nil;G.os.getComputerID=function()return 61 end
    do local n=0;local c={};G.colors=setmetatable({},{__index=function(_,k)if not c[k] then n=n+1;c[k]=2^n end;return c[k] end}) end
    local T=screen(G,39,13);for k,v in pairs(T) do G.term[k]=v end
    G.os.pullEventRaw=G.os.pullEvent
    G.rednet.broadcast=function(msg,p) beaconTimes[#beaconTimes+1]=S2.T end
    G.peripheral.getNames=function() local t={};for n in pairs(PER) do t[#t+1]=n end;table.sort(t);return t end
    G.peripheral.getType=function(n) return PER[n] end
    G.peripheral.hasType=function(n,t) return t=="inventory" and INV[n]~=nil end
    G.peripheral.find=function(t,fl) if t=="modem" then local m={isWireless=function()return true end,_side="top"};if not fl or fl("top",m) then return m end end end
    -- jede Kiste braucht 4 s zum Auslesen (wie bei sehr vielen Kisten am Kabel)
    G.peripheral.wrap=function(n) if n=="top" then return {isWireless=function()return true end,open=function()end,close=function()end,isOpen=function()return false end,transmit=function()end} end
        local inv=INV[n];if not inv then return nil end
        return {size=inv.size,getItemDetail=inv.getItemDetail,list=function() G.sleep(4);return inv.list() end} end
    G.keys.getName=function(k) return k end
    return G end
Sim.run(S,60)
Sim.env=orig
local maxGap=0;for k=2,#beaconTimes do maxGap=math.max(maxGap,beaconTimes[k]-beaconTimes[k-1]) end
check("mind. 8 Lebenszeichen in 60 s",#beaconTimes>=8,#beaconTimes)
check("nie mehr als 10 s Pause (Zentrale: offline erst nach 30 s)",maxGap<=10,maxGap)

print(pass.." bestanden, "..failc.." fehlgeschlagen")
if failc>0 then os.exit(1) end
