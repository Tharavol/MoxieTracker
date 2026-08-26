-- luacheck configuration for a World of Warcraft addon.
-- The WoW client runs Lua 5.1 and injects its API as globals, so every API the
-- addon touches has to be declared here or it reads as an undefined global.

std = "lua51"
max_line_length = 120

-- The luarocks CI action installs into .luarocks/ inside the workspace, so
-- `luacheck .` would otherwise lint the toolchain along with the addon.
exclude_files = {".luarocks/**", ".luarocks", "lua_modules/**"}

-- Globals this addon defines. MoxieTrackerDB is the SavedVariables table, and
-- the slash command globals are how the client discovers commands.
globals = {
    "MoxieTrackerDB",
    "SLASH_MOXIETRACKER1",
    "SLASH_MOXIETRACKER2",
    "SlashCmdList",
}

-- WoW API surface used by this addon. Deliberately narrow: a typo in an API
-- name should fail the check rather than be silently allowed by a broad list.
read_globals = {
    "C_AddOns",
    "C_CurrencyInfo",
    "C_Item",
    "C_Timer",
    "C_TradeSkillUI",
    "CreateFrame",
    "Enum",
    "EventUtil",
    "GameTooltip",
    "GetProfessionInfo",
    "GetProfessions",
    "GetRealmName",
    "GetServerTime",
    "IsShiftKeyDown",
    "Settings",
    "UIParent",
    "UnitName",
}

-- The offline test harness temporarily reassigns print() to capture slash
-- command output, and installs its own WoW stubs into _G on purpose.
files["tests/**"] = {
    ignore = {"121", "122"},
}
