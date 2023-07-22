if !file.Exists( "weapons/weapon_lightsaber.lua", "LUA" ) then return end

local table_Random = table.Random
local list_Get = list.Get
local random = math.random
local Rand = math.Rand
local Clamp = math.Clamp
local ceil = math.ceil
local min = math.min
local ipairs = ipairs
local CurTime = CurTime
local string_match = string.match
local math_Approach = math.Approach
local FrameTime = FrameTime
local isnumber = isnumber
local CreateSound = CreateSound
local SimpleTimer = timer.Simple
local EffectData = EffectData
local DamageInfo = DamageInfo
local util_Effect = util.Effect
local TraceLine = util.TraceLine
local TraceHull = util.TraceHull
local ents_GetAll = ents.GetAll
local string_StartWith = string.StartWith
local string_find = string.find
local Entity = Entity
local IsValidRagdoll = util.IsValidRagdoll
local FindInSphere = ents.FindInSphere
local SortedPairsByValue = SortedPairsByValue
local targetTrTbl = {}
local bladeTrTbl = { filter = {} }
local forceTrTbl = { 
    filter = {},
    mins = Vector( -16, -16, 0 ),
    maxs = Vector( 16, 16, 72 )
}
local lsModels

local function GetSaberPosAng( self, wepent, num, side )
    local attachment = wepent:LookupAttachment( ( side and "quillon" or "blade" ) .. ( num or 1 ) )
    if attachment and attachment > 0 then
        local PosAng = wepent:GetAttachment( attachment )
        if !self:LookupBone( "ValveBiped.Bip01_R_Hand" ) then
            PosAng.Pos = ( PosAng.Pos + vector_up * ( self:Crouching() and 18 or 36 ) )
            PosAng.Ang.p = 0
        end
        return PosAng.Pos, PosAng.Ang:Forward()
    end

    local bone = self:LookupBone( "ValveBiped.Bip01_R_Hand" )
    if bone then
        local PosAng = self:GetBoneTransformation( bone )

        local ang = PosAng.Ang
        ang:RotateAroundAxis( ang:Forward(), 180 )
        ang:RotateAroundAxis( ang:Up(), 30 )
        ang:RotateAroundAxis( ang:Forward(), -5.7 )
        ang:RotateAroundAxis( ang:Right(), 92 )

        local pos = ( PosAng.Pos + ang:Up() * -3.3 + ang:Right() * 0.8 + ang:Forward() * 5.6 )
        return pos, ang:Forward()
    end

    local defAng = wepent:GetAngles()
    defAng.p = 0

    local defPos = ( wepent:GetPos() + defAng:Right() * 0.6 - defAng:Up() * 0.2 + defAng:Forward() * 0.8 + vector_up * 18 )
    return defPos, -defAng:Forward()
end

local function SelectTargets( self, wepent, num )
    local eyeAttach = self:GetAttachmentPoint( "eyes" )
    local pos1 = ( eyeAttach.Pos + eyeAttach.Ang:Forward() * 512 )

    targetTrTbl.start = eyeAttach.Pos
    targetTrTbl.filter = self

    local foundEnts = {}
    for _, ent in ipairs( ents_GetAll() ) do
        if ent == self or ent == wepent or !IsValid( ent ) or ent:Health() < 1 or ( ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot() ) and !self:CanTarget( ent ) then continue end

        local mdl = ent:GetModel()
        if !mdl or mdl == "" or string_StartWith( mdl, "models/gibs/" ) or string_find( mdl, "chunk" ) or string_find( mdl, "_shard" ) or string_find( mdl, "_splinters" ) then continue end

        targetTrTbl.endpos = ( ent.EyePos && ent:EyePos() or ent:GetPos() )
        local targetTr = TraceLine( targetTrTbl )
        if targetTr.Fraction != 1.0 and targetTr.Entity != ent then continue end

        local pos2 = ent:GetPos()
        if pos1:Distance( pos2 ) > 512 then continue end
        
        foundEnts[ ent ] = targetTr.HitPos:Distance( pos2 )
    end

    if num == 1 then for ent, _ in SortedPairsByValue( foundEnts ) do return ent end end
    local targets = {}

    for ent, _ in SortedPairsByValue( foundEnts ) do
        targets[ #targets + 1 ] = ent
        if #targets >= num then break end
    end

    return targets
end

local ForcePowers = {
    [ "Force Leap" ] = {
        Cost = 10,
        Cooldown = 0.5,
        ConVar = CreateLambdaConvar( "lambdaplayers_weapons_lightsaber_allowleap", 1, true, false, false, "If Lambda Players with lightsaber are allowed to use the Force Leap power.", 0, 1, { type = "Bool", name = "Lightsaber - Allow Force Leap", category = "Weapon Utilities" } ),
        Action = function( self, wepent, target )
            if !self:IsOnGround() or !IsValid( target ) then return false end
            local selfPos = self:GetPos()
            local jumpVel = ( vector_up * 512 + ( target:GetPos() - selfPos ):GetNormalized() * 512 )            

            forceTrTbl.start = selfPos
            forceTrTbl.endpos = ( selfPos + ( jumpVel / 2 ) )
            forceTrTbl.filter[ 1 ] = self
            forceTrTbl.filter[ 2 ] = wepent
            forceTrTbl.filter[ 3 ] = target
            if TraceHull( forceTrTbl ).Hit or !self:LambdaJump( true ) then return false end

            wepent:EmitSound( "lightsaber/force_leap.wav", nil, nil, 1 )
            self.loco:SetVelocity( jumpVel )
        end
    },
    [ "Force Absorb" ] = {
        Cost = 0.1,
        Cooldown = 0.3,
        ConVar = CreateLambdaConvar( "lambdaplayers_weapons_lightsaber_allowabsorb", 1, true, false, false, "If Lambda Players with lightsaber are allowed to use the Force Absorb power.", 0, 1, { type = "Bool", name = "Lightsaber - Allow Force Absorb", category = "Weapon Utilities" } ),
        Action = function( self )
            self.LS_DmgAbsorbTime = ( CurTime() + 0.1 )
        end,
    },
    [ "Force Heal" ] = {
        Cost = 1,
        Cooldown = 0.2,
        ConVar = CreateLambdaConvar( "lambdaplayers_weapons_lightsaber_allowheal", 1, true, false, false, "If Lambda Players with lightsaber are allowed to use the Force Heal power.", 0, 1, { type = "Bool", name = "Lightsaber - Allow Force Heal", category = "Weapon Utilities" } ),
        Action = function( self )
            local hp = self:Health()
            if hp >= self:GetMaxHealth() then return false end

            local effectData = EffectData()
            effectData:SetOrigin( self:GetPos() )
            util_Effect( "rb655_force_heal", effectData, true, true )

            self:SetHealth( hp + 1 )
            self:Extinguish()
        end
    },
    [ "Force Combust" ] = {
        ConVar = CreateLambdaConvar( "lambdaplayers_weapons_lightsaber_allowcombust", 1, true, false, false, "If Lambda Players with lightsaber are allowed to use the Force Combust power.", 0, 1, { type = "Bool", name = "Lightsaber - Allow Force Combust", category = "Weapon Utilities" } ),
        Action = function( self, wepent )
            local ent = SelectTargets( self, wepent, 1 )
            if !IsValid( ent ) or ent:IsOnFire() then return 0.2 end

            local time = Clamp( 512 / self:GetRangeTo( ent ), 1, 16 )
            local neededForce = ceil( Clamp( time * 2, 10, 32 ) )
            if self.LS_Force < neededForce then return 0.2 end

            ent:Ignite( time, 0 )
            return 1, neededForce
        end
    },
    [ "Force Lightning" ] = {
        Cost = 3,
        ConVar = CreateLambdaConvar( "lambdaplayers_weapons_lightsaber_allowlightning", 1, true, false, false, "If Lambda Players with lightsaber are allowed to use the Force Lightning power.", 0, 1, { type = "Bool", name = "Lightsaber - Allow Force Lightning", category = "Weapon Utilities" } ),
        Action = function( self, wepent )
            local foundents = 0
            for _, ent in ipairs( SelectTargets( self, wepent, 3 ) ) do
                foundents = ( foundents + 1 )

                local effectData = EffectData()
                effectData:SetOrigin( GetSaberPosAng( self, wepent ) )
                effectData:SetEntity( ent )
                util_Effect( "rb655_force_lighting", effectData, true, true )

                local dmginfo = DamageInfo()
                dmginfo:SetAttacker( self )
                dmginfo:SetInflictor( self )
                if ent:IsNPC() then 
                    dmginfo:SetDamage( 4 ) 
                else
                    dmginfo:SetDamage( Clamp( 512 / self:GetRangeTo( ent ), 1, 10 ) )
                end
                ent:TakeDamageInfo( dmginfo )
            end

            if foundents > 0 then
                local lightSnd = wepent.LS_SoundLightning
                if !lightSnd then
                    lightSnd = CreateSound( wepent, "lightsaber/force_lightning" .. random( 2 ) .. ".wav" )
                    wepent.LS_SoundLightning = lightSnd
                end
                lightSnd:Play()

                SimpleTimer( 0.2, function() 
                    if !wepent.LS_SoundLightning then return end 
                    wepent.LS_SoundLightning:Stop() 
                    wepent.LS_SoundLightning = nil 
                end )
            end

            return 0.2, foundEnts
        end
    },
    [ "Force Repulse" ] = {
        ConVar = CreateLambdaConvar( "lambdaplayers_weapons_lightsaber_allowrepulse", 1, true, false, false, "If Lambda Players with lightsaber are allowed to use the Force Repulse power.", 0, 1, { type = "Bool", name = "Lightsaber - Allow Force Repulse", category = "Weapon Utilities" } ),
        Action = function( self, wepent )
            if !self.LS_ForceRepulse then
                if self.LS_Force < 16 then return false end
                self.LS_ForceRepulse = 1
                self.LS_Force = ( self.LS_Force - 16 )
            end
            
            if CurTime() >= self.LS_NextForceEffect then
                local effectData = EffectData()
                effectData:SetOrigin( self:GetPos() + vector_up * 36 )
                effectData:SetRadius( 128 * self.LS_ForceRepulse )
                util_Effect( "rb655_force_repulse_in", effectData, true, true )

                self.LS_NextForceEffect = ( CurTime() + Clamp( self.LS_ForceRepulse / 20, 0.1, 0.5 ) )
            end

            self.LS_ForceRepulse = ( self.LS_ForceRepulse + 0.025 )
            self.LS_Force = ( self.LS_Force - 0.5 )
            return false
        end
    }
}

table.Merge( _LAMBDAPLAYERSWEAPONS, {
    sw_lightsaber = {
        model = "models/sgg/starwars/weapons/w_anakin_ep2_saber_hilt.mdl",
        bonemerge = true,
        
        origin = "Misc",
        prettyname = "Lightsaber",
        killicon = "weapon_lightsaber",
        holdtype = "melee2",
            
        islethal = true,
        ismelee = true,
        keepdistance = 10,
        attackrange = 50,

        OnEquip = function( self, wepent )
            wepent.Owner = self

            local lsMdl = self.LS_WorldModel
            if !lsMdl then
                lsModels = ( lsModels or list_Get( "LightsaberModels" ) )
                local _, rndMdl = table_Random( lsModels )

                lsMdl = ( rndMdl or wepent:GetModel() )
                self:SetExternalVar( "LS_WorldModel", lsMdl )
            end
            wepent:SetModel( lsMdl )

            local holdType = "melee2"
            wepent.l_AttackAnimation = ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE2
            if lsMdl == "models/weapons/starwars/w_maul_saber_staff_hilt.mdl" or wepent:LookupAttachment( "blade2" ) > 0 then
                holdType = "knife"
                wepent.l_AttackAnimation = ACT_HL2MP_GESTURE_RANGE_ATTACK_KNIFE
            end
            self.l_HoldType = holdType

            local length = ( self.LS_MaxLength or random( 32, 64 ) )
            self:SetExternalVar( "LS_MaxLength", length )
            self:SetNW2Int( "LS_MaxLength", length )
            self.l_CombatAttackRange = ( length + 6 )

            local width = ( self.LS_MaxWidth or random( 2, 4 ) )
            self:SetExternalVar( "LS_MaxWidth", width )
            self:SetNW2Int( "LS_MaxWidth", width )
            
            local darkInner = self.LS_DarkInner
            if darkInner == nil then
                darkInner = ( random( 8 ) == 1 )
                self:SetExternalVar( "LS_DarkInner", darkInner )
                self:SetNW2Bool( "LS_DarkInner", darkInner )
            end

            local switchSnd = ( self.LS_SwitchSound or "lightsaber/saber_on" .. random( 4 ) .. ".wav" )
            self:SetExternalVar( "LS_SwitchSound", switchSnd )
            wepent:EmitSound( switchSnd, nil, nil, 0.4 )

            local loopSnd = ( self.LS_LoopSound or "lightsaber/saber_loop" .. random( 8 ) .. ".wav" )
            self:SetExternalVar( "LS_LoopSound", loopSnd )
            
            local swingSnd = ( self.LS_SwingSound or "lightsaber/saber_swing" .. random( 2 ) .. ".wav" )
            self:SetExternalVar( "LS_SwingSound", swingSnd )
                
            local holsterSnd = ( self.LS_HolsterSound or "lightsaber/saber_off" .. random( 4 ) .. ".wav" )
            self:SetExternalVar( "LS_HolsterSound", holsterSnd )

            self.LS_HoldType = holdType
            self.LS_IsHolstered = false
            self.LS_DmgAbsorbTime = 0
            self.LS_Force = ( self.LS_Force or 100 )
            self.LS_CurrentForce = false
            self.LS_LastForceType = false
            self.LS_LastForce = self.LS_Force
            self.LS_NextForceUseTime = ( self.LS_NextForceUseTime or 0 )
            self.LS_NextForceRegenTime = ( self.LS_NextForceRegenTime or 0 )
            self.LS_NextForceSwitchTime = ( self.LS_NextForceSwitchTime or 0 )
            self.LS_RecentDamage = ( self.LS_RecentDamage or 0 )
            self.LS_RecentDmgResetTime = ( self.LS_RecentDmgResetTime or CurTime() )
            self.LS_AgitatedTime = ( CurTime() + random( 5, 15 ) )
            self.LS_NextForceEffect = 0
            self.LS_ForceRepulse = false

            self:SetNW2Float( "LS_LengthAnimation", 0 )

            wepent.LS_SoundHit = CreateSound( wepent, "lightsaber/saber_hit.wav" )
            wepent.LS_SoundLoop = CreateSound( wepent, loopSnd )
            wepent.LS_SoundSwing = CreateSound( wepent, swingSnd)
        end,

        OnHolster = function( self, wepent )
            wepent:EmitSound( self.LS_HolsterSound, nil, nil, 0.4 )

            if wepent.LS_SoundHit then wepent.LS_SoundHit:Stop() end
            if wepent.LS_SoundLoop then wepent.LS_SoundLoop:Stop() end
            if wepent.LS_SoundSwing then wepent.LS_SoundSwing:Stop() end
        end,

        OnTakeDamage = function( self, wepent, dmginfo )
            if dmginfo:IsDamageType( DMG_FALL ) and random( 1, 3 ) == 1 then
                self:SetCrouch( true )
                self.l_moveWaitTime = ( CurTime() + 1 )
                self:SimpleTimer( 1, function() self:SetCrouch( false ) end )
                return true
            end
            
            --

            if CurTime() < self.LS_DmgAbsorbTime then
                local force = self.LS_Force
                if force < 1 then return end

                local damage = ( dmginfo:GetDamage() / 5 )
                if force < damage then
                    force = 0
                    dmginfo:SetDamage( ( damage - force ) * 5 )
                else
                    force = ( force - damage )
                    return true
                end
            end

            --

            self.LS_RecentDamage = ( self.LS_RecentDamage + dmginfo:GetDamage() )
            self.LS_RecentDmgResetTime = CurTime()
        end,

        OnThink = function( self, wepent, isDead )
            local inCombat, isRetreating = self:InCombat(), self:IsPanicking()
            if inCombat or isRetreating then
                self.LS_AgitatedTime = ( CurTime() + random( 5, 15 ) )
            end

            local animMax = 1
            if CurTime() < self.LS_AgitatedTime then
                if self.LS_IsHolstered then
                    self.LS_IsHolstered = false
                    self.l_HoldType = self.LS_HoldType
                    wepent:EmitSound( self.LS_SwitchSound, nil, nil, 0.4 )
                end
            else
                if !self.LS_IsHolstered then
                    self.LS_IsHolstered = true
                    wepent:EmitSound( self.LS_HolsterSound, nil, nil, 0.4 )
                end
                if self.l_HoldType != "normal" and self:GetNW2Float( "LS_LengthAnimation", 0 ) == 0 then
                    self.l_HoldType = "normal"
                end

                animMax = 0
            end

            local lengthAnim = ( isDead and 0 or math_Approach( self:GetNW2Float( "LS_LengthAnimation", 0 ), animMax, FrameTime() * ( animMax == 0 and 1 or 5 ) ) )
            self:SetNW2Float( "LS_LengthAnimation", lengthAnim )

            if isDead then
                if wepent.LS_SoundHit then wepent.LS_SoundHit:Stop() end
                if wepent.LS_SoundLoop then wepent.LS_SoundLoop:Stop() end
                if wepent.LS_SoundSwing then wepent.LS_SoundSwing:Stop() end
                return
            end

            if ( CurTime() - self.LS_RecentDmgResetTime ) >= 5 then
                self.LS_RecentDamage = 0
            end                

            local force = Clamp( self.LS_Force, 0, 100 )
            if CurTime() >= self.LS_NextForceRegenTime then
                force = min( ( force + 0.5 ), 100 )
            end
            self.LS_Force = force

            if self.LS_LastForce > force then
                self.LS_NextForceRegenTime = ( CurTime() + 4 )
            end
            self.LS_LastForce = force

            local maxLength = self:GetNW2Int( "LS_MaxLength", 48 )
            local forceType = self.LS_CurrentForce
            local enemy = self:GetEnemy()

            if inCombat and CurTime() < self.l_WeaponUseCooldown then
                local targetPos = enemy:WorldSpaceCenter()
                local faceAng = ( targetPos - self:WorldSpaceCenter() ):Angle()
                self.Face = ( targetPos + faceAng:Right() * random( -30, 30 ) + faceAng:Up() * random( -25, 25 ) )
                if !self.l_Faceend then self.l_Faceend = ( CurTime() + 0.1 ) end
            end

            if force < 1 then
                self.LS_NextForceUseTime = ( CurTime() + random( 5, 8 ) )
            elseif CurTime() >= self.LS_NextForceUseTime then
                
                if CurTime() >= self.LS_NextForceSwitchTime then
                    local newForce = false
                    if self:IsOnFire() then
                        newForce = "Force Heal"
                    elseif self.LS_RecentDamage >= ( self:Health() / 4 ) and ( !inCombat or !self:IsInRange( enemy, maxLength ) and self:CanSee( enemy ) ) or isRetreating and IsValid( enemy ) and self:IsInRange( enemy, 1500 ) and self:CanSee( enemy ) then
                        newForce = "Force Absorb"
                    elseif ( inCombat or isRetreating and IsValid( enemy ) ) and random( 1, 20 ) > 5 and self:CanSee( enemy ) then
                        local rndAttack = random( 6000 )
                        if rndAttack <= 1250 and self:IsInRange( enemy, 512 ) then
                            newForce = "Force Combust"
                        elseif rndAttack <= 3000 and self:IsInRange( enemy, 512 ) then
                            newForce = "Force Lightning"
                        elseif rndAttack >= 5000 and self:IsInRange( enemy, 384 ) then
                            newForce = "Force Repulse"
                        elseif !isRetreating and self:IsInRange( enemy, 1024 ) and ( random( 100 ) == 1 or !self:IsInRange( enemy, 512 ) ) then
                            newForce = "Force Leap"
                        end
                    elseif self:Health() < self:GetMaxHealth() then
                        newForce = "Force Heal"
                    end

                    if newForce != forceType then
                        forceType = newForce
                        self.LS_CurrentForce = forceType
                        self.LS_NextForceSwitchTime = ( CurTime() + Rand( 0.33, 2.0 ) )
                    end
                end

                local forceInfo = ForcePowers[ forceType ]
                if forceInfo and ( !IsValid( enemy ) or !self:IsInRange( enemy, maxLength + 10 ) ) and forceInfo.ConVar:GetBool() then
                    local infoCost = forceInfo.Cost
                    if !infoCost or force >= infoCost then 
                        local cooldown, cost = forceInfo.Action( self, wepent, enemy )
                        if cooldown != false then
                            self.LS_Force = ( self.LS_Force - ( cost or infoCost or 0 ) )
                            
                            local useTime = ( isnumber( cooldown ) and cooldown or forceInfo.Cooldown or 0 )
                            self.LS_NextForceUseTime = ( CurTime() + useTime )
                        
                            if CurTime() >= self.l_WeaponUseCooldown then
                                self.l_WeaponUseCooldown = ( CurTime() + useTime )
                            else
                                self.l_WeaponUseCooldown = ( self.l_WeaponUseCooldown + useTime )
                            end
                        end
                    end
                end
            end

            local repulseForce = self.LS_ForceRepulse
            local lastForceType = self.LS_LastForceType
            if repulseForce and forceType != lastForceType and lastForceType == "Force Repulse" then
                local selfPos = self:GetPos()
                local maxDist = ( 128 * repulseForce )
                
                for _, ent in ipairs( FindInSphere( selfPos, maxDist ) ) do
                    if ent == self or ent == wepent then continue end
                    if ( ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot() ) and !self:CanTarget( ent ) then continue end

                    local dist = self:GetRangeTo( ent )
                    local mul = ( ( maxDist - dist ) / 256 )
                    local dir = ( ( selfPos - ent:GetPos() ):GetNormalized() * mul )
                    dir.z = 64

                    if ( ent:IsNPC() or ent:IsNextBot() ) && IsValidRagdoll( ent:GetModel() or "" ) then
                        local dmginfo = DamageInfo()
                        dmginfo:SetDamagePosition( ent:WorldSpaceCenter() )
                        dmginfo:SetDamage( 48 * mul )
                        dmginfo:SetDamageType( DMG_GENERIC )
                        if ( 1 - dist / maxDist ) > 0.8 then
                            dmginfo:SetDamageType( DMG_DISSOLVE )
                            dmginfo:SetDamage( ent:Health() * 3 )
                        end
                        dmginfo:SetDamageForce( -dir * min( mul * 40000, 80000 ) )
                        dmginfo:SetInflictor( self )
                        dmginfo:SetAttacker( self )
                        ent:TakeDamageInfo( dmginfo )

                        local vel = ( dir * ( ent:IsOnGround() and -2048 or -1024 ) )
                        if ent:IsNextBot() then
                            ent.loco:Jump()
                            ent.loco:SetVelocity( vel )
                        else
                            ent:SetVelocity( vel )
                        end
                    elseif ent:IsPlayer() then 
                        ent:SetVelocity( dir * ( ent:IsOnGround() and -2048 or -384 ) )
                    else
                        local physCount = ent:GetPhysicsObjectCount()
                        if physCount > 0 then
                            for i = 0, ( physCount - 1 ) do
                                local phys = ent:GetPhysicsObjectNum( i )
                                if IsValid( phys ) then phys:ApplyForceCenter( dir * -512 * min( ent:GetPhysicsObject():GetMass(), 256 ) ) end
                            end
                        end
                    end
                end
                
                local effectData = EffectData()
                effectData:SetOrigin( selfPos + vector_up * 36 )
                effectData:SetRadius( maxDist )
                util_Effect( "rb655_force_repulse_out", effectData, true, true )

                self.LS_ForceRepulse = false
                wepent:EmitSound( "lightsaber/force_repulse.wav" )

                self.LS_NextForceUseTime = ( CurTime() + 1 )
                if CurTime() >= self.l_WeaponUseCooldown then
                    self.l_WeaponUseCooldown = ( CurTime() + 1 )
                else
                    self.l_WeaponUseCooldown = ( self.l_WeaponUseCooldown + 1 )
                end
            end
            self.LS_LastForceType = forceType

            --

            local bladeLength = ( lengthAnim * maxLength )
            if bladeLength <= 0 then return end
            
            bladeTrTbl.filter[ 1 ] = self
            bladeTrTbl.filter[ 2 ] = wepent
            local pos, ang = GetSaberPosAng( self, wepent, 1 )

            bladeTrTbl.start = pos
            bladeTrTbl.endpos = ( pos + ang * bladeLength )
            local trace = TraceLine( bladeTrTbl )
            if trace.Hit and !trace.HitSky and ( !trace.StartSolid or !trace.HitWorld ) then 
                isTracesHit = true
                rb655_DrawHit( trace )

                rb655_LS_DoDamage( trace, wepent ) 
            end

            bladeTrTbl.start = ( pos + ang * bladeLength )
            bladeTrTbl.endpos = pos
            local traceBack = TraceLine( bladeTrTbl )
            if traceBack.Hit and !traceBack.HitSky and ( !traceBack.StartSolid or !traceBack.HitWorld ) then 
                isTracesHit = true
                rb655_DrawHit( traceBack, true )
                
                if traceBack.Entity != trace.Entity then
                    rb655_LS_DoDamage( traceBack, wepent )
                end
            end

            if wepent:LookupAttachment( "blade2" ) > 0 then
                local pos2, dir2 = GetSaberPosAng( self, wepent, 2 )

                bladeTrTbl.start = pos2
                bladeTrTbl.endpos = ( pos2 + dir2 * bladeLength )
                local trace2 = TraceLine( bladeTrTbl )
                if trace2.Hit and !trace2.HitSky and ( !trace2.StartSolid or !trace2.HitWorld ) then 
                    isTracesHit = true
                    rb655_DrawHit( trace2 )

                    rb655_LS_DoDamage( trace2, wepent ) 
                end

                bladeTrTbl.start = ( pos2 + dir2 * bladeLength )
                bladeTrTbl.endpos = pos2
                local traceBack2 = TraceLine( bladeTrTbl )
                if traceBack2.Hit and !traceBack2.HitSky and ( !traceBack2.StartSolid or !traceBack2.HitWorld ) then 
                    isTracesHit = true
                    rb655_DrawHit( traceBack2, true )
                    
                    if traceBack2.Entity != trace2.Entity then
                        rb655_LS_DoDamage( traceBack2, wepent ) 
                    end
                end
            end

            --

            if wepent.LS_SoundHit then
                wepent.LS_SoundHit:ChangeVolume( ( isTracesHit and 0.1 or 0 ), 0 )
            end

            local soundMask =  ( bladeLength < maxLength and 0 or 1 )
            if wepent.LS_SoundSwing then
                if wepent.LS_LastAng != ang then
                    wepent.LS_LastAng = ( wepent.LS_LastAng or ang )
                    wepent.LS_SoundSwing:ChangeVolume( Clamp( ( ang:Distance( wepent.LS_LastAng ) / 2 ), 0, soundMask ), 0 )
                end
                wepent.LS_LastAng = ang
            end
            if wepent.LS_SoundLoop then
                pos = ( pos + ang * bladeLength )
                if wepent.LS_LastPos != pos then
                    wepent.LS_LastPos = ( wepent.LS_LastPos or pos )
                    wepent.LS_SoundLoop:ChangeVolume( 0.1 + Clamp( pos:Distance( wepent.LS_LastPos ) / 128, 0, soundMask * 0.9 ), 0 )
                end
                wepent.LS_LastPos = pos
            end
        end,

        OnDraw = function( self, wepent )
            local clr = self:GetPhysColor():ToColor()
            local blades = 0
            local bladesFound = false

            local entIndex = wepent:EntIndex()
            local darkInner = self:GetNW2Bool( "LS_DarkInner", false )
            local maxLength = self:GetNW2Int( "LS_MaxLength", 48 )
            local maxWidth = self:GetNW2Int( "LS_MaxWidth", 3 )
            local curLength = ( self:GetNW2Float( "LS_LengthAnimation", 0 ) * maxLength )
            local inWater = ( self:WaterLevel() == 3 )

            for _, attach in ipairs( wepent:GetAttachments() or {} ) do
                local name = attach.name
                local bladeNum = string_match( name, "blade(%d+)" )
                local quillonNum = string_match( name, "quillon(%d+)" )
                if !bladeNum and !quillonNum then continue end

                if bladeNum and wepent:LookupAttachment( "blade" .. bladeNum ) > 0 then
                    bladesFound = true
                    blades = ( blades + 1 )

                    local pos, dir = GetSaberPosAng( self, wepent, bladeNum )
                    rb655_RenderBlade( pos, dir, curLength, maxLength, maxWidth, clr, darkInner, entIndex, inWater, false, blades )
                end
                if quillonNum and wepent:LookupAttachment( "quillon" .. quillonNum ) > 0 then
                    blades = blades + 1

                    local pos, dir = GetSaberPosAng( self, wepent, quillonNum, true )
                    rb655_RenderBlade( pos, dir, curLength, maxLength, maxWidth, clr, darkInner, entIndex, inWater, true, blades )
                end
            end

            if !bladesFound then
                local pos, dir = GetSaberPosAng( self, wepent )
                rb655_RenderBlade( pos, dir, curLength, maxLength, maxWidth, clr, darkInner, entIndex, inWater )
            end
        end,

        OnAttack = function( self, wepent, target )
            local anim = wepent.l_AttackAnimation
            self:RemoveGesture( anim )
            self:AddGesture( anim )

            self.l_WeaponUseCooldown = ( CurTime() + 0.5 )
            self.LS_AgitatedTime = ( CurTime() + random( 5, 15 ) )
            return true
        end, 

        OnDeath = function( self )
            self.LS_DmgAbsorbTime = 0
            self.LS_Force = 100
            self.LS_CurrentForce = false
            self.LS_LastForce = self.LS_Force
            self.LS_NextForceUseTime = 0
            self.LS_NextForceRegenTime = 0
            self.LS_NextForceSwitchTime = 0
            self.LS_RecentDamage = 0
            self.LS_RecentDmgResetTime = CurTime()
            self.LS_ForceRepulse = false

            self:SetNW2Float( "LS_LengthAnimation", 0 )
        end,

        OnDealDamage = function( self, wepent, target, info, tookDamage, killed )
            if killed then target:EmitSound( "lightsaber/saber_hit_laser" .. random( 5 ) .. ".wav" ) end
        end
    }
} )