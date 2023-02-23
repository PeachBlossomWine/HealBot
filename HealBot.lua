_addon.name = 'HB'
_addon.author = 'Lorand - Enhanced by PBW'
_addon.command = 'hb'
_addon.lastUpdate = '2023.02.23.1'
_addon.version = _addon.lastUpdate

--[[
TODO:
- !!Fix: Make follow cancellable when in other zones
- Global action queue instead of rebuilding every cycle
- Action sets that must be performed together (e.g., Snake Eye, then Double Up)
- GEO
    - debuff support
    - clean up logic/code
- COR
    - Rolled # detection
- If not in same pt as other instance, send pt list via IPC
- If in alliance, automatically watch other healers?
--]]

require('luau')
require('lor/lor_utils')
_libs.lor.include_addon_name = true
_libs.lor.req('all', {n='packets',v='2016.10.27.0'})
_libs.req('queues')
lor_settings = _libs.lor.settings
serialua = _libs.lor.serialization

hb = {
    active = false, configs_loaded = false, partyMemberInfo = {}, ignoreList = S{}, extraWatchList = S{}, job_registry= T{},
    modes = {['showPacketInfo'] = false, ['debug'] = false, ['mob_debug'] = false, ['independent'] = false},
    _events = {}, txts = {}, config = {}
}
healer = T{}
settings = {}
_libs.lor.debug = hb.modes.debug

res = require('resources')
config = require('config')
texts = require('texts')
packets = require('packets')
files = require('files')

require('HealBot_statics')
require('HealBot_utils')
CureUtils = require('HB_CureUtils')
offense = require('HB_Offense')
actions = require('HB_Actions')
buffs = require('HealBot_buffHandling')
require('HealBot_packetHandling')
require('HealBot_queues')

local ipc_req = serialua.encode({method='GET', pk='buff_ids'})
local can_act_statuses = S{0, 1, 5, 85}    --0/1/5/85 = idle/engaged/chocobo/other_mount
local dead_statuses = S{2, 3}
local pt_keys = {'party1_count', 'party2_count', 'party3_count'}
local pm_keys = {
    {'p0','p1','p2','p3','p4','p5'}, {'a10','a11','a12','a13','a14','a15'}, {'a20','a21','a22','a23','a24','a25'}
}

	-- San d'Oria(294):		149,572 - Defense Down, Avoidance Down
	-- Bastok(295):			13,21 - Slow, Addle
	-- Windurst(296):		168 - Inhibit TP
	-- Jeuno(297):			31 - Plague
	-- Dia, Bio all zones: 	134,135
	
	--dyna_aura_ids = S{572,149,13,21,168,31,134,135} -- Auras
	--gaol_aura_ids = S{146,147,148,149,167,404,174,175,136,137,138,139,140,141,142} -- "DOWN" Aura + Stat down
	--gaes_fete_debuff_ids = S{29,557,558,559,560,561,562,563,564} -- Auras [Mute + 8 Down]
	dyna_sandoria_aura = {'defense down','dia','bio'}	-- 'avoidance down', NOT CODED
	dyna_bastok_aura = {'slow','addle','dia','bio'}
	dyna_windurst_aura = {'inhibit tp','dia','bio'}
	dyna_jeuno_aura = {'plague','dia','bio'}
	dyna_auras = {'defense down','slow','addle','inhibit tp','plague','dia','bio'}	-- 'avoidance down', NOT CODED
	dyna_zones = S{294,295,296,297}

	gaol_zones = S{279,298}
	gaol_auras = {'accuracy down','attack down','defense down','evasion down','magic def. down','magic atk. down','magic evasion down','magic acc. down','str down','int down','vit down','chr down','mnd down','dex down','agi down'}
	
	shinryu_debuffs = {'str down','int down','vit down','chr down','mnd down','dex down','agi down'}
	shinryu_zone = 255

local LevelRestrict = false

hb._events['load'] = windower.register_event('load', function()
    if not _libs.lor then
        local err_msg = 'HB ERROR: Missing core requirement: https://github.com/lorand-ffxi/lor_libs'
        windower.add_to_chat(39, err_msg)
        error(err_msg)
    end
	
    atcc(262, '- Welcome to HB! -')

    _G["healer"] = _libs.lor.actor.Actor.new()
	zone_info = windower.ffxi.get_info()
    utils.load_configs()
    CureUtils.init_cure_potencies()
	
    if gaol_zones:contains(zone_info.zone) then
		coroutine.sleep(10)
		local current_buffs = windower.ffxi.get_player()["buffs"]
		local SJRestrict = false
		
		for key,val in pairs(current_buffs) do
			if val == 157 then -- SJ Restriction
				SJRestrict = true
			end
		end

		if SJRestrict == true then
			windower.add_to_chat(122,'Loaded HB in Sheol: Gaol, disabling HB debuff removal on auras.')
			for i, debuff_name in ipairs(gaol_auras) do
				windower.send_command('hb ignore_debuff all ' .. debuff_name)
			end
		end
	elseif zone_info.zone == 294 then -- San d'Oria
		coroutine.sleep(5)
		windower.add_to_chat(122,'Loaded HB in Dynamis Divergence - San d\'Oria, disabling HB debuff removal on auras.')
		for i, debuff_name in ipairs(dyna_sandoria_aura) do
			windower.send_command('hb ignore_debuff all ' .. debuff_name)
		end
	elseif zone_info.zone == 295 then -- Bastok
		coroutine.sleep(5)
		windower.add_to_chat(122,'Loaded HB in Dynamis Divergence - Bastok, disabling HB debuff removal on auras.')
		for i, debuff_name in ipairs(dyna_bastok_aura) do
			windower.send_command('hb ignore_debuff all ' .. debuff_name)
		end
	elseif zone_info.zone == 296 then -- Windurst
		coroutine.sleep(5)
		windower.add_to_chat(122,'Loaded HB in Dynamis Divergence - Windurst, disabling HB debuff removal on auras.')
		for i, debuff_name in ipairs(dyna_windurst_aura) do
			windower.send_command('hb ignore_debuff all ' .. debuff_name)
		end
	elseif zone_info.zone == 297 then -- Jeuno
		coroutine.sleep(5)
		windower.add_to_chat(122,'Loaded HB in Dynamis Divergence - Jeuno, disabling HB debuff removal on auras.')
		for i, debuff_name in ipairs(dyna_jeuno_aura) do
			windower.send_command('hb ignore_debuff all ' .. debuff_name)
		end
	elseif zone_info.zone == 255 then -- Abyssea - Empyreal Paradox
		coroutine.sleep(5)
		windower.add_to_chat(122,'Loaded HB in Abyssea - Empyreal Paradox, disabling HB debuff on stat down.')
		for i, debuff_name in ipairs(shinryu_debuffs) do
			windower.send_command('hb ignore_debuff all ' .. debuff_name)
		end
	end
	
end)


hb._events['unload'] = windower.register_event('unload', function()
    for _,event in pairs(hb._events) do
        windower.unregister_event(event)
    end
end)


hb._events['logout'] = windower.register_event('logout', function()
    windower.send_command('lua unload healBot')
end)

hb._events['zone'] = windower.register_event('zone change', function(new_id, old_id)
    healer.zone_enter = os.clock()
    buffs.resetDebuffTimers('ALL')
	hb.active = false	-- Deactivate when zoned.
    zone_info = windower.ffxi.get_info()
	offense.cleanup()
	
    if zone_info ~= nil then
        if zone_info.zone == 131 then
            windower.send_command('lua unload healBot')
			
		elseif gaol_zones:contains(zone_info.zone) then
			coroutine.sleep(10)
			local current_buffs = windower.ffxi.get_player()["buffs"]
			local SJRestrict = false
			
			for key,val in pairs(current_buffs) do
				if val == 157 then -- SJ Restriction
					SJRestrict = true
				end
			end

			if SJRestrict == true then
				windower.add_to_chat(122,'In Sheol: Gaol, disabling HB debuff removal on auras.')
				for i, debuff_name in ipairs(gaol_auras) do
					windower.send_command('hb ignore_debuff all ' .. debuff_name)
				end
			end
		elseif zone_info.zone == 294 then -- San d'Oria
			coroutine.sleep(5)
			windower.add_to_chat(122,'In Dynamis Divergence - San d\'Oria, disabling HB debuff removal on auras.')
			for i, debuff_name in ipairs(dyna_sandoria_aura) do
				windower.send_command('hb ignore_debuff all ' .. debuff_name)
			end
		elseif zone_info.zone == 295 then -- Bastok
			coroutine.sleep(5)
			windower.add_to_chat(122,'In Dynamis Divergence - Bastok, disabling HB debuff removal on auras.')
			for i, debuff_name in ipairs(dyna_bastok_aura) do
				windower.send_command('hb ignore_debuff all ' .. debuff_name)
			end
		elseif zone_info.zone == 296 then -- Windurst
			coroutine.sleep(5)
			windower.add_to_chat(122,'In Dynamis Divergence - Windurst, disabling HB debuff removal on auras.')
			for i, debuff_name in ipairs(dyna_windurst_aura) do
				windower.send_command('hb ignore_debuff all ' .. debuff_name)
			end
		elseif zone_info.zone == 297 then -- Jeuno
			coroutine.sleep(5)
			windower.add_to_chat(122,'In Dynamis Divergence - Jeuno, disabling HB debuff removal on auras.')
			for i, debuff_name in ipairs(dyna_jeuno_aura) do
				windower.send_command('hb ignore_debuff all ' .. debuff_name)
			end
		elseif zone_info.zone == 255 then -- Abyssea - Empyreal Paradox
			coroutine.sleep(5)
			windower.add_to_chat(122,'In Abyssea - Empyreal Paradox, disabling HB debuff on stat down.')
			for i, debuff_name in ipairs(shinryu_debuffs) do
				windower.send_command('hb ignore_debuff all ' .. debuff_name)
			end
        elseif zone_info.mog_house == true then
            hb.active = false
        elseif settings.deactivateIndoors and indoor_zones:contains(zone_info.zone) then
            hb.active = false
        elseif settings.activateOutdoors and not indoor_zones:contains(zone_info.zone) then
            hb.active = true
        end
    end
	
	-- Exiting code
	if gaol_zones:contains(old_id) and not gaol_zones:contains(new_id) then
		coroutine.sleep(5)
		windower.add_to_chat(122,'Exiting Sheol: Gaol zones, enabling NA/Erase removal.')
		for i, debuff_name in ipairs(gaol_auras) do
			windower.send_command('hb unignore_debuff all ' .. debuff_name)
		end
	elseif dyna_zones:contains(old_id) and not dyna_zones:contains(new_id) then
		coroutine.sleep(5)
		windower.add_to_chat(122,'Exiting any Dynamis Divergence zone, enabling NA/Erase removal.')
		for i, debuff_name in ipairs(dyna_auras) do
			windower.send_command('hb unignore_debuff all ' .. debuff_name)
		end
	elseif old_id == shinryu_zone and new_id ~= shinryu_zone then
		coroutine.sleep(5)
		windower.add_to_chat(122,'Exiting Abyssea - Empyreal Paradox, enabling NA/Erase removal.')
		for i, debuff_name in ipairs(shinryu_debuffs) do
			windower.send_command('hb unignore_debuff all ' .. debuff_name)
		end
	end
	
end)


hb._events['job'] = windower.register_event('job change', function()
    hb.active = false
    healer:update_job()
    printStatus()
end)

hb._events['inc'] = windower.register_event('incoming chunk', handle_incoming_chunk)
hb._events['cmd'] = windower.register_event('addon command', processCommand)


--[[
    Executes before each frame is rendered for display.
    Acts as the run() method of a threaded application.
--]]
hb._events['render'] = windower.register_event('prerender', function()
    if not hb.configs_loaded then return end

    local now = os.clock()
    local moving = hb.isMoving()
    local acting = hb.isPerformingAction(moving)
    local player = windower.ffxi.get_player()
    healer.name = player and player.name or 'Player'
    if (player ~= nil) and can_act_statuses:contains(player.status) then
        local partner, targ = offense.assistee_and_target()
        hb.follow_target_exists()   --Attempts to prevent autorun problems
        local follow = settings.follow
        if hb.auto_movement_active() then
            if ((now - healer.last_move_check) > follow.delay) then
                local should_move = false
				if (targ ~= nil) and (player.target_index == partner.target_index) then
					if offense.assist.engage and (partner.status == 1) then
						if healer:dist_from(targ.id) > 3 then
							should_move = true
							healer:move_towards(targ.id)
						end
					end
				end
                if (not should_move) and follow.active and (healer:dist_from(follow.target) > follow.distance) and not (player.status == 1) then	-- Only follow if not engaged.
                    should_move = true
                    healer:move_towards(follow.target)
				elseif player.status == 1 and player.target_index then		-- For when autotarget to engage correct distance
					local current_targ = windower.ffxi.get_mob_by_index(player.target_index)
					if healer:dist_from(current_targ.id) > (2 + current_targ.model_size) then
						should_move = true
						healer:move_towards(current_targ.id)
					end
                end
                if (not should_move) then
                    if follow.active then
                        windower.ffxi.run(false)
                    end
                else
                    moving = true
                end
                healer.last_move_check = now      --Refresh stored movement check time
            end
        end
        
        if hb.active and not (moving or acting) then
            --hb.active = false    --Quick stop when debugging
            if healer:action_delay_passed() then
                if actions.take_action(player, partner, targ) then
                    healer.last_action = now                    --Refresh stored action check time
                end
            end
        end
        
        if hb.active and ((now - healer.last_ipc_sent) > healer.ipc_delay) then
            windower.send_ipc_message(ipc_req)
            healer.last_ipc_sent = now
        end
    end
end)


function haveBuff(...)
    local args = S{...}:map(string.lower)
    local player = windower.ffxi.get_player()
    if (player ~= nil) and (player.buffs ~= nil) then
        for _,bid in pairs(player.buffs) do
            local buff = res.buffs[bid]
            if args:contains(buff.en:lower()) then
                return true
            end
        end
    end
	
    return false
end




function hb.activate()
    local player = windower.ffxi.get_player()
    if player ~= nil then
        settings.healing.max = {}
        for _,cure_type in pairs(CureUtils.cure_types) do
            settings.healing.max[cure_type] = CureUtils.highest_tier(cure_type)
        end
        if (settings.healing.max.cure == 0) then
            if settings.healing.max.waltz > 0 then
                settings.healing.mode = 'waltz'
                settings.healing.modega = 'waltzga'
			elseif settings.healing.max.blue > 0 then
				settings.healing.mode = 'blue'
                settings.healing.modega = 'bluega'
            else
                disableCommand('cure', true)
            end
        else
            settings.healing.mode = 'cure'
            settings.healing.modega = 'curaga'
        end
        hb.active = true
    end
    printStatus()
end


function hb.addPlayer(list, player)
    if (player == nil) or list:contains(player.name) or hb.ignoreList:contains(player.name) then return end
    local is_trust = player.mob and player.mob.spawn_type == 14 or false    --13 = players; 14 = Trust NPC
    if (settings.ignoreTrusts and is_trust and (not hb.extraWatchList:contains(player.name))) then return end
    local status = player.mob and player.mob.status or player.status
    if dead_statuses:contains(status) or (player.hpp <= 0) then
        --Player is dead.  Reset their buff/debuff lists and don't include them in monitored list
        buffs.resetDebuffTimers(player.name)
        buffs.resetBuffTimers(player.name)
    else
        player.trust = is_trust
        list[player.name] = player
    end
end


watchall = false
local function _getMonitoredPlayers()
    local pt = windower.ffxi.get_party()
    local my_zone = pt.p0.zone
    local targets = S{}
    for p = 1, #pt_keys do
        for m = 1, pt[pt_keys[p]] do
            local pt_member = pt[pm_keys[p][m]]
            if my_zone == pt_member.zone then
                if p == 1 or hb.extraWatchList:contains(pt_member.name) or watchall then
                    hb.addPlayer(targets, pt_member)
                end
            end
        end
    end
    for extraName,_ in pairs(hb.extraWatchList) do
        hb.addPlayer(targets, windower.ffxi.get_mob_by_name(extraName))
    end

	local display_targets = S{}
	for k,v in pairs(targets) do
		if v.mob ~= nil then
			display_targets:add(string.format("%-10s - %3s", v.name, get_registry(v.mob.id)))
		end
	end
	
    hb.txts.montoredBox:text(getPrintable(display_targets, true))
    hb.txts.montoredBox:visible(settings.textBoxes.montoredBox.visible)
    return targets
end
hb.getMonitoredPlayers = _libs.lor.advutils.tcached(1, _getMonitoredPlayers)


local function _getMonitoredIds()
    local ids = S{}
    for name, player in pairs(hb.getMonitoredPlayers()) do
        local id = player.mob and player.mob.id or player.id or utils.get_player_id[name]
        if id ~= nil then
            ids[id] = true
        end
    end
    return ids
end
hb.getMonitoredIds = _libs.lor.advutils.tcached(1, _getMonitoredIds)


function hb.follow_target_exists()
    if (settings.follow.target == nil) then return end
    local ft = windower.ffxi.get_mob_by_name(settings.follow.target)
    if settings.follow.active and (ft == nil) then
        settings.follow.pause = true
        settings.follow.active = false
    elseif settings.follow.pause and (ft ~= nil) then
        settings.follow.pause = nil
        settings.follow.active = true
    end
end


function hb.auto_movement_active()
    return settings.follow.active or (offense.assist.active and offense.assist.engage)
end


function hb.isMoving()
    local timeAtPos = healer:time_at_pos()
    if timeAtPos == nil then
        hb.txts.moveInfo:hide()
        return true
    end
    local moving = healer:is_moving()
    hb.txts.moveInfo:text(('Time @ %s: %.1fs'):format(tostring(healer:pos()), timeAtPos))
    hb.txts.moveInfo:visible(settings.textBoxes.moveInfo.visible)
    return moving
end


function hb.isPerformingAction(moving)
    local acting = healer:is_acting()
    --local status = ('is %s'):format(acting and 'performing an action' or (moving and 'moving' or 'idle'))
	local status = ('are %s'):format(acting and 'performing an action' or (moving and 'moving' or 'idle'))
    
    if (os.clock() - healer.zone_enter) < 25 then
        acting = true
        status = 'zoned recently'
        healer.zone_wait = true
    elseif healer.zone_wait then
        healer.zone_wait = false
        buffs.resetBuffTimers('ALL', S{'Protect V', 'Shell V'})
    elseif healer:buff_active('Petrification','Charm','Terror','Stun','Mute') then -- ('Sleep','Petrification','Charm','Terror','Lullaby','Stun','Silence','Mute')
        acting = true
        --status = 'is disabled'
		status = 'are disabled'
    end
    
    local player = windower.ffxi.get_player()
    if (player ~= nil) then
        local mpp = player.vitals.mpp
        if (mpp <= 10) then
            status = status..' | \\cs(255,0,0)LOW MP\\cr'
        end
    end
	
	-- Changed for anon
	healer.name = "You"
	
    local hb_status = hb.active and '\\cs(0,0,255)[ON]\\cr' or '\\cs(255,0,0)[OFF]\\cr'
    hb.txts.actionInfo:text((' %s %s %s'):format(hb_status, healer.name, status))
    hb.txts.actionInfo:visible(settings.textBoxes.actionInfo.visible)
    return acting
end


	-- if haveBuff('Level Restriction') then
		-- --log('restriction on')
	-- else
		-- log('No more restrict')
		-- buffs.resetDebuffTimers(player.name)
	-- end

function hb.process_ipc(msg)
    local loaded = serialua.decode(msg)
    if loaded == nil then
        atc(53, 'Received nil IPC message')
    elseif type(loaded) ~= 'table' then
        atcfs(264, 'IPC message: %s', loaded)
    elseif loaded.method == 'GET' then
        if loaded.pk ~= nil then        
            if loaded.pk == 'buff_ids' then
                local player = windower.ffxi.get_player()
                local response = {
                    method='POST', pk='buff_ids', val=player.buffs,
                    pid=player.id, name=player.name, stype=player.spawn_type
                }
                local encoded = serialua.encode(response)
                windower.send_ipc_message(encoded)
            else
                atcfs(123, 'Invalid pk for GET request: %s', loaded.pk)
            end
        else
            atcfs(123, 'Invalid GET request: %s', msg)
        end
    elseif loaded.method == 'POST' then
        if loaded.pk ~= nil then        
            if loaded.pk == 'buff_ids' then
                if loaded.name ~= nil then                
                    local player = windower.ffxi.get_mob_by_name(loaded.name)
                    player = player or {id=loaded.pid,name=loaded.name,spawn_type=loaded.stype}
                    buffs.review_active_buffs(player, loaded.val)
                else
                    atcfs(123, 'Missing name in POST message: %s', msg)
                end
            else
                atcfs(123, 'Invalid pk for POST message: %s', loaded.pk)
            end
        else
            atcfs(123, 'Invalid POST message: %s', msg)
        end
    else
        atcfs(123, 'Invalid IPC message: %s', msg)
    end
end

hb._events['ipc'] = windower.register_event('ipc message', hb.process_ipc)


--======================================================================================================================
--[[
Copyright © 2018, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the
      following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
      following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
--]]
--======================================================================================================================
