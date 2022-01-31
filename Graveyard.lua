



function QuickHoTSingle(playerName, forceMaxRank)

    local _, class = UnitClass('player');
    class = string.lower(class);
    if class == "druid" then
        --
    elseif class == "paladin" then
        return;
    elseif class == "priest" then
        --
    elseif class == "shaman" then
        return;
    end

    -- Only one instance of QuickHeal allowed at a time
    if QuickHealBusy then
        if HealingTarget and MassiveOverhealInProgress then
            QuickHeal_debug("Massive overheal aborted.");
            SpellStopCasting();
        else
            QuickHeal_debug("Healing in progress, command ignored");
        end
        return ;
    end

    QuickHealBusy = true;
    local AutoSelfCast = GetCVar("autoSelfCast");
    SetCVar("autoSelfCast", 0);

    -- Protect against invalid extParam
    if not (type(extParam) == "table") then
        extParam = {}
    end

    Target = FindSingleToHOT(playerName);

    --QuickHeal_debug("********** BREAKPOINT: Well, we got this far. **********");
    --QuickHeal_debug(string.format("  Healing target grr:  (%s)",  Target));
    QuickHeal_debug(string.format("  Healing target grr: " .. tostring(Target)));

    if (Target == nil) or (Target == false) then
        jgpprint("ain't nobody to heal dude")
        SetCVar("autoSelfCast", AutoSelfCast);
        QuickHealBusy = false;
        return;
    end

    -- Target acquired
    --QuickHeal_debug(string.format("  Healing target: %s (%s)", UnitFullName(Target), Target));

    HealingSpellSize = 0;

    SpellID, HealingSpellSize = FindHoTSpellToUse(Target, "hot", forceMaxRank);

    if (SpellID == nil) then
        --jgpprint("ain't nobody to heal dude")
        SetCVar("autoSelfCast", AutoSelfCast);
        QuickHealBusy = false;
        return;
    end

    if SpellID then
        ExecuteHOT(Target, SpellID);
        QuickHealBusy = false;
    else
        Message("You have no healing spells to cast", "Error", 2);
    end

    SetCVar("autoSelfCast", AutoSelfCast);
end

function FindSingleToHOT(playerName)
    local playerIds = {};
    local petIds = {};
    local i;
    local AllPlayersAreFull = true;
    local AllPetsAreFull = true;

    QuickHeal_debug("********** HoT Single **********");

    local healingTarget = nil;
    local healingTargetHealth = 100000;
    local healingTargetHealthPct = 1;
    local healingTargetMissinHealth = 0;
    local unit;

    --jgpprint("forceApplication == " .. tostring(forceApplication))

    if (InRaid()) then
        for i = 1, GetNumRaidMembers() do
            if UnitIsHealable("raid" .. i, true) then
                jgpprint("considering raid" .. i .. ":" .. UnitName("raid" .. i))
                if IsSingleTarget("raid" .. i, playerName) then
                    --if not UnitHasRenew("raid" .. i) then
                    --jgpprint("AAAAAAAAAAAAAAAAAAAAAAAAAA" .. UnitName("raid" .. i) .. " doesn't have renew.")
                    --playerIds["raid" .. i] = i;
                    healingTarget = "raid" .. i;
                    --end
                    --elseif forceApplication then
                    --    healingTarget = "raid" .. i;
                    --end

                    --healingTarget = "raid" .. 1;
                    --return healingTarget;

                    jgpprint(UnitName("raid" .. i) .. " :: " .. "raid" .. i)
                end
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            if UnitIsHealable("party" .. i, true) then
                if IsSingleTarget("party" .. i, playerName) then
                    --playerIds["party" .. i] = i;
                    --if not UnitHasRenew("party" .. i) then
                    healingTarget = "party" .. i;
                    --end

                    jgpprint(UnitName("party" .. i))
                end
            end
        end
    end

    --QuickHeal_debug("********** Done Scanning for single-target HoT **********");

    -- Clear any healable target
    local OldPlaySound = PlaySound;
    PlaySound = function()
    end
    local TargetWasCleared = false;
    if UnitIsHealable('target') then
        TargetWasCleared = true;
        ClearTarget();
    end

    --QuickHeal_debug("********** in the middle **********");

    -- Cast the checkspell
    CastCheckSpellHOT();
    if not SpellIsTargeting() then
        -- Reacquire target if it was cleared
        if TargetWasCleared then
            TargetLastTarget();
        end
        -- Reinsert the PlaySound
        PlaySound = OldPlaySound;
        return false;
    end

    --QuickHeal_debug("********** And then this happens **********");

    -- Examine Healable Players
    --for unit, i in playerIds do
    --    QuickHeal_debug(string.format("%s (%s) : %d/%d", UnitFullName(unit), unit, UnitHealth(unit), UnitHealthMax(unit)));
    --    local SubGroup = false;
    --    if InRaid() and not RestrictParty and RestrictSubgroup and i <= GetNumRaidMembers() then
    --        _, _, SubGroup = GetRaidRosterInfo(i);
    --    end
    --    if not RestrictSubgroup or RestrictParty or not InRaid() or (SubGroup and not QHV["FilterRaidGroup" .. SubGroup]) then
    --        if not IsBlacklisted(UnitFullName(unit)) then
    --            if SpellCanTargetUnit(unit) then
    --                QuickHeal_debug(string.format("%s (%s) : %d/%d", UnitFullName(unit), unit, UnitHealth(unit), UnitHealthMax(unit)));
    --
    --                --Get who to heal for different classes
    --                local IncHeal = HealComm:getHeal(UnitName(unit))
    --                local PredictedHealth = (UnitHealth(unit) + IncHeal)
    --                local PredictedHealthPct = (UnitHealth(unit) + IncHeal) / UnitHealthMax(unit);
    --                local PredictedMissingHealth = UnitHealthMax(unit) - UnitHealth(unit) - IncHeal;
    --
    --                if PredictedHealthPct < QHV.RatioFull then
    --                    local _, PlayerClass = UnitClass('player');
    --                    PlayerClass = string.lower(PlayerClass);
    --
    --                    --if PlayerClass == "shaman" then
    --                    --    if PredictedHealthPct < healingTargetHealthPct then
    --                    --        healingTarget = unit;
    --                    --        healingTargetHealthPct = PredictedHealthPct;
    --                    --        AllPlayersAreFull = false;
    --                    --    end
    --                    if PlayerClass == "priest" then
    --                        --writeLine("Find who to heal for Priest");
    --                        if healPlayerWithLowestPercentageOfLife == 1 then
    --                            if PredictedHealthPct < healingTargetHealthPct then
    --                                --if not UnitHasRenew(unit) then
    --                                    --QuickHeal_debug("********** Hot target don't got HoT **********");
    --                                    healingTarget = unit;
    --                                    healingTargetHealthPct = PredictedHealthPct;
    --                                    AllPlayersAreFull = false;
    --                                --else
    --                                --    QuickHeal_debug("********** Hot target got HoT **********");
    --                                --end
    --                            end
    --                        else
    --                            if PredictedMissingHealth > healingTargetMissinHealth then
    --                                --if not UnitHasRenew(unit) then
    --                                    --QuickHeal_debug("********** Hot target don't got HoT **********");
    --                                    healingTarget = unit;
    --                                    healingTargetMissinHealth = PredictedMissingHealth;
    --                                    AllPlayersAreFull = false;
    --                                --else
    --                                --    QuickHeal_debug("********** Hot target got HoT **********");
    --                                --end
    --                            end
    --                        end
    --                    --elseif PlayerClass == "paladin" then
    --                    --    --writeLine("Find who to heal for Paladin")
    --                    --    if healPlayerWithLowestPercentageOfLife == 1 then
    --                    --        if PredictedHealthPct < healingTargetHealthPct then
    --                    --            healingTarget = unit;
    --                    --            healingTargetHealthPct = PredictedHealthPct;
    --                    --            AllPlayersAreFull = false;
    --                    --        end
    --                    --    else
    --                    --        if PredictedHealth < healingTargetHealth then
    --                    --            healingTarget = unit;
    --                    --            healingTargetHealth = PredictedHealth;
    --                    --            AllPlayersAreFull = false;
    --                    --        end
    --                    --    end
    --                    elseif PlayerClass == "druid" then
    --                        if PredictedHealthPct < healingTargetHealthPct then
    --                            healingTarget = unit;
    --                            healingTargetHealthPct = PredictedHealthPct;
    --                            AllPlayersAreFull = false;
    --                        end
    --                    else
    --                        writeLine(QuickHealData.name .. " " .. QuickHealData.version .. " does not support " .. UnitClass('player') .. ". " .. QuickHealData.name .. " not loaded.")
    --                        return ;
    --                    end
    --                end
    --
    --
    --                --writeLine("Values for "..UnitName(unit)..":")
    --                --writeLine("Health: "..UnitHealth(unit) / UnitHealthMax(unit).." | IncHeal: "..IncHeal / UnitHealthMax(unit).." | PredictedHealthPct: "..PredictedHealthPct) --Edelete
    --            else
    --                QuickHeal_debug(UnitFullName(unit) .. " (" .. unit .. ")", "is out-of-range or unhealable");
    --            end
    --        else
    --            QuickHeal_debug(UnitFullName(unit) .. " (" .. unit .. ")", "is blacklisted");
    --        end
    --    end
    --end
    --healPlayerWithLowestPercentageOfLife = 0

    -- Reacquire target if it was cleared earlier, and stop CheckSpell
    SpellStopTargeting();
    if TargetWasCleared then
        TargetLastTarget();
    end
    PlaySound = OldPlaySound;

    ---- Examine External Target
    --if AllPlayersAreFull and (AllPetsAreFull or QHV.PetPriority == 0) then
    --    if not QuickHeal_UnitHasHealthInfo('target') and UnitIsHealable('target', true) then
    --        QuickHeal_debug(string.format("%s (%s) : %d/%d", UnitFullName('target'), 'target', UnitHealth('target'), UnitHealthMax('target')));
    --        local Health;
    --        Health = UnitHealth('target') / 100;
    --        if Health < QHV.RatioFull then
    --            return 'target';
    --        end
    --    end
    --end

    if UnitHasRenew(healingTarget) then
        healingTarget = nil;
    end


    return healingTarget;
end

function QuickHealSingle(playerName, multiplier)

    if multiplier == nil then
        multiplier = 1.0;
    end

    -- Only one instance of QuickHeal allowed at a time
    if QuickHealBusy then
        if HealingTarget and MassiveOverhealInProgress then
            QuickHeal_debug("Massive overheal aborted.");
            SpellStopCasting();
        else
            QuickHeal_debug("Healing in progress, command ignored");
        end
        return ;
    end

    QuickHealBusy = true;
    local AutoSelfCast = GetCVar("autoSelfCast");
    SetCVar("autoSelfCast", 0);

    -- Protect against invalid extParam
    if not (type(extParam) == "table") then
        extParam = {}
    end

    Target = FindSingleToHeal(playerName, multiplier);

    if (Target == nil) then
        --jgpprint("ain't nobody to heal dude")
        SetCVar("autoSelfCast", AutoSelfCast);
        QuickHealBusy = false;
        return;
    end

    -- Target acquired
    QuickHeal_debug(string.format("  Healing target: %s (%s)", UnitFullName(Target), Target));


    HealingSpellSize = 0;

    SpellID, HealingSpellSize = FindHealSpellToUse(Target, "channel", multiplier, nil);

    if (SpellID == nil) then
        --jgpprint("ain't nobody to heal dude")
        SetCVar("autoSelfCast", AutoSelfCast);
        QuickHealBusy = false;
        return;
    end

    -- Spell acquired
    QuickHeal_debug(string.format("  Spell & Size: %s (%s)", SpellID, HealingSpellSize));

    if SpellID then
        ExecuteSingleHeal(Target, SpellID, multiplier);
    else
        Message("You have no healing spells to cast", "Error", 2);
    end

    SetCVar("autoSelfCast", AutoSelfCast);
end

function FindSingleToHeal(playerName, multiplier)
    local playerIds = {};
    local petIds = {};
    local i;
    local AllPlayersAreFull = true;
    local AllPetsAreFull = true;

    QuickHeal_debug("********** Heal Single **********");

    local healingTarget = nil;
    local healingTargetHealth = 100000;
    local healingTargetHealthPct = 1;
    local healingTargetMissinHealth = 0;
    local unit;

    if (InRaid()) then
        for i = 1, GetNumRaidMembers() do
            if UnitIsHealable("raid" .. i, true) then
                jgpprint("considering raid" .. i .. ":" .. UnitName("raid" .. i))
                if IsSingleTarget("raid" .. i, playerName) then
                    --playerIds["raid" .. i] = i;  -- every one that will be considered for heal
                    healingTarget = "raid" .. i;
                    --jgpprint(UnitName("raid" .. i))
                end
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            if UnitIsHealable("party" .. i, true) then
                if IsSingleTarget("party" .. i, playerName) then
                    --playerIds["party" .. i] = i;  -- every one that will be considered for heal
                    healingTarget = "party" .. i;
                    --jgpprint(UnitName("party" .. i))
                end
            end
        end
    end



    QuickHeal_debug("********** Done Scanning for single-target Heal **********");

    -- Clear any healable target
    local OldPlaySound = PlaySound;
    PlaySound = function()
    end
    local TargetWasCleared = false;
    if UnitIsHealable('target') then
        TargetWasCleared = true;
        ClearTarget();
    end

    -- Cast the checkspell
    CastCheckSpell();
    if not SpellIsTargeting() then
        -- Reacquire target if it was cleared
        if TargetWasCleared then
            TargetLastTarget();
        end
        -- Reinsert the PlaySound
        PlaySound = OldPlaySound;
        return false;
    end

    --for unit, i in playerIds do
    --    local SubGroup = false;
    --    if InRaid() and not RestrictParty and RestrictSubgroup and i <= GetNumRaidMembers() then
    --        _, _, SubGroup = GetRaidRosterInfo(i);
    --    end
    --    if not RestrictSubgroup or RestrictParty or not InRaid() or (SubGroup and not QHV["FilterRaidGroup" .. SubGroup]) then
    --        if not IsBlacklisted(UnitFullName(unit)) then
    --            if SpellCanTargetUnit(unit) then
    --                QuickHeal_debug(string.format("%s (%s) : %d/%d", UnitFullName(unit), unit, UnitHealth(unit), UnitHealthMax(unit)));
    --
    --                --Get who to heal for different classes
    --                local IncHeal = HealComm:getHeal(UnitName(unit))
    --                local PredictedHealth = (UnitHealth(unit) + IncHeal)
    --                local PredictedHealthPct = (UnitHealth(unit) + IncHeal) / UnitHealthMax(unit);
    --                local PredictedMissingHealth = UnitHealthMax(unit) - UnitHealth(unit) - IncHeal;
    --
    --                if PredictedHealthPct < QHV.RatioFull then
    --                    local _, PlayerClass = UnitClass('player');
    --                    PlayerClass = string.lower(PlayerClass);
    --
    --                    if PlayerClass == "shaman" then
    --                        if PredictedHealthPct < healingTargetHealthPct then
    --                            healingTarget = unit;
    --                            healingTargetHealthPct = PredictedHealthPct;
    --                            AllPlayersAreFull = false;
    --                        end
    --                    elseif PlayerClass == "priest" then
    --                        --writeLine("Find who to heal for Priest");
    --                        if healPlayerWithLowestPercentageOfLife == 1 then
    --                            if PredictedHealthPct < healingTargetHealthPct then
    --                                healingTarget = unit;
    --                                healingTargetHealthPct = PredictedHealthPct;
    --                                AllPlayersAreFull = false;
    --                            end
    --                        else
    --                            if PredictedMissingHealth > healingTargetMissinHealth then
    --                                healingTarget = unit;
    --                                healingTargetMissinHealth = PredictedMissingHealth;
    --                                AllPlayersAreFull = false;
    --                            end
    --                        end
    --                    elseif PlayerClass == "paladin" then
    --                        --writeLine("Find who to heal for Paladin")
    --                        if healPlayerWithLowestPercentageOfLife == 1 then
    --                            if PredictedHealthPct < healingTargetHealthPct then
    --                                healingTarget = unit;
    --                                healingTargetHealthPct = PredictedHealthPct;
    --                                AllPlayersAreFull = false;
    --                            end
    --                        else
    --                            if PredictedHealth < healingTargetHealth then
    --                                healingTarget = unit;
    --                                healingTargetHealth = PredictedHealth;
    --                                AllPlayersAreFull = false;
    --                            end
    --                        end
    --                    elseif PlayerClass == "druid" then
    --                        if PredictedHealthPct < healingTargetHealthPct then
    --                            healingTarget = unit;
    --                            healingTargetHealthPct = PredictedHealthPct;
    --                            AllPlayersAreFull = false;
    --                        end
    --                    else
    --                        writeLine(QuickHealData.name .. " " .. QuickHealData.version .. " does not support " .. UnitClass('player') .. ". " .. QuickHealData.name .. " not loaded.")
    --                        return ;
    --                    end
    --                end
    --
    --
    --                --writeLine("Values for "..UnitName(unit)..":")
    --                --writeLine("Health: "..UnitHealth(unit) / UnitHealthMax(unit).." | IncHeal: "..IncHeal / UnitHealthMax(unit).." | PredictedHealthPct: "..PredictedHealthPct) --Edelete
    --            else
    --                QuickHeal_debug(UnitFullName(unit) .. " (" .. unit .. ")", "is out-of-range or unhealable");
    --            end
    --        else
    --            QuickHeal_debug(UnitFullName(unit) .. " (" .. unit .. ")", "is blacklisted");
    --        end
    --    end
    --end




    healPlayerWithLowestPercentageOfLife = 0



    -- Reacquire target if it was cleared earlier, and stop CheckSpell
    SpellStopTargeting();
    if TargetWasCleared then
        TargetLastTarget();
    end
    PlaySound = OldPlaySound;

    ---- Examine External Target
    --if AllPlayersAreFull and (AllPetsAreFull or QHV.PetPriority == 0) then
    --    if not QuickHeal_UnitHasHealthInfo('target') and UnitIsHealable('target', true) then
    --        QuickHeal_debug(string.format("%s (%s) : %d/%d", UnitFullName('target'), 'target', UnitHealth('target'), UnitHealthMax('target')));
    --        local Health;
    --        Health = UnitHealth('target') / 100;
    --        if Health < QHV.RatioFull then
    --            return 'target';
    --        end
    --    end
    --end

    return healingTarget;
end

-- Returns true if the unit matches playerName string
function IsSingleTarget(unit, playerName)
    if playerName == UnitName(unit) then
        return true;
    end
end

function ExecuteSingleHeal(Target, SpellID, multiplier)
    local TargetWasChanged = false;

    -- Setup the monitor and related events
    StartMonitor(Target, multiplier);

    -- Supress sound from target-switching
    local OldPlaySound = PlaySound;
    PlaySound = function()
    end

    -- If the current target is healable, take special measures
    if UnitIsHealable('target') then
        -- If the healing target is targettarget change current healable target to targettarget
        if Target == 'targettarget' then
            local old = UnitFullName('target');
            TargetUnit('targettarget');
            Target = 'target';
            TargetWasChanged = true;
            QuickHeal_debug("Healable target preventing healing, temporarily switching target to target's target", old, '-->', UnitFullName('target'));
        end
        -- If healing target is not the current healable target clear the healable target
        if not (Target == 'target') then
            QuickHeal_debug("Healable target preventing healing, temporarily clearing target", UnitFullName('target'));
            ClearTarget();
            TargetWasChanged = true;
        end
    end

    -- Get spell info
    local SpellName, SpellRank = GetSpellName(SpellID, BOOKTYPE_SPELL);
    if SpellRank == "" then
        SpellRank = nil
    end
    local SpellNameAndRank = SpellName .. (SpellRank and " (" .. SpellRank .. ")" or "");

    QuickHeal_debug("  Casting: " .. SpellNameAndRank .. " on " .. UnitFullName(Target) .. " (" .. Target .. ")" .. ", ID: " .. SpellID);

    -- Clear any pending spells
    if SpellIsTargeting() then
        SpellStopTargeting()
    end

    -- Cast the spell
    CastSpell(SpellID, BOOKTYPE_SPELL);

    -- Target == 'target'
    -- Instant channeling --> succesful cast
    -- Instant channeling --> instant 'out of range' fail
    -- Instant channeling --> delayed 'line of sight' fail
    -- No channeling --> SpellStillTargeting (unhealable NPC's, duelists etc.)

    -- Target ~= 'target'
    -- SpellCanTargetUnit == true
    -- Channeling --> succesful cast
    -- Channeling --> instant 'out of range' fail
    -- Channeling --> delayed 'line of sight' fail
    -- No channeling --> SpellStillTargeting (unknown circumstances)
    -- SpellCanTargetUnit == false
    -- Duels/unhealable NPC's etc.

    -- The spell is awaiting target selection, write to screen if the spell can actually be cast
    if SpellCanTargetUnit(Target) or ((Target == 'target') and HealingTarget) then

        Notification(Target, SpellNameAndRank);

        -- Write to center of screen
        if UnitIsUnit(Target, 'player') then
            Message(string.format("Casting %s on yourself", SpellNameAndRank), "Healing", 3)
        else
            Message(string.format("Casting %s on %s", SpellNameAndRank, UnitFullName(Target)), "Healing", 3)
        end
    end

    -- Assign the target of the healing spell
    SpellTargetUnit(Target);

    -- just in case something went wrong here (Healing people in duels!)
    if SpellIsTargeting() then
        StopMonitor("Spell cannot target " .. (UnitFullName(Target) or "unit"));
        SpellStopTargeting()
    end

    -- Reacquire target if it was changed earlier
    if TargetWasChanged then
        local old = UnitFullName('target') or "None";
        TargetLastTarget();
        QuickHeal_debug("Reacquired previous target", old, '-->', UnitFullName('target'));
    end

    -- Enable sound again
    PlaySound = OldPlaySound;
end