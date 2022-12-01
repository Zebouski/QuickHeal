local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

function QuickHeal_Druid_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_REGROWTH .. " will always be used in combat, and "  .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will be used when out of combat. ";
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_REGROWTH .. " will be used in combat if the target has less than " .. RatioHealthy*100 .. "% life, and " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will be used otherwise. ";
        else
            return QUICKHEAL_SPELL_REGROWTH .. " will never be used. " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " will always be used in and out of combat. ";
        end
    end
end

function QuickHeal_Druid_FindHealSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
    local ForceHTinCombat = false;
    local NaturesGrace = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediately if no player needs healing
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

    -- Determine health and heal need of target
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
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,12); 
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9); 
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14); 
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));
   
    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    --local _,_,_,_,talentRank,_ = GetTalentInfo(3,10); 
    --local irMod = 5*talentRank/100 + 1;
    --debug(string.format("Improved Rejuvenation modifier: %f", irMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end
    
    -- Detect Clearcasting (from Omen of Clarity, talent(1,9))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -------------------------------------------

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub, Madness event)
    if QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect Nature's Grace (next nature spell is hasted by 0.5 seconds)
    --if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") and healneed < ((219*gnMod+healMod25*PF14)*2.8) and
    --        not QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
    --    ManaLeft = 110*tsMod*mgMod;
    --end

    if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") then
        NaturesGrace = true;
    end

    -------------------------------------------

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    --local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    --local maxRankRJ = table.getn(SpellIDsRJ);
    
    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG));

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    local level = UnitLevel('player');

    --hardwire InCombat to true for testing
    --InCombat = true;

    if level < 60 then
        -- < LEVEL 60 STUFFS
        --print('f:QuickHeal_Druid_FindHealSpellToUse --you are not 60');
        -- Find suitable SpellID based on the defined criteria
        if not InCombat or TargetIsHealthy or maxRankRG<1 then
            -- Not in combat or target is healthy so use the closest available mana efficient healing
            debug(string.format("Not in combat or target healthy or no Regrowth available, will use Healing Touch"))
            if Health < RatioFull then
                SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
                if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
                if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
                if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
                if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
                if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
                if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
                if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
                if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
                if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
                if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
            end
        elseif ForceHTinCombat then
            SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
            if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
            if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
            if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
            if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
            if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
            if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
            if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
            if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
            if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
            if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
        else
            -- In combat and target is unhealthy and player has Regrowth
            debug(string.format("In combat and target unhealthy and Regrowth available, will use Regrowth"));
            if Health < RatioFull then
                SpellID = SpellIDsRG[1]; HealSize = 91*gnMod+healModRG*PFRG1; -- Default to rank 1
                if healneed > ( 176*gnMod+healModRG*PFRG2)*k and ManaLeft >= 205*mgMod and maxRankRG >= 2 then SpellID = SpellIDsRG[2]; HealSize =  176*gnMod+healModRG*PFRG2 end
                if healneed > ( 257*gnMod+healModRG)*k and ManaLeft >= 280*mgMod and maxRankRG >= 3 then SpellID = SpellIDsRG[3]; HealSize =  257*gnMod+healModRG end
                if healneed > ( 339*gnMod+healModRG)*k and ManaLeft >= 350*mgMod and maxRankRG >= 4 then SpellID = SpellIDsRG[4]; HealSize =  339*gnMod+healModRG end
                if healneed > ( 431*gnMod+healModRG)*k and ManaLeft >= 420*mgMod and maxRankRG >= 5 then SpellID = SpellIDsRG[5]; HealSize =  431*gnMod+healModRG end
                if healneed > ( 543*gnMod+healModRG)*k and ManaLeft >= 510*mgMod and maxRankRG >= 6 then SpellID = SpellIDsRG[6]; HealSize =  543*gnMod+healModRG end
                if healneed > ( 686*gnMod+healModRG)*k and ManaLeft >= 615*mgMod and maxRankRG >= 7 then SpellID = SpellIDsRG[7]; HealSize =  686*gnMod+healModRG end
                if healneed > ( 857*gnMod+healModRG)*k and ManaLeft >= 740*mgMod and maxRankRG >= 8 then SpellID = SpellIDsRG[8]; HealSize =  857*gnMod+healModRG end
                if healneed > (1061*gnMod+healModRG)*k and ManaLeft >= 880*mgMod and maxRankRG >= 9 then SpellID = SpellIDsRG[9]; HealSize = 1061*gnMod+healModRG end
            end
        end
    else
        -- > LEVEL 60 STUFFS
        --print('f:QuickHeal_Druid_FindHealSpellToUse --you ARE 60');
        -- Find suitable SpellID based on the defined criteria
        if not InCombat then
            --print('f:QuickHeal_Druid_FindHealSpellToUse --NOT InCombat');
            -- Not in combat or target is healthy so use the closest available mana efficient healing
            debug(string.format("Not in combat or target healthy or no Regrowth available, will use Healing Touch"))
            if Health < RatioFull then
                SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
                if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
                if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
                if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
                if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
                if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
                if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
                if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
                if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
                if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
                if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
            end
        else
            if not TargetIsHealthy then -- QH toggle is set to true (High HPS)
                --print('f:QuickHeal_Druid_FindHealSpellToUse -- InCombat, High HPS');
                if Health < RatioFull then
                    local heel = healneed/2; --healneed*3/8
                    SpellID = SpellIDsRG[1]; HealSize = 91*gnMod+healModRG*PFRG1; -- Default to rank 1
                    if heel > ( 176*gnMod+healModRG*PFRG2)*k and ManaLeft >= 205*mgMod and maxRankRG >= 2 and downRankFH >= 2 then SpellID = SpellIDsRG[2]; HealSize =  176*gnMod+healModRG*PFRG2 end
                    if heel > ( 257*gnMod+healModRG)*k and ManaLeft >= 280*mgMod and maxRankRG >= 3 and downRankFH >= 3 then SpellID = SpellIDsRG[3]; HealSize =  257*gnMod+healModRG end
                    if heel > ( 339*gnMod+healModRG)*k and ManaLeft >= 350*mgMod and maxRankRG >= 4 and downRankFH >= 4 then SpellID = SpellIDsRG[4]; HealSize =  339*gnMod+healModRG end
                    if heel > ( 431*gnMod+healModRG)*k and ManaLeft >= 420*mgMod and maxRankRG >= 5 and downRankFH >= 5 then SpellID = SpellIDsRG[5]; HealSize =  431*gnMod+healModRG end
                    if heel > ( 543*gnMod+healModRG)*k and ManaLeft >= 510*mgMod and maxRankRG >= 6 and downRankFH >= 6 then SpellID = SpellIDsRG[6]; HealSize =  543*gnMod+healModRG end
                    if heel > ( 686*gnMod+healModRG)*k and ManaLeft >= 615*mgMod and maxRankRG >= 7 and downRankFH >= 7 then SpellID = SpellIDsRG[7]; HealSize =  686*gnMod+healModRG end
                    if heel > ( 857*gnMod+healModRG)*k and ManaLeft >= 740*mgMod and maxRankRG >= 8 and downRankFH >= 8 then SpellID = SpellIDsRG[8]; HealSize =  857*gnMod+healModRG end
                    if heel > (1061*gnMod+healModRG)*k and ManaLeft >= 880*mgMod and maxRankRG >= 9 and downRankFH >= 9 then SpellID = SpellIDsRG[9]; HealSize = 1061*gnMod+healModRG end
                end
            else -- QH toggle is set to false (Normal HPS)
                --print('f:QuickHeal_Druid_FindHealSpellToUse -- InCombat, Normal HPS');
                if Health < RatioFull then

                    -- if Nature's Grace has procced, cast HT4
                    if NaturesGrace then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30; return SpellID,HealSize*HDB; end

                    SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
                    --if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 and downRankNH >= 2 then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
                    if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 and downRankNH >= 3 then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
                    if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 and downRankNH >= 4 then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
                    --if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 and downRankNH >= 5 then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
                    --if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 and downRankNH >= 6 then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
                    --if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 and downRankNH >= 7 then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
                    --if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 and downRankNH >= 8 then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
                    --if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 and downRankNH >= 9 then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
                    --if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 and downRankNH >= 10 then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
                    --if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 and downRankNH >= 11 then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
                end
            end
        end
    end



    
    return SpellID,HealSize*HDB;
end

function QuickHeal_Druid_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
    local ForceHTinCombat = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

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
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,12);
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    --local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    --local irMod = 5*talentRank/100 + 1;
    --debug(string.format("Improved Rejuvenation modifier: %f", irMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

    -- Detect Clearcasting (from Omen of Clarity, talent(1,9))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -------------------------------------------

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub, Madness event)
    if QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect Nature's Grace (next nature spell is hasted by 0.5 seconds)
    if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") and healneed < ((219*gnMod+healMod25*PF14)*2.8) and
            not QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        ManaLeft = 110*tsMod*mgMod;
    end

    -------------------------------------------

    ---- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    --local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    --local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    --if UnitLevel('player') < 60 then
    --    print('f:QuickHeal_Druid_FindHealSpellToUseNoTarget --you are not 60');
    --else
    --    print('f:QuickHeal_Druid_FindHealSpellToUseNoTarget --you are 60');
    --end

    if not forceMaxHPS then
        SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
        if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
        if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
        if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
        if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
        if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
        if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
        if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
        if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
        if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
        if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
    else
        SpellID = SpellIDsRG[1]; HealSize = 91*gnMod+healModRG*PFRG1; -- Default to rank 1
        if healneed > ( 176*gnMod+healModRG*PFRG2)*k and ManaLeft >= 205*mgMod and maxRankRG >= 2 then SpellID = SpellIDsRG[2]; HealSize =  176*gnMod+healModRG*PFRG2 end
        if healneed > ( 257*gnMod+healModRG)*k and ManaLeft >= 280*mgMod and maxRankRG >= 3 then SpellID = SpellIDsRG[3]; HealSize =  257*gnMod+healModRG end
        if healneed > ( 339*gnMod+healModRG)*k and ManaLeft >= 350*mgMod and maxRankRG >= 4 then SpellID = SpellIDsRG[4]; HealSize =  339*gnMod+healModRG end
        if healneed > ( 431*gnMod+healModRG)*k and ManaLeft >= 420*mgMod and maxRankRG >= 5 then SpellID = SpellIDsRG[5]; HealSize =  431*gnMod+healModRG end
        if healneed > ( 543*gnMod+healModRG)*k and ManaLeft >= 510*mgMod and maxRankRG >= 6 then SpellID = SpellIDsRG[6]; HealSize =  543*gnMod+healModRG end
        if healneed > ( 686*gnMod+healModRG)*k and ManaLeft >= 615*mgMod and maxRankRG >= 7 then SpellID = SpellIDsRG[7]; HealSize =  686*gnMod+healModRG end
        if healneed > ( 857*gnMod+healModRG)*k and ManaLeft >= 740*mgMod and maxRankRG >= 8 then SpellID = SpellIDsRG[8]; HealSize =  857*gnMod+healModRG end
        if healneed > (1061*gnMod+healModRG)*k and ManaLeft >= 880*mgMod and maxRankRG >= 9 then SpellID = SpellIDsRG[9]; HealSize = 1061*gnMod+healModRG end
    end

    return SpellID,HealSize*hdb;
end

function QuickHeal_Druid_FindHoTSpellToUse(Target, healType, forceMaxRank)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediately if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    -- Determine health and heal need of target
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
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,12);
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    local irMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Rejuvenation modifier: %f", irMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

    -- Detect Clearcasting (from Omen of Clarity, talent(1,9))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
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

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d, RJ up to rank %d", maxRankHT, maxRankRG, maxRankRJ));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    QuickHeal_debug(string.format("healneed: %f  target: %s  healType: %s  forceMaxRank: %s", healneed, Target, healType, tostring(forceMaxRank)));

    --return SpellIDsRJ[1], 32*irMod+gnMod+healMod15;

    --if UnitLevel('player') < 60 then
    --    print('f:QuickHeal_Druid_FindHoTSpellToUse --you are not 60');
    --else
    --    print('f:QuickHeal_Druid_FindHoTSpellToUse --you are 60');
    --end

    if healType == "hot" then
        --QuickHeal_debug(string.format("Spiritual Healing modifier: %f", shMod));
        --SpellID = SpellIDsR[1]; HealSize = 215*shMod+healMod15; -- Default to Renew

        --if Health < QuickHealVariables.RatioFull then
        --if Health > QuickHealVariables.RatioHealthyPriest then
        if not forceMaxRank then
            SpellID = SpellIDsRJ[1]; HealSize = 32*irMod+gnMod+healMod15; -- Default to Renew(Rank 1)
            if healneed > (56*irMod+gnMod+healMod15)*k and ManaLeft >= 155 and maxRankRJ >=2 then SpellID = SpellIDsRJ[2]; HealSize = 56*irMod+gnMod+healMod15 end
            if healneed > (116*irMod+gnMod+healMod15)*k and ManaLeft >= 185 and maxRankRJ >=3 then SpellID = SpellIDsRJ[3]; HealSize = 116*irMod+gnMod+healMod15 end
            if healneed > (180*irMod+gnMod+healMod15)*k and ManaLeft >= 215 and maxRankRJ >=4 then SpellID = SpellIDsRJ[4]; HealSize = 180*irMod+gnMod+healMod15 end
            if healneed > (244*irMod+gnMod+healMod15)*k and ManaLeft >= 265 and maxRankRJ >=5 then SpellID = SpellIDsRJ[5]; HealSize = 244*irMod+gnMod+healMod15 end
            if healneed > (304*irMod+gnMod+healMod15)*k and ManaLeft >= 315 and maxRankRJ >=6 then SpellID = SpellIDsRJ[6]; HealSize = 304*irMod+gnMod+healMod15 end
            if healneed > (388*irMod+gnMod+healMod15)*k and ManaLeft >= 380 and maxRankRJ >=7 then SpellID = SpellIDsRJ[7]; HealSize = 388*irMod+gnMod+healMod15 end
            if healneed > (488*irMod+gnMod+healMod15)*k and ManaLeft >= 455 and maxRankRJ >=8 then SpellID = SpellIDsRJ[8]; HealSize = 488*irMod+gnMod+healMod15 end
            if healneed > (688*irMod+gnMod+healMod15)*k and ManaLeft >= 545 and maxRankRJ >=9 then SpellID = SpellIDsRJ[9]; HealSize = 608*irMod+gnMod+healMod15 end
            if healneed > (756*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=10 then SpellID = SpellIDsRJ[10]; HealSize = 756*irMod+gnMod+healMod15 end
            if healneed > (888*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=11 then SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+gnMod+healMod15 end
        else
            SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+gnMod+healMod15
            if maxRankRJ >=2 then SpellID = SpellIDsRJ[2]; HealSize = 56*irMod+healMod15 end
            if maxRankRJ >=3 then SpellID = SpellIDsRJ[3]; HealSize = 116*irMod+healMod15 end
            if maxRankRJ >=4 then SpellID = SpellIDsRJ[4]; HealSize = 180*irMod+healMod15 end
            if maxRankRJ >=5 then SpellID = SpellIDsRJ[5]; HealSize = 244*irMod+healMod15 end
            if maxRankRJ >=6 then SpellID = SpellIDsRJ[6]; HealSize = 304*irMod+healMod15 end
            if maxRankRJ >=7 then SpellID = SpellIDsRJ[7]; HealSize = 388*irMod+healMod15 end
            if maxRankRJ >=8 then SpellID = SpellIDsRJ[8]; HealSize = 488*irMod+healMod15 end
            if maxRankRJ >=9 then SpellID = SpellIDsRJ[9]; HealSize = 688*irMod+healMod15 end
            if maxRankRJ >=10 then SpellID = SpellIDsRJ[10]; HealSize = 756*irMod+healMod15 end
            if maxRankRJ >=11 then SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+healMod15 end
        end
        --end
    end

    return SpellID,HealSize*HDB;
end

function QuickHeal_Druid_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

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
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,12);
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    local irMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Rejuvenation modifier: %f", irMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

    -- Detect Clearcasting (from Omen of Clarity, talent(1,9))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
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
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d, RJ up to rank %d", maxRankHT, maxRankRG, maxRankRJ));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    --QuickHeal_debug(string.format("healneed: %f  target: %s  healType: %s  forceMaxRank: %s", healneed, Target, healType, tostring(forceMaxRank)));

    --return SpellIDsRJ[1], 32*irMod+gnMod+healMod15;

    --if UnitLevel('player') < 60 then
    --    print('f:QuickHeal_Druid_FindHoTSpellToUseNoTarget --you are not 60');
    --else
    --    print('f:QuickHeal_Druid_FindHoTSpellToUseNoTarget --you are 60');
    --end

    SpellID = SpellIDsRJ[1]; HealSize = 32*irMod+gnMod+healMod15; -- Default to Renew(Rank 1)
    if healneed > (56*irMod+gnMod+healMod15)*k and ManaLeft >= 155 and maxRankRJ >=2 then SpellID = SpellIDsRJ[2]; HealSize = 56*irMod+gnMod+healMod15 end
    if healneed > (116*irMod+gnMod+healMod15)*k and ManaLeft >= 185 and maxRankRJ >=3 then SpellID = SpellIDsRJ[3]; HealSize = 116*irMod+gnMod+healMod15 end
    if healneed > (180*irMod+gnMod+healMod15)*k and ManaLeft >= 215 and maxRankRJ >=4 then SpellID = SpellIDsRJ[4]; HealSize = 180*irMod+gnMod+healMod15 end
    if healneed > (244*irMod+gnMod+healMod15)*k and ManaLeft >= 265 and maxRankRJ >=5 then SpellID = SpellIDsRJ[5]; HealSize = 244*irMod+gnMod+healMod15 end
    if healneed > (304*irMod+gnMod+healMod15)*k and ManaLeft >= 315 and maxRankRJ >=6 then SpellID = SpellIDsRJ[6]; HealSize = 304*irMod+gnMod+healMod15 end
    if healneed > (388*irMod+gnMod+healMod15)*k and ManaLeft >= 380 and maxRankRJ >=7 then SpellID = SpellIDsRJ[7]; HealSize = 388*irMod+gnMod+healMod15 end
    if healneed > (488*irMod+gnMod+healMod15)*k and ManaLeft >= 455 and maxRankRJ >=8 then SpellID = SpellIDsRJ[8]; HealSize = 488*irMod+gnMod+healMod15 end
    if healneed > (688*irMod+gnMod+healMod15)*k and ManaLeft >= 545 and maxRankRJ >=9 then SpellID = SpellIDsRJ[9]; HealSize = 608*irMod+gnMod+healMod15 end
    if healneed > (756*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=10 then SpellID = SpellIDsRJ[10]; HealSize = 756*irMod+gnMod+healMod15 end
    if healneed > (888*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=11 then SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+gnMod+healMod15 end


    return SpellID,HealSize*hdb;
end

function QuickHeal_Command_Druid(msg)

    --if PlayerClass == "priest" then
    --  writeLine("DRUID", 0, 1, 0);
    --end

    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- match 3 arguments
    if arg1 ~= nil and arg2 ~= nil and arg3 ~= nil then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL(maxHPS)", 0, 1, 0);
                QuickHeal(arg1, nil, nil, true);
                return;
            end
            if arg2 == "hot" and arg3 == "fh" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank & no hp check)", 0, 1, 0);
                QuickHOT(arg1, nil, nil, true, true);
                return;
            end
            if arg2 == "hot" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank)", 0, 1, 0);
                QuickHOT(arg1, nil, nil, true, false);
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
        if arg4 == "hot" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HOT (max)", 0, 1, 0);
            QuickHOT(nil, nil, nil, true, false);
            return;
        end
        if arg4 == "hot" and arg5 == "fh" then
            --writeLine(QuickHealData.name .. " FH (max rank & no hp check)", 0, 1, 0);
            QuickHOT(nil, nil, nil, true, true);
            return;
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "hot" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT", 0, 1, 0);
                QuickHOT(arg1, nil, nil, false, false);
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

    if cmd == "heal" then
        --writeLine(QuickHealData.name .. " HEAL", 0, 1, 0);
        QuickHeal();
        return;
    end

    if cmd == "hot" then
        --writeLine(QuickHealData.name .. " HOT", 0, 1, 0);
        QuickHOT();
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
    writeLine("== QUICKHEAL USAGE : DRUID ==");
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

    writeLine(" [type] specifies the use of a [hot] or [heal]");
    writeLine(" [mod] (optional) modifies [hot] or [heal] options:");
    writeLine("  [heal] modifier options:");
    writeLine("   [max] applies maximum rank [heal] to subgroup members that have <100% health");
    writeLine("  [hot] modifier options:");
    writeLine("   [max] applies maximum rank [hot] to subgroup members that have <100% health and no hot applied");
    writeLine("   [fh] applies maximum rank [hot] to subgroup members that have no hot applied regardless of health status");

    writeLine("/qh reset - Reset configuration to default parameters for all classes.");
end