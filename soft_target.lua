-- Fishing Addon - Soft Targeting
-- Configures soft-targeting CVars for maximum interact range and arc.
-- Makes the interact key (F) auto-detect nearby game objects like treasures.

local FA = FishingAddon

local SOFT_TARGET_CVARS = {
    SoftTargetInteract          = "3",
    SoftTargetInteractRange     = "10",
    SoftTargetInteractArc       = "2",
    SoftTargetIconGameObject    = "1",
    SoftTargetIconInteract      = "1",
    SoftTargetLowPriorityIcons  = "1",
    -- Click-to-move: pressing interact on a soft-target walks to it
    autoInteract                = "1",
}

function FA.ApplySoftTargeting()
    for cvar, value in pairs(SOFT_TARGET_CVARS) do
        SetCVar(cvar, value)
    end
end
