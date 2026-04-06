-- luals --check must be $ThisFileDirectory/../lua so that workspace library and ignoreDir work
return {
    Lua = {
        runtime = {
            version = "LuaJIT",
            nonstandardSymbol = {
                "/**/",
                "//",
                "!",
                "!=",
                "&&",
                "||",
                "continue",
            },
            special = {
                include = "dofile",
            },
        },
        diagnostics = {
            disable = {
                "deprecated",
            },
        },
        workspace = {
            library = {
                "../.vscode/server",
                "../.vscode/types",
            },
            ignoreDir = {
                "../.vscode",
                "effects",
                "matproxy",
                "splashsweps/client",
            },
        },
    },
}
