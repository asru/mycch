local mq = require('mq')
local ImGui = require 'ImGui'

local arg = { ... }

local running = true
local myName = mq.TLO.Me.DisplayName()
local CheckItemName = ''
local CheckItemQuantity = 0
local StartAmount = 0
local ItemSlot = 0
local ItemSlot2 = 0
local window_flags = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize)
local openGUI, drawGUI = true, true
local combo_selected = 1
local connected_list = {}
local cchheader = "\ay[\agMYCCH\ay]"
local action = "WAIT"
local DEBUG = false
-- Remote action scheduler (to avoid blocking ImGui callbacks)
local remote_task = nil -- {peer=string, oneshot=string, cooldown=integer}


if mq.TLO.Plugin('mq2dannet').IsLoaded() == false then
    printf("%s \aoDanNet is required for this plugin.  \arExiting", cchheader)
    mq.exit()
end

local function realestate_window_open()
    return mq.TLO.Window('RealEstateItemsWnd').Open()
end

local function item_moved_to_inventory()
    if mq.TLO.FindItem("=" .. CheckItemName) ~= nil then return true end
    return false
end

local function display_window_open()
    if mq.TLO.Window("ItemDisplayWindow").Child("IDW_ItemInfo1").Text() == CheckItemName then return true end
    return false
end

local function check_item_count()
    if tonumber(mq.TLO.FindItemCount("=" .. CheckItemName)() or 0) ~= StartAmount then return true end
    return false
end

local function closet_button_ready()
    return mq.TLO.Window("REIW_ItemsPage").Child("REIW_Move_Closet_Button").Enabled()
end

local function inventory_button_ready()
    return mq.TLO.Window("REIW_ItemsPage").Child("REIW_Move_Inventory_Button").Enabled()
end

local function check_item_returned()
    if not (tonumber(mq.TLO.FindItemCount("=" .. CheckItemName)() or 0) > 0) then return true end
    return false
end

local function return_item_to_storage()
    local loopcount = 1
    mq.cmdf("/nomodkey /itemnotify in pack%s %s leftmouseup", ItemSlot, ItemSlot2)
    mq.delay("5s", closet_button_ready)
    while tonumber(mq.TLO.FindItemCount("=" .. CheckItemName)() or 0) > 0 do
        if mq.TLO.Window("REIW_ItemsPage").Child("REIW_Move_Closet_Button").Enabled() then
            mq.cmd(
                "/nomodkey /shift /notify RealEstateItemsWnd REIW_Move_Closet_Button leftmouseup")
        elseif mq.TLO.Window("REIW_ItemsPage").Child("REIW_Move_Crate_Button").Enabled() then
            mq.cmd(
                "/nomodkey /shift /notify RealEstateItemsWnd REIW_Move_Crate_Button leftmouseup")
        end
        if loopcount == 5 then
            mq.cmdf("/nomodkey /itemnotify in pack%s %s leftmouseup", ItemSlot, ItemSlot2)
            loopcount = 1
        else
            loopcount = loopcount + 1
        end
    end
    mq.delay("5s", check_item_returned)
    mq.delay("5s", inventory_button_ready)
end

local function open_windows()
    if not mq.TLO.Window('InventoryWindow').Open() then
        mq.cmd("/squelch /windowstate InventoryWindow open")
    end
    mq.cmd("/keypress OPEN_INV_BAGS")
    if not mq.TLO.Window('RealEstateItemsWnd').Open() then
        mq.cmd("/squelch /windowstate RealEstateItemsWnd open")
        mq.delay('2s', realestate_window_open)
    end
end

local function close_windows()
    if mq.TLO.Window('InventoryWindow').Open() then
        mq.cmd("/squelch /windowstate InventoryWindow close")
    end
    mq.cmd("/keypress CLOSE_INV_BAGS")
    if mq.TLO.Window('RealEstateItemsWnd').Open() then
        mq.cmd("/squelch /windowstate RealEstateItemsWnd close")
        mq.delay('2s', realestate_window_open)
    end
end

local function collect_from_house()
    local count = 0
    open_windows()
    mq.delay('1s')
    local i = 0
    while true do
        i = i + 1
        if not mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(i, 2).Length() then break end
        if mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(i, 3)() == 'V' then
            CheckItemName = mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(i, 2)()
            CheckItemQuantity = mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(i, 4)()
            mq.cmdf('/notify RealEstateItemsWnd REIW_ItemList Listselect %s', i)
            mq.cmd('/nomodkey /shift /notify RealEstateItemsWnd REIW_Move_Inventory_Button leftmouseup')
            mq.delay("20s", item_moved_to_inventory)
            mq.delay("1s")
            StartAmount = mq.TLO.FindItemCount("=" .. CheckItemName)()
            while mq.TLO.FindItem("=" .. CheckItemName).ItemSlot() == nil do
                mq.delay(50)
            end
            ItemSlot = mq.TLO.FindItem("=" .. CheckItemName).ItemSlot() - 22
            ItemSlot2 = mq.TLO.FindItem("=" .. CheckItemName).ItemSlot2() + 1
            if mq.TLO.FindItem("=" .. CheckItemName).Collectible() then
                mq.cmdf("/nomodkey /altkey /itemnotify in pack%s %s leftmouseup", ItemSlot, ItemSlot2)
                mq.delay("2s", display_window_open)
                mq.delay(500)
                if mq.TLO.Window("ItemDisplayWindow").Child("IDW_ItemInfo1").Text() ~= CheckItemName then
                    printf("\arYou maybe bugged, \ao the ItemDisplayWIndow text is showing \ar%s \ao instead of \ay%s",
                        mq.TLO.Window("ItemDisplayWindow").Child("IDW_ItemInfo1").Text(), CheckItemName)
                    print("It is recomended you relog.")
                else
                    if mq.TLO.Window("ItemDisplayWindow").Child("IDW_CollectedLabel").Text() == "Not Collected" then
                        printf("\ap>>> %s <<< \ag hasn't been collected yet. Doing that now.", CheckItemName)
                        mq.cmd("/invoke ${Window[ItemDisplayWindow].DoClose}")
                        mq.cmdf("/nomodkey /itemnotify in pack%s %s rightmouseup", ItemSlot, ItemSlot2)
                        mq.delay("3s", check_item_count)
                        if tonumber(CheckItemQuantity) == 1 then
                            i = i - 1
                        else
                            return_item_to_storage()
                        end
                        count = count + 1
                    else
                        printf("\ap>>> %s <<< \arhas been collected. Returning to vault.", CheckItemName)
                        mq.cmd("/invoke ${Window[ItemDisplayWindow].DoClose}")
                        return_item_to_storage()
                    end
                end
            else
                return_item_to_storage()
            end
        end
        CheckItemName = ''
        CheckItemQuantity = 0
        StartAmount = 0
    end
    printf("%s \aoDone! I have collected: \ap%s", cchheader, count)
    mq.cmdf("/dgt %s \aoI'm done with my collectibles master! I have collected: \ap%s", cchheader, count)
    close_windows()
end

local function store_in_house()
    open_windows()
    for i = 1, 12 do
        if mq.TLO.InvSlot('pack' .. i).Item.Container() then
            for j = 1, mq.TLO.InvSlot('pack' .. i).Item.Container() do
                if mq.TLO.InvSlot('pack' .. i).Item.Item(j).Collectible() then
                    CheckItemName = mq.TLO.InvSlot('pack' .. i).Item.Item(j).Name()
                    ItemSlot = i
                    ItemSlot2 = j
                    return_item_to_storage()
                end
            end
        end
    end
    ItemSlot = 0
    ItemSlot2 = 0
    CheckItemName = ''
    close_windows()
end

local function collect_inventory_all()
    local count = 0
    if not mq.TLO.Window('InventoryWindow').Open() then
        mq.cmd("/squelch /windowstate InventoryWindow open")
    end
    mq.cmd("/keypress OPEN_INV_BAGS")
    for i = 1, 12 do
        if mq.TLO.InvSlot('pack' .. i).Item.Container() then
            for j = 1, mq.TLO.InvSlot('pack' .. i).Item.Container() do
                if mq.TLO.InvSlot('pack' .. i).Item.Item(j).Collectible() then
                    StartAmount = mq.TLO.FindItemCount("=" .. CheckItemName)()
                    CheckItemName = mq.TLO.InvSlot('pack' .. i).Item.Item(j).Name()
                    mq.cmdf("/nomodkey /altkey /itemnotify in pack%s %s leftmouseup", i, j)
                    mq.delay("2s", display_window_open)
                    mq.delay(500)
                    if mq.TLO.Window("ItemDisplayWindow").Child("IDW_ItemInfo1").Text() ~= CheckItemName then
                        printf(
                            "\arYou maybe bugged, \ao the ItemDisplayWIndow text is showing \ar%s \ao instead of \ay%s",
                            mq.TLO.Window("ItemDisplayWindow").Child("IDW_ItemInfo1").Text(), CheckItemName)
                        print("It is recomended you relog.")
                    else
                        if mq.TLO.Window("ItemDisplayWindow").Child("IDW_CollectedLabel").Text() == "Not Collected" then
                            printf("\ap>>> %s <<< \ag hasn't been collected yet. Doing that now.", CheckItemName)
                            mq.cmd("/invoke ${Window[ItemDisplayWindow].DoClose}")
                            mq.cmdf("/nomodkey /itemnotify in pack%s %s rightmouseup", i, j)
                            mq.delay("3s", check_item_count)
                            count = count + 1
                        else
                            printf("\ap>>> %s <<< \arhas been collected. Ignoring.", CheckItemName)
                            mq.cmd("/invoke ${Window[ItemDisplayWindow].DoClose}")
                        end
                    end
                end
            end
        end
    end
    printf("%s \aoDone! I have collected: \ap%s", cchheader, count)
    mq.cmdf("/dgt %s \aoI'm done with my collectibles master! I have collected: \ap%s", cchheader, count)
end

local function get_all_from_house()
    open_windows()
    local x = 1
    for i = 1, 1000 do
        if not mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(x, 2).Length() then break end
        if mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(x, 3)() == 'V' then
            CheckItemName = mq.TLO.Window('RealEstateItemsWnd').Child('REIW_ItemList').List(x, 2)()
            mq.cmdf('/notify RealEstateItemsWnd REIW_ItemList Listselect %s', x)
            mq.cmd('/nomodkey /shift /notify RealEstateItemsWnd REIW_Move_Inventory_Button leftmouseup')
            mq.delay("20s", item_moved_to_inventory)
            mq.delay("1s")
            if mq.TLO.FindItem("=" .. CheckItemName).Collectible() then
                printf("\ap>>> %s <<< \ag moved to inventory.", CheckItemName)
            else
                while mq.TLO.FindItem("=" .. CheckItemName).ItemSlot() == nil do
                    mq.delay(50)
                end
                ItemSlot = mq.TLO.FindItem("=" .. CheckItemName).ItemSlot() - 22
                ItemSlot2 = mq.TLO.FindItem("=" .. CheckItemName).ItemSlot2() + 1
                return_item_to_storage()
                x = x + 1
            end
        else
            x = x + 1
        end
    end
    close_windows()
end

local function dannet_connected()
    connected_list = {}
    -- Always include self first (plain character name)
    table.insert(connected_list, myName:lower())
    -- Then add DanNet peers, excluding any that match self
    local peers_list = mq.TLO.DanNet.Peers()
    for word in string.gmatch(peers_list, '([^|]+)') do
        -- Extract character name from "server_character" format
        local charName = word:match("_(.+)$") or word
        -- Skip if this peer is the same character (with or without server prefix)
        if charName:lower() ~= myName:lower() and word:lower() ~= myName:lower() then
            table.insert(connected_list, word)
        end
    end
end

local function cmd_mycch(cmd)
    if cmd == nil or cmd == 'help' then
    printf("%s \ar/mycch exit \ao--- Exit script", cchheader)
    printf("%s \ar/mycchhide \ao--- Hide GUI", cchheader)
    printf("%s \ar/mycch show \ao--- Show GUI", cchheader)
    elseif cmd == 'exit' or cmd == 'quit' or cmd == 'stop' then
        running = false
    elseif cmd == 'show' then
        openGUI = true
    elseif cmd == 'hide' then
        openGUI = false
    else
    printf("%s \arUnrecognized command.", cchheader)
    end
end

local function displayGUI()
    if not openGUI then return end
    openGUI, drawGUI = ImGui.Begin("Collector's Clearing House##" .. myName, openGUI, window_flags)
    if drawGUI then
        dannet_connected()
        local comboWidth = 150
        local endWidth = 60
        local spacing = ImGui.GetStyle().ItemSpacing.x
        local rowWidth = comboWidth + spacing + endWidth
        ImGui.PushItemWidth(comboWidth)
        combo_selected = ImGui.Combo('##Combo', combo_selected, connected_list)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Character to perform action')
        end
        ImGui.PopItemWidth()
        ImGui.SameLine()
        if ImGui.Button("End", ImVec2(endWidth, 22)) then
            running = false
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('End mycch (exit)')
        end
        if ImGui.Button("Store All Collectibles", ImVec2(rowWidth, 22)) then
            if connected_list[combo_selected] == myName:lower() then
                action = 'CALL_STORE'
            else
                -- Queue remote stop->run sequence (no blocking delay in ImGui)
                mq.cmdf("/squelch /dex %s /lua stop mycch", connected_list[combo_selected])
                remote_task = {peer = connected_list[combo_selected], oneshot = "store", cooldown = 3}
                if DEBUG then printf("%s queued remote: %s -> %s", cchheader, connected_list[combo_selected], "store") end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Store all collectibles in housing storage')
        end
    if ImGui.Button("Retrieve All Collectibles", ImVec2(rowWidth, 22)) then
            if connected_list[combo_selected] == myName:lower() then
                action = 'CALL_GET'
            else
                mq.cmdf("/squelch /dex %s /lua stop mycch", connected_list[combo_selected])
                remote_task = {peer = connected_list[combo_selected], oneshot = "grab", cooldown = 3}
                if DEBUG then printf("%s queued remote: %s -> %s", cchheader, connected_list[combo_selected], "grab") end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Retrieve all collectibles from housing storage')
        end
    if ImGui.Button("Collect and Return", ImVec2(rowWidth, 22)) then
            if connected_list[combo_selected] == myName:lower() then
                action = 'CALL_COLLECTH'
            else
                mq.cmdf("/squelch /dex %s /lua stop mycch", connected_list[combo_selected])
                remote_task = {peer = connected_list[combo_selected], oneshot = "collecth", cooldown = 3}
                if DEBUG then printf("%s queued remote: %s -> %s", cchheader, connected_list[combo_selected], "collecth") end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Collect items in housing storage (and return to storage)')
        end
    if ImGui.Button("Collect in Inventory", ImVec2(rowWidth, 22)) then
            if connected_list[combo_selected] == myName:lower() then
                action = 'CALL_COLLECTI'
            else
                mq.cmdf("/squelch /dex %s /lua stop mycch", connected_list[combo_selected])
                remote_task = {peer = connected_list[combo_selected], oneshot = "collecti", cooldown = 3}
                if DEBUG then printf("%s queued remote: %s -> %s", cchheader, connected_list[combo_selected], "collecti") end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Collect collectibles in inventory')
        end
    end
    ImGui.End()
end

local function main()
    dannet_connected()
    for i, name in pairs(connected_list) do
        if name == string.lower(mq.TLO.Me.DisplayName()) then combo_selected = i end
    end
    while running == true do
        mq.delay(200)
        -- Remote scheduler: after a few ticks, send the oneshot to target
        if remote_task ~= nil then
            if remote_task.cooldown > 0 then
                remote_task.cooldown = remote_task.cooldown - 1
            else
                if DEBUG then printf("%s running remote oneshot: %s -> %s", cchheader, remote_task.peer, remote_task.oneshot) end
                mq.cmdf("/squelch /dex %s /lua run mycch oneshot %s", remote_task.peer, remote_task.oneshot)
                remote_task = nil
            end
        end
        if action == "WAIT" then
        elseif action == "CALL_STORE" then
            store_in_house()
            action = 'WAIT'
        elseif action == "CALL_GET" then
            get_all_from_house()
            action = 'WAIT'
        elseif action == "CALL_COLLECTH" then
            collect_from_house()
            action = 'WAIT'
        elseif action == "CALL_COLLECTI" then
            collect_inventory_all()
            action = 'WAIT'
        end
    end
end

if #arg == 0 then
    mq.imgui.init('displayGUI', displayGUI)
    mq.bind('/mycch', cmd_mycch)
    main()
elseif arg[1]:lower() == 'oneshot' then
    if arg[2]:lower() == "collecth" then
        collect_from_house()
    elseif arg[2]:lower() == "collecti" then
        collect_inventory_all()
    elseif arg[2]:lower() == "store" then
        store_in_house()
    elseif arg[2]:lower() == "grab" then
        get_all_from_house()
    end
    -- Ensure oneshot invocations always terminate, even if no work was found
    mq.delay(200)
    mq.exit()
end
