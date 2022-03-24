local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

function QuickHeal_Paladin_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_HOLY_LIGHT .. " will never be used in combat. ";
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the target has more than " .. RatioHealthy*100 .. "% life, and only if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. ";
        else
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " will only be used in combat if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT .. " available. ";
        end
    end
end

function QuickHeal_Paladin_FindSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediatly if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- Determine health and healneed of target
    local healneed;
    local Health;

    if QuickHeal_UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementatin for HealComm
        if Overheal then
            healneed = healneed * multiplier;
        else
            --
        end
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = QuickHeal_EstimateUnitHealNeed(Target,true); -- needs HealComm implementation maybe
        if Overheal then
            healneed = healneed * multiplier;
        else
            --
        end
        Health = UnitHealth(Target)/100;
    end

    -- if BonusScanner is running, get +Healing bonus
    local Bonus = 0;
    if (BonusScanner) then
        Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        debug(string.format("Equipment Healing Bonus: %d", Bonus));
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,5);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Lesser Healing Wave' and 'Healing Wave'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (LHW and HW Rank 1 and 2) and K for slow spells (HW)            3 = 4 | 3 < 4 | 3 > 4
    end

    if not forceMaxHPS then
        if Health < RatioFull then
            if maxRankFL >=1                                                                                                                      then SpellID = SpellIDsFL[1]; HealSize = 67*hlMod+healMod15 else SpellID = SpellIDsHL[1]; HealSize = 43*hlMod+healMod25*PF1 end -- Default to rank 1 of FL or HL
            if healneed     > ( 83*hlMod+healMod25*PF6 )*K and ManaLeft >= 60  and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) then SpellID = SpellIDsHL[2]; HealSize =  83*hlMod+healMod25*PF6  end
            if healneed     > (103*hlMod+healMod15)     *k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2                              then SpellID = SpellIDsFL[2]; HealSize = 103*hlMod+healMod15      end
            if healneed     > (154*hlMod+healMod15)     *k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3                              then SpellID = SpellIDsFL[3]; HealSize = 154*hlMod+healMod15      end
            if healneed     > (173*hlMod+healMod25*PF14)*K and ManaLeft >= 110 and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) then SpellID = SpellIDsHL[3]; HealSize = 173*hlMod+healMod25*PF14 end
            if healneed     > (209*hlMod+healMod15)     *k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4                              then SpellID = SpellIDsFL[4]; HealSize = 209*hlMod+healMod15      end
            if healneed     > (283*hlMod+healMod15)     *k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5                              then SpellID = SpellIDsFL[5]; HealSize = 283*hlMod+healMod15      end
            if healneed     > (333*hlMod+healMod25)     *K and ManaLeft >= 190 and maxRankHL >=4 and (TargetIsHealthy and maxRankFL <= 5 or NoFL) then SpellID = SpellIDsHL[4]; HealSize = 333*hlMod+healMod25      end
            if healneed     > (363*hlMod+healMod15)     *k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6                              then SpellID = SpellIDsFL[6]; HealSize = 363*hlMod+healMod15      end
            if healneed     > (522*hlMod+healMod25)     *K and ManaLeft >= 275 and maxRankHL >=5 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[5]; HealSize = 522*hlMod+healMod25      end
            if healneed     > (739*hlMod+healMod25)     *K and ManaLeft >= 365 and maxRankHL >=6 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[6]; HealSize = 739*hlMod+healMod25      end
            if healneed     > (999*hlMod+healMod25)     *K and ManaLeft >= 465 and maxRankHL >=7 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[7]; HealSize = 999*hlMod+healMod25      end
            if healneed     > (1317*hlMod+healMod25)    *K and ManaLeft >= 580 and maxRankHL >=8 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[8]; HealSize = 1317*hlMod+healMod25     end
            if healneed     > (1680*hlMod+healMod25)    *K and ManaLeft >= 660 and maxRankHL >=9 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[9]; HealSize = 1680*hlMod+healMod25     end
        end
    else
        if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 then SpellID = SpellIDsFL[1]; HealSize = 67*hlMod+healMod15 end
        if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 then SpellID = SpellIDsFL[2]; HealSize = 103*hlMod+healMod15 end
        if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 then SpellID = SpellIDsFL[3]; HealSize = 154*hlMod+healMod15 end
        if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 then SpellID = SpellIDsFL[4]; HealSize = 209*hlMod+healMod15 end
        if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 then SpellID = SpellIDsFL[5]; HealSize = 283*hlMod+healMod15 end
        if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 then SpellID = SpellIDsFL[6]; HealSize = 363*hlMod+healMod15 end
    end
    return SpellID,HealSize*HDB;
end

function QuickHeal_Paladin_FindSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- Determine health and heal need of target
    local healneed = healDeficit * multiplier;
    local Health = healDeficit / maxhealth;

    -- if BonusScanner is running, get +Healing bonus
    local Bonus = 0;
    if (BonusScanner) then
        Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        debug(string.format("Equipment Healing Bonus: %d", Bonus));
    end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,5);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Lesser Healing Wave' and 'Healing Wave'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (LHW and HW Rank 1 and 2) and K for slow spells (HW)            3 = 4 | 3 < 4 | 3 > 4
    end

    if not forceMaxHPS then
        if maxRankFL >=1                                                                                                                      then SpellID = SpellIDsFL[1]; HealSize = 67*hlMod+healMod15 else SpellID = SpellIDsHL[1]; HealSize = 43*hlMod+healMod25*PF1 end -- Default to rank 1 of FL or HL
        if healneed     > ( 83*hlMod+healMod25*PF6 )*K and ManaLeft >= 60  and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) then SpellID = SpellIDsHL[2]; HealSize =  83*hlMod+healMod25*PF6  end
        if healneed     > (103*hlMod+healMod15)     *k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2                              then SpellID = SpellIDsFL[2]; HealSize = 103*hlMod+healMod15      end
        if healneed     > (154*hlMod+healMod15)     *k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3                              then SpellID = SpellIDsFL[3]; HealSize = 154*hlMod+healMod15      end
        if healneed     > (173*hlMod+healMod25*PF14)*K and ManaLeft >= 110 and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) then SpellID = SpellIDsHL[3]; HealSize = 173*hlMod+healMod25*PF14 end
        if healneed     > (209*hlMod+healMod15)     *k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4                              then SpellID = SpellIDsFL[4]; HealSize = 209*hlMod+healMod15      end
        if healneed     > (283*hlMod+healMod15)     *k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5                              then SpellID = SpellIDsFL[5]; HealSize = 283*hlMod+healMod15      end
        if healneed     > (333*hlMod+healMod25)     *K and ManaLeft >= 190 and maxRankHL >=4 and (TargetIsHealthy and maxRankFL <= 5 or NoFL) then SpellID = SpellIDsHL[4]; HealSize = 333*hlMod+healMod25      end
        if healneed     > (363*hlMod+healMod15)     *k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6                              then SpellID = SpellIDsFL[6]; HealSize = 363*hlMod+healMod15      end
        if healneed     > (522*hlMod+healMod25)     *K and ManaLeft >= 275 and maxRankHL >=5 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[5]; HealSize = 522*hlMod+healMod25      end
        if healneed     > (739*hlMod+healMod25)     *K and ManaLeft >= 365 and maxRankHL >=6 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[6]; HealSize = 739*hlMod+healMod25      end
        if healneed     > (999*hlMod+healMod25)     *K and ManaLeft >= 465 and maxRankHL >=7 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[7]; HealSize = 999*hlMod+healMod25      end
        if healneed     > (1317*hlMod+healMod25)    *K and ManaLeft >= 580 and maxRankHL >=8 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[8]; HealSize = 1317*hlMod+healMod25     end
        if healneed     > (1680*hlMod+healMod25)    *K and ManaLeft >= 660 and maxRankHL >=9 and (TargetIsHealthy and maxRankFL <= 6 or NoFL) then SpellID = SpellIDsHL[9]; HealSize = 1680*hlMod+healMod25     end
    else
        if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 then SpellID = SpellIDsFL[1]; HealSize = 67*hlMod+healMod15 end
        if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 then SpellID = SpellIDsFL[2]; HealSize = 103*hlMod+healMod15 end
        if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 then SpellID = SpellIDsFL[3]; HealSize = 154*hlMod+healMod15 end
        if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 then SpellID = SpellIDsFL[4]; HealSize = 209*hlMod+healMod15 end
        if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 then SpellID = SpellIDsFL[5]; HealSize = 283*hlMod+healMod15 end
        if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 then SpellID = SpellIDsFL[6]; HealSize = 363*hlMod+healMod15 end
    end

    return SpellID,HealSize*hdb;
end

function QuickHeal_Command_Paladin(msg)

    --if PlayerClass == "priest" then
    --  writeLine("PALADIN", 0, 1, 0);
    --end

    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- match 3 arguments
    if arg1 ~= nil and arg2 ~= nil and arg3 ~= nil then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL(maxHPS)", 0, 1, 0);
                --QuickHeal(arg1, nil, nil, true);
                QuickHeal(arg1, nil, nil, true);
                return;
            end
        end
    end

    -- match 2 arguments
    local _, _, arg4, arg5= string.find(msg, "%s?(%w+)%s?(%w+)")

    if arg4 ~= nil and arg5 ~= nil then
        if arg4 == "debug" then
            if arg5 == "on" then
                QHV.DebugMode = true;
                --writeLine(QuickHealData.name .. " debug mode enabled", 0, 0, 1);
                return;
            elseif arg5 == "off" then
                QHV.DebugMode = false;
                --writeLine(QuickHealData.name .. " debug mode disabled", 0, 0, 1);
                return;
            end
        end
        if arg4 == "heal" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HEAL (max)", 0, 1, 0);
            QuickHeal(nil, nil, nil, true);
            return;
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "heal" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL", 0, 1, 0);
                QuickHeal(arg1, nil, nil, false);
                return;
            end
        end
    end

    -- match 1 argument
    local cmd = string.lower(msg)

    if cmd == "cfg" then
        QuickHeal_ToggleConfigurationPanel();
        return;
    end

    if cmd == "toggle" then
        QuickHeal_Toggle_Healthy_Threshold();
        return;
    end

    if cmd == "downrank" or cmd == "dr" then
        ToggleDownrankWindow()
        return;
    end

    if cmd == "tanklist" or cmd == "tl" then
        QH_ShowHideMTListUI();
        return;
    end

    if cmd == "reset" then
        QuickHeal_SetDefaultParameters();
        writeLine(QuickHealData.name .. " reset to default configuration", 0, 0, 1);
        QuickHeal_ToggleConfigurationPanel();
        QuickHeal_ToggleConfigurationPanel();
        return;
    end

    if cmd == "heal" then
        --writeLine(QuickHealData.name .. " HEAL", 0, 1, 0);
        QuickHeal();
        return;
    end

    if cmd == "" then
        --writeLine(QuickHealData.name .. " qh", 0, 1, 0);
        QuickHeal(nil);
        return;
    elseif cmd == "player" or cmd == "target" or cmd == "targettarget" or cmd == "party" or cmd == "subgroup" or cmd == "mt" or cmd == "nonmt" then
        --writeLine(QuickHealData.name .. " qh " .. cmd, 0, 1, 0);
        QuickHeal(cmd);
        return;
    end

    -- Print usage information if arguments do not match
    --writeLine(QuickHealData.name .. " Usage:");
    writeLine("== QUICKHEAL USAGE : PALADIN ==");
    writeLine("/qh cfg - Opens up the configuration panel.");
    writeLine("/qh toggle - Switches between High HPS and Normal HPS.  Heals (Healthy Threshold 0% or 100%).");
    writeLine("/qh downrank | dr - Opens the slider to limit QuickHeal to constrain healing to lower ranks.");
    writeLine("/qh tanklist | tl - Toggles display of the main tank list UI.");
    writeLine("/qh [mask] [type] [mod] - Heals the party/raid member that most needs it with the best suited healing spell.");
    writeLine(" [mask] constrains healing pool to:");
    writeLine("  [player] yourself");
    writeLine("  [target] your target");
    writeLine("  [targettarget] your target's target");
    writeLine("  [party] your party");
    writeLine("  [mt] main tanks (defined in the configuration panel)");
    writeLine("  [nonmt] everyone but the main tanks");
    writeLine("  [subgroup] raid subgroups (defined in the configuration panel)");

    writeLine(" [mod] (optional) modifies [heal] options:");
    writeLine("  [max] applies maximum rank HPS [heal] to subgroup members that have <100% health");

    writeLine("/qh reset - Reset configuration to default parameters for all classes.");
end