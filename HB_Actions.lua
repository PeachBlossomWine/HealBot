--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot action handling functions
--]]
--==============================================================================

local actions = {queue=L()}
local lor_res = _libs.lor.resources
local ffxi = _libs.lor.ffxi


local function local_queue_reset()
    actions.queue = L()
end

local function local_queue_insert(action, target)
	if (tostring(action) ~= nil) and (tostring(target) ~= nil) then
		actions.queue:append(tostring(action)..' → '..tostring(target))
	else
	
	end
    --actions.queue:append(tostring(action)..' → '..tostring(target))
end

local function local_queue_disp()
    hb.txts.actionQueue:text(getPrintable(actions.queue))
    hb.txts.actionQueue:visible(settings.textBoxes.actionQueue.visible)
end


--[[
	Builds an action queue for defensive actions.  Returns the action deemed most important at the time.
--]]
function actions.get_defensive_action()
	local action = {}
	local player = player or windower.ffxi.get_player()
	--local targets = hb.getMonitoredPlayers()
	
	if (not settings.disable.cure) then
		local cureq = CureUtils.get_cure_queue()
		while (not cureq:empty()) do
			local cact = cureq:pop()
            local_queue_insert(cact.action.en, cact.name)
			if (action.cure == nil) and healer:in_casting_range(cact.name) then
				action.cure = cact
			end
		end
	end
	if (not settings.disable.na) then
		local dbuffq = buffs.getDebuffQueue()
		while (not dbuffq:empty()) do
			local dbact = dbuffq:pop()
			atcd(123, 'Debuff popped to remove: ' .. dbact.debuff.en)
			local ign = buffs.ignored_debuffs[dbact.debuff.en]	
			
			if not ((ign ~= nil) and ((ign.all == true) or ((ign[dbact.name] ~= nil) and (ign[dbact.name] == true)))) then
				-- Erase disable toggle
				if (dbact.action.en == 'Erase') then
					if (not settings.disable.erase) then
						dbact_target = windower.ffxi.get_mob_by_name(dbact.name)
						local_queue_insert(dbact.action.en, dbact.name)
						if (action.debuff == nil) and healer:in_casting_range(dbact.name) and healer:ready_to_use(dbact.action) and not(dbact_target.hpp == 0) then
							action.debuff = dbact
						end
					end
				else
					dbact_target = windower.ffxi.get_mob_by_name(dbact.name)
					local_queue_insert(dbact.action.en, dbact.name)
					if (action.debuff == nil) and healer:in_casting_range(dbact.name) and healer:ready_to_use(dbact.action) and not(dbact_target.hpp == 0) and dbact.debuff.id ~= 20 and (player.vitals.mp >= dbact.action.mp_cost) then
						action.debuff = dbact
					end
				end
			else
				atcd(123, '***[Failsafe ignore_debuff caught]*** ->  Name: ' .. dbact.name .. ' Debuff: ' .. dbact.debuff.en .. ' ID: ' .. dbact.debuff.id)
			end
			
		end
	end
	if (not settings.disable.buff) then
		
		local buffq = buffs.getBuffQueue()
		while (not buffq:empty()) do
			local bact = buffq:pop()
			
			if (bact and bact.action and bact.action.en) then
				bact_target = windower.ffxi.get_mob_by_name(bact.name)
				local_queue_insert(bact.action.en, bact.name)
			end
            
			if (action.buff == nil) and healer:in_casting_range(bact.name) and healer:ready_to_use(bact.action) and not(bact_target.hpp == 0) and (player.vitals.mp >= bact.action.mp_cost) then
				action.buff = bact
			end
		end
	end
	
	local_queue_disp()
	
	if (action.cure ~= nil) then
		if (action.debuff ~= nil) and (action.debuff.action.en == 'Paralyna') and (action.debuff.name == healer.name) then
			return action.debuff
		elseif (action.debuff ~= nil) and ((action.debuff.prio + 2) < action.cure.prio) then
			return action.debuff
		elseif (action.buff ~= nil) and ((action.buff.prio + 2) < action.cure.prio) then
			return action.buff
		end
		return action.cure
	elseif (action.debuff ~= nil) then
		if (action.buff ~= nil) and (action.buff.prio < action.debuff.prio) then
			return action.buff
		end
		return action.debuff
	elseif (action.buff ~= nil) then
		return action.buff
	end
	return nil
end


function actions.take_action(player, partner, targ)
    if hb.aoe_action then
        healer:take_action(hb.aoe_action)
        return
    end
    buffs.checkOwnBuffs()
    local_queue_reset()
    local action = actions.get_defensive_action()
    if (action ~= nil) then         --If there's a defensive action to perform
        --Record attempt time for buffs/debuffs
        buffs.buffList[action.name] = buffs.buffList[action.name] or {}
        if (action.type == 'buff') and (buffs.buffList[action.name][action.buff]) then
            buffs.buffList[action.name][action.buff].attempted = os.clock()
        elseif (action.type == 'debuff') then
            buffs.debuffList[action.name][action.debuff.id].attempted = os.clock()
        end
        if action.action.accession then
            local accession = lor_res.action_for("Accession")
            if healer:can_use(accession) and utils.ready_to_use(accession) then
                healer:take_action({action=accession}, healer.name)
                hb.aoe_action = action
                return true
            end
        end
        healer:take_action(action)
		--Debuffs with moblist specified, has same priority as healing or buffing - will alternate.
		if offense.moblist.active and offense.moblist.mobs then
			build_mob_debuff_list(player, offense.moblist.mobs)
			return true
		end
		return true
    --Otherwise, there may be an offensive action(Debuffing or engage to attack)
    else             
		--Targetting or Independant mode.
        if (targ ~= nil) or hb.modes.independent then
            local self_engaged = (player.status == 1)
            if (targ ~= nil) then
				local partner_engaged = (partner.status == 1)
				if (player.target_index == partner.target_index) then
					if offense.assist.engage and partner_engaged and (not self_engaged) then
						healer:send_cmd('input /attack on')
						return true
					elseif offense.assist.engage and partner_engaged and self_engaged and (not player.target_locked) then
						healer:send_cmd('input /lockon')
						return true
					--Debuff actions with lock on target
					else
						if not check_moblist_mob(player.target_index) then
							healer:take_action(actions.get_offensive_action(player, partner), '<t>')
						end
						if offense.moblist.active and offense.moblist.mobs then 
							build_mob_debuff_list(player, offense.moblist.mobs)
						end
						return true
					end
				else   --Different targets
					--Assist but not engage
					if partner_engaged and (not self_engaged) and not (offense.assist.nolock) then
						healer:send_cmd('input /as '..offense.assist.name)
						return true
					--Assist + Debuffs with mob id, requires gearswap
					elseif (partner_engaged and partner.target_index and offense.assist.nolock) then
						if not check_moblist_mob(partner.target_index) then
							healer:take_action(actions.get_offensive_action(player, partner), windower.ffxi.get_mob_by_index(partner.target_index).id)
						end
						if (hb.modes.independent and (self_engaged or (player.target_locked and utils.isMonster(player.target_index)))) then
							if not check_moblist_mob(player.target_index) then
								healer:take_action(actions.get_offensive_action(player, nil), '<t>')
							end
						end
						if offense.moblist.active and offense.moblist.mobs then 
							build_mob_debuff_list(player, offense.moblist.mobs)
						end
						return true
					--Switches target to same as partner
					elseif partner_engaged and partner.target_index and self_engaged and not (offense.assist.nolock) and offense.assist.sametarget then
						healer:switch_target(windower.ffxi.get_mob_by_index(partner.target_index).id)
						return true
					end
				end
			-- Debuff without having assist, either engaged or target locked.
            elseif (hb.modes.independent and (self_engaged or (player.target_locked and utils.isMonster(player.target_index)))) then
				if not check_moblist_mob(player.target_index) then
					healer:take_action(actions.get_offensive_action(player, nil), '<t>')
				end
				if offense.moblist.active and offense.moblist.mobs then 
					build_mob_debuff_list(player, offense.moblist.mobs)
				end
				return true
            end
		end
		--Debuffs with mobslist specified within debuffing block
		if offense.moblist.active and offense.moblist.mobs then
			build_mob_debuff_list(player, offense.moblist.mobs)
			return true
        end
    end
	return false
end

--Builder for list of mobs to debuff, accounting for same name mobs.
function build_mob_debuff_list(player, moblist)
	mob_names = T(windower.ffxi.get_mob_list()):filter(set.contains+{moblist})
	for mob_index,mob_name in pairs(mob_names) do
		if utils.isMonster(mob_index) then
			healer:take_action(actions.get_offensive_action_list(player, mob_index), windower.ffxi.get_mob_by_index(mob_index).id)
		end
	end
end

function check_moblist_mob(target_index)
	if not offense.moblist.mobs then return false end
	local target_name = windower.ffxi.get_mob_by_index(target_index).name
	
	for mob_name,_ in pairs(offense.moblist.mobs) do
		if target_name == mob_name then
			return true
		end
	end
	return false
end

--[[
	Builds an action queue for offensive actions.
    Returns the action deemed most important at the time.
--]]
function actions.get_offensive_action(player, partner)
	player = player or windower.ffxi.get_player()
	local target = (partner and partner.target_index and windower.ffxi.get_mob_by_index(partner.target_index)) or windower.ffxi.get_mob_by_target()
    if target == nil or target.hpp == 0 then return nil end
    local action = {}
    
    --Prioritize debuffs over nukes/ws
    local dbuffq = offense.getDebuffQueue(player, target)
    while not dbuffq:empty() do
        local dbact = dbuffq:pop()
        local_queue_insert(dbact.action.en, target.name)
        if (action.db == nil) and healer:in_casting_range(target) and healer:ready_to_use(dbact.action) and (player.vitals.mp >= dbact.action.mp_cost) then
            action.db = dbact
        end
    end
    
    local_queue_disp()
    if action.db ~= nil then
        return action.db
    end
    
    if (not settings.disable.ws) and (settings.ws ~= nil) and healer:ready_to_use(lor_res.action_for(settings.ws.name)) then
        local sign = settings.ws.sign or '>'
        local hp = settings.ws.hp or 0
        local hp_ok = ((sign == '<') and (target.hpp <= hp)) or ((sign == '>') and (target.hpp >= hp))
        
        local partner_ok = true
        if (settings.ws.partner ~= nil) then
            local pname = settings.ws.partner.name
            local partner = ffxi.get_party_member(pname)
            if partner ~= nil then
                partner_ok = partner.tp >= settings.ws.partner.tp
            else
                partner_ok = false
                atc(123,'Unable to locate weaponskill partner '..pname)
            end
        end
        
        if (hp_ok and partner_ok) then
            return {action=lor_res.action_for(settings.ws.name),name='<t>'}
        end
    elseif (not settings.disable.spam) and settings.spam.active and (settings.spam.name ~= nil) then
        local spam_action = lor_res.action_for(settings.spam.name)
        if (target.hpp > 0) and healer:ready_to_use(spam_action) and healer:in_casting_range('<t>') then
            local _p_ok = (player.vitals.mp >= spam_action.mp_cost)
            if spam_action.tp_cost ~= nil then
                _p_ok = (_p_ok and (player.vitals.tp >= spam_action.tp_cost))
            end
            if _p_ok then
                return {action=spam_action,name='<t>'}
            else
                atcd('MP/TP not ok for '..settings.spam.name)
            end
        end
    end
    
    atcd('get_offensive_action: no offensive actions to perform')
	return nil
end

--Moblist debuff - with separate list if defined.  Otherwise use default debuffs
function actions.get_offensive_action_list(player, mob_index)
	player = player or windower.ffxi.get_player()
	local target = (windower.ffxi.get_mob_by_index(mob_index))
    if target == nil or target.hpp == 0 then return nil end
    local action = {}
    
    --Prioritize debuffs over nukes/ws
    local dbuffq = offense.getDebuffQueue(player, target, true)
    while not dbuffq:empty() do
        local dbact = dbuffq:pop()
        local_queue_insert(dbact.action.en, target.name)
        if (action.db == nil) and healer:in_casting_range(target) and healer:ready_to_use(dbact.action) and (player.vitals.mp >= dbact.action.mp_cost) then
            action.db = dbact
        end
    end
    
    local_queue_disp()
    if action.db ~= nil then
        return action.db
    end
   
    atcd('get_offensive_action: no offensive actions to perform')
	return nil
end

return actions

--==============================================================================
--[[
Copyright © 2016, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
--==============================================================================
