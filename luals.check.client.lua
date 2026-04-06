-- luals --check must be $ThisFileDirectory/../lua so that workspace library and ignoreDir work
return {
    Lua = {
        diagnostics = {
            disable = {
                "deprecated",
            },
        },
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
        workspace = {
            library = {
                "../.vscode/client",
                "../.vscode/types",
            },
            ignoreDir = {
                "../.vscode",
                "splashsweps/server",
            },
        },
    },
}
