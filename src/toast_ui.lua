local common=dofile("/toast/toast_common.lua")
local M={}
function M.new(screen,cfg)
    local ui={filter="all",selected=nil,page=1,buttons={},ids={}}
    local function num(n)return common.number(n)end
    local function short(n)
        n=num(n);if math.abs(n)>=1000000 then return string.format("%.1fM",n/1000000)end
        if math.abs(n)>=10000 then return string.format("%.1fk",n/1000)end
        return tostring(math.floor(n))
    end
    function ui.setScreen(s)screen=s end
    function ui.draw(fleet,link,notice)
        local w,h=screen.getSize();ui.buttons={}
        screen.setBackgroundColor(colors.black);screen.setTextColor(colors.white);screen.clear()
        local function text(x,y,s,fg,bg)
            if x<1 or x>w or y<1 or y>h then return end
            screen.setCursorPos(x,y);screen.setTextColor(fg or colors.white);screen.setBackgroundColor(bg or colors.black)
            screen.write(tostring(s):sub(1,w-x+1))
        end
        local function button(x,y,width,label,action,bg,enabled)
            local color=enabled and bg or colors.gray
            text(x,y,string.rep(" ",width),colors.white,color)
            text(x,y,tostring(label):sub(1,width),colors.white,color)
            ui.buttons[#ui.buttons+1]={x=x,y=y,w=width,action=action,enabled=enabled}
        end
        if w<26 or h<18 then
            text(1,1,"TOAST CONTROL",colors.cyan);text(1,3,"Minimum: 26 x 18 Zeichen",colors.yellow)
            text(1,5,"Monitor vergroessern /");text(1,6,"textScale=0.5 einstellen.");return
        end
        local entries=fleet.entries or {};local ids={}
        local farms,mines,online,faults,totalFarm,totalMine,fuel,seeds,slots=0,0,0,0,0,0,0,0,0
        local unlimited=false
        local chunkFuel=0
        for _,id in ipairs(fleet.ids or {})do
            local e=entries[id] or {};local d=e.data or {}
            if (ui.filter=="all" or e.job==ui.filter) and link and e.online and num(d.chunks)>0 then chunkFuel=chunkFuel+num(d.chunkFuel) end
            if e.job=="farm" then farms=farms+1 elseif e.job=="mining" then mines=mines+1 end
            if ui.filter=="all" or e.job==ui.filter then
                ids[#ids+1]=id
                if link and e.online then online=online+1 end
                if d.fault or d.recovery then faults=faults+1 end
                if e.job=="farm" then totalFarm=totalFarm+num(d.total) elseif e.job=="mining" then totalMine=totalMine+num(d.total) end
                seeds=seeds+num(d.seeds);slots=slots+num(d.freeSlots)
                if d.fuel=="unlimited" then unlimited=true else fuel=fuel+num(d.fuel) end
            end
        end
        ui.ids=ids
        if ui.selected and not common.contains(ids,ui.selected)then ui.selected=nil end
        local selected=ui.selected and entries[ui.selected];local data=selected and selected.data or {}
        local title=ui.filter=="farm" and "FARM" or ui.filter=="mining" and "MINING" or "ALLE"
        text(1,1,"TOAST CONTROL / "..(link and "ONLINE" or "OFFLINE"),colors.cyan)
        text(1,2,"Farm "..farms.." | Mine "..mines.." | "..online.."/"..#ids..(faults>0 and (" | Fehler "..faults) or ""),
            faults>0 and colors.orange or colors.lightGray)
        local third=math.floor(w/3)
        for i,v in ipairs({{"ALLE","all"},{"FARM","farm"},{"MINING","mining"}})do
            button(1+(i-1)*third,3,i==3 and w-2*third or third,v[1],"filter:"..v[2],
                ui.filter==v[2] and colors.blue or colors.gray,true)
        end
        local label=selected and (selected.label~="" and selected.label or "Turtle") or title.." TURTLES"
        if ui.selected then label=label.." #"..ui.selected end
        text(1,4,label,colors.cyan)
        local statusColor=(data.fault or data.recovery) and colors.orange or colors.yellow
        text(1,5,selected and (link and selected.online and tostring(data.status or "Verbunden") or "OFFLINE / alte Werte") or "Gemeinsame Uebersicht",
            selected and statusColor or colors.yellow)
        text(1,6,selected and tostring(data.detail or "Noch keine Daten") or "START / STOP / RESET fuer "..title,colors.lightGray)
        if selected then
            text(1,7,(selected.job=="farm" and "Ernte " or "Beute ")..short(data.total)..
                (selected.job=="farm" and " | Saat "..short(data.seeds) or " | Slots "..short(data.freeSlots)))
            text(1,8,"Fuel "..(data.fuel=="unlimited" and "unbegrenzt" or short(data.fuel)).." | "..(selected.job=="farm" and "Runden " or "Gaenge ")..short(data.rounds)
                ..(data.chunks and (" | Chunks "..(data.chunks>0 and (data.chunks.." -"..short(data.chunkFuel).."/h") or "aus")) or ""))
            local pc=math.floor(math.max(0,math.min(1,num(data.scanned)/math.max(1,num(data.cells))))*100)
            text(1,9,"Fortschritt "..pc.."% | "..(selected.job=="farm" and "Pflanzen " or "Bloecke ")..short(data.harvested),colors.lightGray)
        else
            text(1,7,"Ernte "..short(totalFarm).." | Beute "..short(totalMine))
            text(1,8,"Fuel "..(unlimited and "teils unbegrenzt" or short(fuel))..(chunkFuel>0 and (" | Chunks -"..short(chunkFuel).."/h") or ""))
            text(1,9,"Saat "..short(seeds).." | Freie Slots "..short(slots),colors.lightGray)
        end
        local available=math.max(1,h-16)
        local pageSize=cfg.display.pageSize>0 and math.min(available,cfg.display.pageSize) or available
        local pages=math.max(1,math.ceil(#ids/pageSize));ui.pages=pages;ui.page=math.min(ui.page,pages)
        for row=1,pageSize do
            local id=ids[(ui.page-1)*pageSize+row];if not id then break end
            local e=entries[id] or {};local d=e.data or {}
            local prefix=e.job=="farm" and "F" or e.job=="mining" and "M" or "?"
            local name=e.label and e.label~="" and e.label or ""
            local status=link and e.online and tostring(d.status or "ONLINE") or "OFFLINE"
            local bg=ui.selected==id and colors.blue or ((d.fault or d.recovery) and link and e.online and colors.brown or colors.gray)
            button(1,10+row,w,(d.fault or d.recovery) and "!"..prefix.."#"..id.." "..name.." "..status or prefix.."#"..id.." "..name.." "..status,"id:"..id,bg,true)
        end
        text(1,h-5,tostring(notice or ""),colors.lightGray)
        local half=math.floor(w/2)
        button(1,h-4,half,"< Seite "..ui.page.."/"..pages,"pageprev",colors.gray,true)
        button(half+1,h-4,w-half,"Seite >","pagenext",colors.gray,true)
        for i,v in ipairs({{"< Ziel","prev"},{"Ziel >","next"},{"GRUPPE","group"}})do
            button(1+(i-1)*third,h-3,i==3 and w-2*third or third,v[1],v[2],colors.blue,true)
        end
        button(1,h-2,w,"RESET: Fehler loeschen + heim","reset",colors.orange,link and #ids>0)
        local canStart=false
        for _,id in ipairs(ids)do
            local e=entries[id]
            if link and (not ui.selected or ui.selected==id) and e and e.online and e.data and not e.data.recovery then canStart=true end
        end
        local once=selected and (selected.job=="farm" and "1 RUNDE" or "1 GANG") or ui.filter=="farm" and "1 RUNDE" or ui.filter=="mining" and "1 GANG" or "1 LAUF"
        for i,v in ipairs({{"START","start",colors.green},{"STOP","stop",colors.red},{once,"once",colors.blue}})do
            button(1+(i-1)*third,h-1,i==3 and w-2*third or third,v[1],v[2],v[3],v[2]=="stop" and link or canStart)
        end
        text(1,h,ui.selected and ("Ziel #"..ui.selected.." | 0: Gruppe") or ("Ziel "..title.." | Q: Ende"),colors.lightGray)
    end
    function ui.action(a)
        if not a then return end
        if a:match("^filter:")then ui.filter=a:sub(8);ui.selected=nil;ui.page=1
        elseif a:match("^id:")then ui.selected=tonumber(a:sub(4))
        elseif a=="group" then ui.selected=nil
        elseif a=="pageprev" then ui.page=math.max(1,ui.page-1)
        elseif a=="pagenext" then ui.page=math.min(ui.pages or 1,ui.page+1)
        elseif a=="next" or a=="prev" then
            local index=0;for i,id in ipairs(ui.ids)do if id==ui.selected then index=i end end
            index=(index+(a=="next" and 1 or -1))%(#ui.ids+1)
            ui.selected=ui.ids[index]
        else return a end
    end
    function ui.target()return ui.selected or ui.filter end
    function ui.click(x,y)
        for _,b in ipairs(ui.buttons)do if b.enabled and y==b.y and x>=b.x and x<b.x+b.w then return b.action end end
    end
    ui.keys={["0"]="group",["1"]="start",["2"]="stop",["3"]="once",["4"]="reset",["a"]="filter:all",["f"]="filter:farm",["m"]="filter:mining"}
    return ui
end
return M
