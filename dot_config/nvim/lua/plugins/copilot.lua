
--- @type LazySpec
return {
    "zbirenbaum/copilot.lua",
    cmd = { "Copilot" },
    event = { "InsertEnter" },
    opts = {
        filetypes = {
            gitcommit = true
        },
    },
}
