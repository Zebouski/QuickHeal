
function QuickHeal_Shaman_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_HEALING_WAVE .. " will never be used in combat. ";
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HEALING_WAVE .. " will only be used in combat if the target has more than " .. RatioHealthy*100 .. "% life, and only if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_LESSER_HEALING_WAVE .. " available. ";
        else
            return QUICKHEAL_SPELL_HEALING_WAVE .. " will only be used in combat if the healing done is greater than the greatest " .. QUICKHEAL_SPELL_LESSER_HEALING_WAVE .. " available. ";
        end
    end
end

function QuickHeal_Shaman_FindChainHealSpellToUse(Target, healType, multiplier, forceMaxRank)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF12 = 0.7;
    local PF18 = 0.925;

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

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    -- THIS IS WHERE BUG HAPPENS
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediatly if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    -- Determine health and healneed of target
    local healneed;
    local Health;
    if UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementation for HealComm
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = EstimateUnitHealNeed(Target,true);
        Health = UnitHealth(Target)/100;
    end

    -- if BonusScanner is running, get +Healing bonus
    local Bonus = 0;
    if (BonusScanner) then
        Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        debug(string.format("Equipment Healing Bonus: %d", Bonus));
    end

    -- Calculate healing bonus
    local healModLHW = (1.5/3.5) * Bonus;
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,LHW)", healMod15,healMod20,healMod25,healMod30,healModLHW);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Purification Talent (increases healing by 2% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local pMod = 2*talentRank/100 + 1;
    debug(string.format("Purification modifier: %f", pMod))

    -- Tidal Focus - Decreases mana usage by 1% per rank on healing
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,2);
    local tfMod = 1 - talentRank/100;
    debug(string.format("Improved Healing modifier: %f", tfMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health)
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        InCombat = false;
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

    -- Detect healing way on target
    local hwMod = QuickHeal_DetectBuff(Target,"Spell_Nature_HealingWay");
    if hwMod then hwMod = 1+0.06*hwMod else hwMod = 1 end;
    debug("Healing Way healing modifier",hwMod);

    -- Get a list of ranks available of 'Lesser Healing Wave' and 'Healing Wave'
    local SpellIDsCH = GetSpellIDs(QUICKHEAL_SPELL_CHAIN_HEAL);
    local maxRankCH = table.getn(SpellIDsCH);

    --local SpellIDsHW = GetSpellIDs(QUICKHEAL_SPELL_HEALING_WAVE);
    --local SpellIDsLHW = GetSpellIDs(QUICKHEAL_SPELL_LESSER_HEALING_WAVE);
    --local maxRankHW = table.getn(SpellIDsHW);
    --local maxRankLHW = table.getn(SpellIDsLHW);
    --local NoLHW = maxRankLHW < 1;


    -- DEBUG display GetSpellIDs table
    debug(string.format("Found CH up to rank %d", maxRankCH))
    for index, data in ipairs(SpellIDsCH) do
        debug('GetSpellIDs:' .. index .. ':' .. data)
    end

    --Get max HealRanks that are allowed to be used (we haven't implemented this)
    --local downRankCH = QuickHealVariables.DownrankValueCH -- rank for 1.5 sec heals
    --
    --local downRankFH = QuickHealVariables.DownrankValueFH -- rank for 1.5 sec heals
    --local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals

    -- DEBUG force InCombat to always true
    --InCombat = true;

    -- Find suitable SpellID based on the defined criteria
    ---prefers chain heal rank one
    local k = 0.9; -- In combat means that target is losing life while casting, so compensate
    local K = 0.8; -- k for fast spells (LHW and HW Rank 1 and 2) and K for slow spells (HW)

    if not forceMaxRank then
        SpellID = SpellIDsCH[1]; HealSize = 356*pMod+healMod25;
        --if healneed > (356*pMod*hwMod+healMod25) and ManaLeft >= 260 *tfMod and maxRankCH >=1 then SpellID = SpellIDsCH[1]; HealSize = 356*pMod+healMod25 end
        if healneed > (898*pMod*hwMod+healMod25) and ManaLeft >= 315 *tfMod and maxRankCH >=2 then SpellID = SpellIDsCH[2]; HealSize = 449*pMod+healMod25 end
        if healneed > (1213*pMod*hwMod+healMod25) and ManaLeft >= 405 *tfMod and maxRankCH >=3 then SpellID = SpellIDsCH[3]; HealSize = 607*pMod+healMod25 end
    else
        SpellID = SpellIDsCH[3]; HealSize = 607*pMod+healMod25;
        --if ManaLeft >= 260 *tfMod and maxRankCH >=1 then SpellID = SpellIDsCH[1]; HealSize = 356*pMod+healMod25 end
        --if ManaLeft >= 315 *tfMod and maxRankCH >=2 then SpellID = SpellIDsCH[2]; HealSize = 449*pMod+healMod25 end
        --if ManaLeft >= 405 *tfMod and maxRankCH >=3 then SpellID = SpellIDsCH[3]; HealSize = 607*pMod+healMod25 end
    end

    --SpellID = SpellIDsCH[3];
    --HealSize = 0;

    debug(string.format("about to print spellid.  HealSize:%d", HealSize))
    debug(string.format("wow SpellID:%s HealSize:%s", SpellID, HealSize))
    return SpellID,HealSize*HDB;
end

function QuickHeal_Shaman_FindHealSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF12 = 0.7;
    local PF18 = 0.925;

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

    -- Determine health and healneed of target
    local healneed;
    local Health;
    if UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementatio for HealComm
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = EstimateUnitHealNeed(Target,true);
        Health = UnitHealth(Target)/100;
    end

    -- if BonusScanner is running, get +Healing bonus
    local Bonus = 0;
    if (BonusScanner) then
        Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        debug(string.format("Equipment Healing Bonus: %d", Bonus));
    end

    -- Calculate healing bonus
    local healModLHW = (1.5/3.5) * Bonus;
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,LHW)", healMod15,healMod20,healMod25,healMod30,healModLHW);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Purification Talent (increases healing by 2% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local pMod = 2*talentRank/100 + 1;
    debug(string.format("Purification modifier: %f", pMod))

    -- Tidal Focus - Decreases mana usage by 1% per rank on healing
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,2);
    local tfMod = 1 - talentRank/100;
    debug(string.format("Improved Healing modifier: %f", tfMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health)
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        InCombat = false;
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

    -- Detect healing way on target
    local hwMod = QuickHeal_DetectBuff(Target,"Spell_Nature_HealingWay");
    if hwMod then hwMod = 1+0.06*hwMod else hwMod = 1 end;
    debug("Healing Way healing modifier",hwMod);

    -- Get a list of ranks available of 'Lesser Healing Wave' and 'Healing Wave'
    local SpellIDsHW = GetSpellIDs(QUICKHEAL_SPELL_HEALING_WAVE);
    local SpellIDsLHW = GetSpellIDs(QUICKHEAL_SPELL_LESSER_HEALING_WAVE);
    local maxRankHW = table.getn(SpellIDsHW);
    local maxRankLHW = table.getn(SpellIDsLHW);
    local NoLHW = maxRankLHW < 1;
    debug(string.format("Found HW up to rank %d, and found LHW up to rank %d", maxRankHW, maxRankLHW))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals

    -- Find suitable SpellID based on the defined criteria
    if InCombat then
        -- In combat so use LHW unless:
        -- Target is healthy (health > RatioHealthy)
        -- AND The HW in question is larger than any available LHW
        -- OR LHW is unavailable (sub level 20 characters)
        debug(string.format("In combat, will prefer LHW"))
        if Health < RatioFull then
            local k = 0.9; -- In combat means that target is losing life while casting, so compensate
            local K = 0.8; -- k for fast spells (LHW and HW Rank 1 and 2) and K for slow spells (HW)
            if maxRankLHW >=1 then SpellID = SpellIDsLHW[1]; HealSize = 174*pMod+healModLHW else SpellID = SpellIDsHW[1]; HealSize = 39*pMod*hwMod+healMod15*PF1 end -- Default to HW or LHW
            --if healneed > (  71*pMod*hwMod+healMod20*PF6 )*k and ManaLeft >= 45*tfMod and maxRankHW >=2 and downRankNH >=2 and NoLHW then SpellID = SpellIDsHW[2]; HealSize =  71*pMod*hwMod+healMod20*PF6 end
            if healneed > (  71*pMod*hwMod+healMod20*PF6 )*k and ManaLeft >= 45*tfMod and maxRankHW >=2 and downRankNH >=2 then SpellID = SpellIDsHW[2]; HealSize =  71*pMod*hwMod+healMod20*PF6 end
            --if healneed > ( 142*pMod*hwMod+healMod25*PF12)*K and ManaLeft >= 80*tfMod and maxRankHW >=3 and downRankNH >=3 and NoLHW then SpellID = SpellIDsHW[3]; HealSize = 142*pMod*hwMod+healMod25*PF12 end
            if healneed > ( 142*pMod*hwMod+healMod25*PF12)*K and ManaLeft >= 80*tfMod and maxRankHW >=3 and downRankNH >=3 then SpellID = SpellIDsHW[3]; HealSize = 142*pMod*hwMod+healMod25*PF12 end
            if healneed > (174*pMod+healModLHW)*k and ManaLeft >= 105*tfMod and maxRankLHW >=1 and downRankFH >=1 then SpellID = SpellIDsLHW[1]; HealSize = 174*pMod+healModLHW end
            if healneed > (264*pMod+healModLHW)*k and ManaLeft >= 145*tfMod and maxRankLHW >=2 and downRankFH >=2 then SpellID = SpellIDsLHW[2]; HealSize = 264*pMod+healModLHW end
            if healneed > ( 292*pMod*hwMod+healMod30*PF18)*K and ManaLeft >= 155*tfMod and maxRankHW >=4 and downRankNH >=4 and (TargetIsHealthy and maxRankLHW <= 2 and downRankFH <= 2 or NoLHW) then SpellID = SpellIDsHW[4]; HealSize = 292*pMod*hwMod+healMod30*PF18 end
            if healneed > (359*pMod+healModLHW)*k and ManaLeft >= 185*tfMod and maxRankLHW >=3 and downRankFH >=3 then SpellID = SpellIDsLHW[3]; HealSize = 359*pMod+healModLHW end
            if healneed > ( 408*pMod*hwMod+healMod30)*K and ManaLeft >= 200*tfMod and maxRankHW >=5 and downRankNH >=5 and healMod30 >=5 and (TargetIsHealthy and maxRankLHW <= 3 and downRankFH <= 3 or NoLHW)  then SpellID = SpellIDsHW[5]; HealSize = 408*pMod*hwMod+healMod30 end
            if healneed > (486*pMod+healModLHW)*k and ManaLeft >= 235*tfMod and maxRankLHW >=4 and downRankFH >=4 then SpellID = SpellIDsLHW[4]; HealSize = 486*pMod+healModLHW end
            if healneed > ( 579*pMod*hwMod+healMod30)*K and ManaLeft >= 265*tfMod and maxRankHW >=6 and downRankNH >=6 and healMod30 >=6 and (TargetIsHealthy and maxRankLHW <= 4 and downRankFH <= 4 or NoLHW) then SpellID = SpellIDsHW[6]; HealSize = 579*pMod*hwMod+healMod30 end
            if healneed > (668*pMod+healModLHW)*k and ManaLeft >= 305*tfMod and maxRankLHW >=5 and downRankFH >=5 then SpellID = SpellIDsLHW[5]; HealSize = 668*pMod+healModLHW end
            if healneed > ( 797*pMod*hwMod+healMod30)*K and ManaLeft >= 340*tfMod and maxRankHW >=7 and downRankNH >=7 and (TargetIsHealthy and maxRankLHW <= 5 and downRankFH <= 5 or NoLHW) then SpellID = SpellIDsHW[7]; HealSize = 797*pMod*hwMod+healMod30 end
            if healneed > (880*pMod+healModLHW)*k and ManaLeft >= 380*tfMod and maxRankLHW >=6 and downRankFH >=6 then SpellID = SpellIDsLHW[6]; HealSize = 880*pMod+healModLHW end
            if healneed > (1092*pMod*hwMod+healMod30)*K and ManaLeft >= 440*tfMod and maxRankHW >=8 and downRankNH >=8 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) then SpellID = SpellIDsHW[8]; HealSize = 1092*pMod*hwMod+healMod30 end
            if healneed > (1464*pMod*hwMod+healMod30)*K and ManaLeft >= 560*tfMod and maxRankHW >=9 and downRankNH >=9 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) then SpellID = SpellIDsHW[9]; HealSize = 1464*pMod*hwMod+healMod30 end
            if healneed > (1735*pMod*hwMod+healMod30)*K and ManaLeft >= 620*tfMod and maxRankHW >=10 and downRankNH >=10 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) then SpellID = SpellIDsHW[10]; HealSize = 1735*pMod*hwMod+healMod30 end
        end
    else
        -- Not in combat so use the closest available healing
        debug(string.format("Not in combat, will use closest available HW or LHW"))
        if Health < RatioFull then
            SpellID = SpellIDsHW[1]; HealSize = 39*pMod*hwMod+healMod15*PF1;
            if healneed > ( 71*pMod*hwMod+healMod20*PF6 ) and ManaLeft >= 45*tfMod and maxRankHW >=2 and downRankNH >=2 then SpellID = SpellIDsHW[2]; HealSize = 71*pMod*hwMod+healMod20*PF6 end
            if healneed > (142*pMod*hwMod+healMod25*PF12) and ManaLeft >= 80*tfMod and maxRankHW >=3 and downRankNH >=3 then SpellID = SpellIDsHW[3]; HealSize = 142*pMod*hwMod+healMod25*PF12 end
            if healneed > (174*pMod+healModLHW) and ManaLeft >= 105*tfMod and maxRankLHW >=1 and downRankFH >=1 then SpellID = SpellIDsLHW[1]; HealSize = 174*pMod+healModLHW end
            if healneed > (264*pMod+healModLHW) and ManaLeft >= 145*tfMod and maxRankLHW >=2 and downRankFH >=2 then SpellID = SpellIDsLHW[2]; HealSize = 264*pMod+healModLHW end
            if healneed > (292*pMod*hwMod+healMod30*PF18) and ManaLeft >= 155*tfMod and maxRankHW >=4 and downRankNH >=4 then SpellID = SpellIDsHW[4]; HealSize = 292*pMod*hwMod+healMod30*PF18 end
            if healneed > (359*pMod+healModLHW) and ManaLeft >= 185*tfMod and maxRankLHW >=3 and downRankFH >=3 then SpellID = SpellIDsLHW[3]; HealSize = 359*pMod+healModLHW end
            if healneed > (408*pMod*hwMod+healMod30) and ManaLeft >= 200*tfMod and maxRankHW >=5 and downRankNH >=5 then SpellID = SpellIDsHW[5]; HealSize = 408*pMod*hwMod+healMod30 end
            if healneed > (486*pMod+healModLHW) and ManaLeft >= 235*tfMod and maxRankLHW >=4 and downRankFH >=4 then SpellID = SpellIDsLHW[4]; HealSize = 486*pMod+healModLHW end
            if healneed > (579*pMod*hwMod+healMod30) and ManaLeft >= 265*tfMod and maxRankHW >=6 and downRankNH >=6 then SpellID = SpellIDsHW[6]; HealSize = 579*pMod*hwMod+healMod30 end
            if healneed > (668*pMod+healModLHW) and ManaLeft >= 305*tfMod and maxRankLHW >=5 and downRankFH >=5 then SpellID = SpellIDsLHW[5]; HealSize = 668*pMod+healModLHW end
            if healneed > (797*pMod*hwMod+healMod30) and ManaLeft >= 340*tfMod and maxRankHW >=7 and downRankNH >=7 then SpellID = SpellIDsHW[7]; HealSize = 797*pMod*hwMod+healMod30 end
            if healneed > (880*pMod+healModLHW) and ManaLeft >= 380*tfMod and maxRankLHW >=6 and downRankFH >=6 then SpellID = SpellIDsLHW[6]; HealSize = 880*pMod+healModLHW end
            if healneed > (1092*pMod*hwMod+healMod30) and ManaLeft >= 440*tfMod and maxRankHW >=8 and downRankNH >=8 then SpellID = SpellIDsHW[8]; HealSize = 1092*pMod*hwMod+healMod30 end
            if healneed > (1464*pMod*hwMod+healMod30) and ManaLeft >= 560*tfMod and maxRankHW >=9 and downRankNH >=9 then SpellID = SpellIDsHW[9]; HealSize = 1464*pMod*hwMod+healMod30 end
            if healneed > (1735*pMod*hwMod+healMod30) and ManaLeft >= 620*tfMod and maxRankHW >=10 and downRankNH >=10 then SpellID = SpellIDsHW[10]; HealSize = 1735*pMod*hwMod+healMod30 end
        end
    end

    return SpellID,HealSize*HDB;
end

function QuickHeal_Shaman_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF12 = 0.7;
    local PF18 = 0.925;

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

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

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
    local healModLHW = (1.5/3.5) * Bonus;
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,LHW)", healMod15,healMod20,healMod25,healMod30,healModLHW);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Purification Talent (increases healing by 2% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local pMod = 2*talentRank/100 + 1;
    debug(string.format("Purification modifier: %f", pMod))

    -- Tidal Focus - Decreases mana usage by 1% per rank on healing
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,2);
    local tfMod = 1 - talentRank/100;
    debug(string.format("Improved Healing modifier: %f", tfMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health)
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        InCombat = false;
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

    -- Detect healing way on target
    local hwMod = QuickHeal_DetectBuff(Target,"Spell_Nature_HealingWay");
    if hwMod then hwMod = 1+0.06*hwMod else hwMod = 1 end;
    debug("Healing Way healing modifier",hwMod);

    -- Get a list of ranks available of 'Lesser Healing Wave' and 'Healing Wave'
    local SpellIDsHW = GetSpellIDs(QUICKHEAL_SPELL_HEALING_WAVE);
    local SpellIDsLHW = GetSpellIDs(QUICKHEAL_SPELL_LESSER_HEALING_WAVE);
    local maxRankHW = table.getn(SpellIDsHW);
    local maxRankLHW = table.getn(SpellIDsLHW);
    local NoLHW = maxRankLHW < 1;
    debug(string.format("Found HW up to rank %d, and found LHW up to rank %d", maxRankHW, maxRankLHW))

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals

    if forceMaxHPS then
        local k = 0.9; -- In combat means that target is losing life while casting, so compensate
        local K = 0.8; -- k for fast spells (LHW and HW Rank 1 and 2) and K for slow spells (HW)
        if maxRankLHW >=1 then SpellID = SpellIDsLHW[1]; HealSize = 174*pMod+healModLHW else SpellID = SpellIDsHW[1]; HealSize = 39*pMod*hwMod+healMod15*PF1 end -- Default to HW or LHW
        --if healneed > (  71*pMod*hwMod+healMod20*PF6 )*k and ManaLeft >= 45*tfMod and maxRankHW >=2 and downRankNH >=2 and NoLHW then SpellID = SpellIDsHW[2]; HealSize =  71*pMod*hwMod+healMod20*PF6 end
        if healneed > (  71*pMod*hwMod+healMod20*PF6 )*k and ManaLeft >= 45*tfMod and maxRankHW >=2 and downRankNH >=2 then SpellID = SpellIDsHW[2]; HealSize =  71*pMod*hwMod+healMod20*PF6 end
        --if healneed > ( 142*pMod*hwMod+healMod25*PF12)*K and ManaLeft >= 80*tfMod and maxRankHW >=3 and downRankNH >=3 and NoLHW then SpellID = SpellIDsHW[3]; HealSize = 142*pMod*hwMod+healMod25*PF12 end
        if healneed > ( 142*pMod*hwMod+healMod25*PF12)*K and ManaLeft >= 80*tfMod and maxRankHW >=3 and downRankNH >=3 then SpellID = SpellIDsHW[3]; HealSize = 142*pMod*hwMod+healMod25*PF12 end
        if healneed > (174*pMod+healModLHW)*k and ManaLeft >= 105*tfMod and maxRankLHW >=1 and downRankFH >=1 then SpellID = SpellIDsLHW[1]; HealSize = 174*pMod+healModLHW end
        if healneed > (264*pMod+healModLHW)*k and ManaLeft >= 145*tfMod and maxRankLHW >=2 and downRankFH >=2 then SpellID = SpellIDsLHW[2]; HealSize = 264*pMod+healModLHW end
        if healneed > ( 292*pMod*hwMod+healMod30*PF18)*K and ManaLeft >= 155*tfMod and maxRankHW >=4 and downRankNH >=4 and (TargetIsHealthy and maxRankLHW <= 2 and downRankFH <= 2 or NoLHW) then SpellID = SpellIDsHW[4]; HealSize = 292*pMod*hwMod+healMod30*PF18 end
        if healneed > (359*pMod+healModLHW)*k and ManaLeft >= 185*tfMod and maxRankLHW >=3 and downRankFH >=3 then SpellID = SpellIDsLHW[3]; HealSize = 359*pMod+healModLHW end
        if healneed > ( 408*pMod*hwMod+healMod30)*K and ManaLeft >= 200*tfMod and maxRankHW >=5 and downRankNH >=5 and healMod30 >=5 and (TargetIsHealthy and maxRankLHW <= 3 and downRankFH <= 3 or NoLHW)  then SpellID = SpellIDsHW[5]; HealSize = 408*pMod*hwMod+healMod30 end
        if healneed > (486*pMod+healModLHW)*k and ManaLeft >= 235*tfMod and maxRankLHW >=4 and downRankFH >=4 then SpellID = SpellIDsLHW[4]; HealSize = 486*pMod+healModLHW end
        if healneed > ( 579*pMod*hwMod+healMod30)*K and ManaLeft >= 265*tfMod and maxRankHW >=6 and downRankNH >=6 and healMod30 >=6 and (TargetIsHealthy and maxRankLHW <= 4 and downRankFH <= 4 or NoLHW) then SpellID = SpellIDsHW[6]; HealSize = 579*pMod*hwMod+healMod30 end
        if healneed > (668*pMod+healModLHW)*k and ManaLeft >= 305*tfMod and maxRankLHW >=5 and downRankFH >=5 then SpellID = SpellIDsLHW[5]; HealSize = 668*pMod+healModLHW end
        if healneed > ( 797*pMod*hwMod+healMod30)*K and ManaLeft >= 340*tfMod and maxRankHW >=7 and downRankNH >=7 and (TargetIsHealthy and maxRankLHW <= 5 and downRankFH <= 5 or NoLHW) then SpellID = SpellIDsHW[7]; HealSize = 797*pMod*hwMod+healMod30 end
        if healneed > (880*pMod+healModLHW)*k and ManaLeft >= 380*tfMod and maxRankLHW >=6 and downRankFH >=6 then SpellID = SpellIDsLHW[6]; HealSize = 880*pMod+healModLHW end
        if healneed > (1092*pMod*hwMod+healMod30)*K and ManaLeft >= 440*tfMod and maxRankHW >=8 and downRankNH >=8 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) then SpellID = SpellIDsHW[8]; HealSize = 1092*pMod*hwMod+healMod30 end
        if healneed > (1464*pMod*hwMod+healMod30)*K and ManaLeft >= 560*tfMod and maxRankHW >=9 and downRankNH >=9 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) then SpellID = SpellIDsHW[9]; HealSize = 1464*pMod*hwMod+healMod30 end
        if healneed > (1735*pMod*hwMod+healMod30)*K and ManaLeft >= 620*tfMod and maxRankHW >=10 and downRankNH >=10 and (TargetIsHealthy and maxRankLHW <= 6 and downRankFH <= 6 or NoLHW) then SpellID = SpellIDsHW[10]; HealSize = 1735*pMod*hwMod+healMod30 end
    else
        SpellID = SpellIDsHW[1]; HealSize = 39*pMod*hwMod+healMod15*PF1;
        if healneed > ( 71*pMod*hwMod+healMod20*PF6 ) and ManaLeft >= 45*tfMod and maxRankHW >=2 and downRankNH >=2 then SpellID = SpellIDsHW[2]; HealSize = 71*pMod*hwMod+healMod20*PF6 end
        if healneed > (142*pMod*hwMod+healMod25*PF12) and ManaLeft >= 80*tfMod and maxRankHW >=3 and downRankNH >=3 then SpellID = SpellIDsHW[3]; HealSize = 142*pMod*hwMod+healMod25*PF12 end
        if healneed > (174*pMod+healModLHW) and ManaLeft >= 105*tfMod and maxRankLHW >=1 and downRankFH >=1 then SpellID = SpellIDsLHW[1]; HealSize = 174*pMod+healModLHW end
        if healneed > (264*pMod+healModLHW) and ManaLeft >= 145*tfMod and maxRankLHW >=2 and downRankFH >=2 then SpellID = SpellIDsLHW[2]; HealSize = 264*pMod+healModLHW end
        if healneed > (292*pMod*hwMod+healMod30*PF18) and ManaLeft >= 155*tfMod and maxRankHW >=4 and downRankNH >=4 then SpellID = SpellIDsHW[4]; HealSize = 292*pMod*hwMod+healMod30*PF18 end
        if healneed > (359*pMod+healModLHW) and ManaLeft >= 185*tfMod and maxRankLHW >=3 and downRankFH >=3 then SpellID = SpellIDsLHW[3]; HealSize = 359*pMod+healModLHW end
        if healneed > (408*pMod*hwMod+healMod30) and ManaLeft >= 200*tfMod and maxRankHW >=5 and downRankNH >=5 then SpellID = SpellIDsHW[5]; HealSize = 408*pMod*hwMod+healMod30 end
        if healneed > (486*pMod+healModLHW) and ManaLeft >= 235*tfMod and maxRankLHW >=4 and downRankFH >=4 then SpellID = SpellIDsLHW[4]; HealSize = 486*pMod+healModLHW end
        if healneed > (579*pMod*hwMod+healMod30) and ManaLeft >= 265*tfMod and maxRankHW >=6 and downRankNH >=6 then SpellID = SpellIDsHW[6]; HealSize = 579*pMod*hwMod+healMod30 end
        if healneed > (668*pMod+healModLHW) and ManaLeft >= 305*tfMod and maxRankLHW >=5 and downRankFH >=5 then SpellID = SpellIDsLHW[5]; HealSize = 668*pMod+healModLHW end
        if healneed > (797*pMod*hwMod+healMod30) and ManaLeft >= 340*tfMod and maxRankHW >=7 and downRankNH >=7 then SpellID = SpellIDsHW[7]; HealSize = 797*pMod*hwMod+healMod30 end
        if healneed > (880*pMod+healModLHW) and ManaLeft >= 380*tfMod and maxRankLHW >=6 and downRankFH >=6 then SpellID = SpellIDsLHW[6]; HealSize = 880*pMod+healModLHW end
        if healneed > (1092*pMod*hwMod+healMod30) and ManaLeft >= 440*tfMod and maxRankHW >=8 and downRankNH >=8 then SpellID = SpellIDsHW[8]; HealSize = 1092*pMod*hwMod+healMod30 end
        if healneed > (1464*pMod*hwMod+healMod30) and ManaLeft >= 560*tfMod and maxRankHW >=9 and downRankNH >=9 then SpellID = SpellIDsHW[9]; HealSize = 1464*pMod*hwMod+healMod30 end
        if healneed > (1735*pMod*hwMod+healMod30) and ManaLeft >= 620*tfMod and maxRankHW >=10 and downRankNH >=10 then SpellID = SpellIDsHW[10]; HealSize = 1735*pMod*hwMod+healMod30 end
    end

    return SpellID,HealSize*hdb;
end

function QuickHeal_Command_Shaman(msg)

    --if PlayerClass == "priest" then
    --  writeLine("SHAMAN", 0, 1, 0);
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
            if arg2 == "chainheal" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank & no hp check)", 0, 1, 0);
                QuickChainHeal(arg1, nil, nil, true, true);
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
        if arg4 == "chainheal" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HOT (max)", 0, 1, 0);
            QuickChainHeal(nil, nil, nil, true, false);
            return;
        end
        if arg4 == "heal" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HEAL (max)", 0, 1, 0);
            QuickHeal(nil, nil, nil, true);
            return;
        end

        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "chainheal" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL", 0, 1, 0);
                QuickChainHeal(arg1, nil, nil, false);
                return;
            end
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

    if cmd == "chainheal" then
        --writeLine(QuickHealData.name .. " CHAINHEAL", 0, 1, 0);
        QuickChainHeal();
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
    writeLine("== QUICKHEAL USAGE : SHAMAN ==");
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

    writeLine(" [type] specifies the use of a [chainheal] or [heal]");
    writeLine(" [mod] (optional) modifies [chainheal] or [heal] options:");
    writeLine("  [chainheal] modifier options:");
    writeLine("   [max] applies maximum rank [chainheal] to subgroup members that have <100% health");
    writeLine("  [heal] modifier options:");
    writeLine("   [max] applies maximum rank [heal] to subgroup members that have <100% health");

    writeLine("/qh reset - Reset configuration to default parameters for all classes.");
end