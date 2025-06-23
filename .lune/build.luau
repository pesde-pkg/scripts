--> Generates sync config and sourcemap scripts for supported tools

local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local lib = require("../src")
local manifest = require("./lib/manifest")
local pathfs = require("../lune_packages/pathfs")
local fs = pathfs.fs

type ToolChoice = "rojo"
local SCRIPTS_DIR = pathfs.absolute(pathfs.Path.from(".pesde"))
local MANIFEST = manifest(nil, (nil :: any) :: { meta: manifest.PesdeManifest })
local SCRIPTS = {
	syncConfigGenerator = [[local process = require("@lune/process")

local args = table.clone(process.args)
local ok, _ =
require("./lune_packages/core").generators.%s.syncConfig(table.remove(args, 1), args, { writeToFile = true })
if not ok then
	return process.exit(1)
end]],

	sourcemapGenerator = [[local process = require("@lune/process")

local ok = require("./lune_packages/core").generators.%s.sourcemap(process.args[1])
if not ok then
	return process.exit(1)
end
]],
}

local README_TMPL = [[# `pesde/scripts_%s`
Common scripts intended for use with %s.

## Included scripts
### roblox_sync_config_generator

Generates a %s sync config for pesde Roblox packages.

### sourcemap_generator

Prints out a sourcemap for Wally dependencies for type extraction.
]]

local function logPrefix(type: "error" | "info")
	local statusColor: stdio.Color = if type == "error"
		then "red"
		elseif type == "info" then "green"
		else error(`Invalid type: {type}`)

	return `main::{stdio.style("bold")}{stdio.color(statusColor)}{type}{stdio.color(
		"reset"
	)}`
end

local INFO_PREFIX = `[ {logPrefix("info")}]`
local _ERROR_PREFIX = `[{logPrefix("error")}]`

local function installDeps(): number
	local PESDE_INFO_PREFIX =
		string.gsub(`[{logPrefix("info")}]`, "main", "pesde")
	local PESDE_ERROR_PREFIX =
		string.gsub(`[{logPrefix("error")}]`, "main", "pesde")
	local SPINNER_STATES =
		{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

	stdio.write(`{PESDE_INFO_PREFIX} Installing dependencies with pesde`)

	-- Spawn our thread to display the spinner
	local spinnerThread = task.spawn(function()
		-- Hide the cursor
		stdio.write("\x1b[?25l")

		-- Display the spinner
		while true do
			for _, state in SPINNER_STATES do
				stdio.write(` {state}`)
				stdio.write(
					-- Moves the cursor back 1 spot and clears everything after
					"\x1b[2D\x1b[0K"
				)

				-- Wait 10ms between each spinner state
				task.wait(0.1)
			end
		end
	end)

	-- `process_spawn` is an async rust function, so tokio spawns a hardware
	-- thread and mlua will yield the current thread, allowing for `spinnerThread`
	-- to continue executing
	local child = process.exec("pesde", { "install" }, {
		stdio = "default",
	})

	-- If we reach this point, that means mlua resumed the current thread and
	-- `process_spawn` returned or errored. We can now close `spinnerThread` and
	-- clean up

	task.cancel(spinnerThread)
	stdio.write(
		-- Clear the current line, move cursor back to its beginning and
		-- show it
		"\x1b[2K\x1b[1G\x1b[?25h"
	)

	if not child.ok then
		stdio.ewrite(
			`{PESDE_ERROR_PREFIX} Failed to install dependencies with pesde, error:\n`
		)
		stdio.ewrite(child.stderr)
	end

	stdio.write(
		`{PESDE_INFO_PREFIX} Installed dependencies with pesde successfully\n`
	)

	return child.code
end

for tool, generators in lib.generators do
	local startTime = os.clock()

	-- For each tool, we generate a respective manifests and scripts
	local toolChoice = tool :: ToolChoice
	local toolScriptsDir = SCRIPTS_DIR:join(toolChoice)
	local toolMeta = MANIFEST.meta.scripts[toolChoice]

	if not fs.isDir(toolScriptsDir) then
		fs.writeDir(toolScriptsDir)
	end

	local capitalisedToolChoice = string.gsub(toolChoice, "^%l", string.upper)

	-- Define the manifest for the tool
	local toolManifest: manifest.PesdeManifest = {
		name = `pesde/scripts_{toolChoice}`,
		version = toolMeta.version,
		-- For the description, we capitalize the first letter of the tool name here
		-- since it is a proper noun
		description = `Scripts for {capitalisedToolChoice}-based Roblox projects.`,
		authors = {
			"daimond113 <contact@daimond113.com> (https://www.daimond113.com/)",
			"Erica Marigold <hi@devcomp.xyz>",
		},
		repository = "https://github.com/pesde-pkg/scripts",
		license = "MIT",
		includes = {
			"roblox_sync_config_generator.luau",
			"sourcemap_generator.luau",
			"pesde.toml",
			"README.md",
			"LICENSE",
		},

		target = {
			environment = "lune",
			scripts = {
				roblox_sync_config_generator = "roblox_sync_config_generator.luau",
				sourcemap_generator = "sourcemap_generator.luau",
			},
		},

		peer_dependencies = toolMeta.tool_dependencies,
		dependencies = {
			core = { workspace = "pesde/scripts_core", version = "^" },
		},

		indices = {
			default = "https://github.com/pesde-pkg/index",
		},
	}

	-- Format the scripts for the tool
	local syncConfigGeneratorScript, sourcemapGeneratorScript =
		string.format(SCRIPTS.syncConfigGenerator, toolChoice),
		string.format(SCRIPTS.sourcemapGenerator, toolChoice)

	-- Finally, write all the generated files
	fs.writeFile(
		toolScriptsDir:join("pesde.toml"),
		serde.encode("toml", toolManifest, true)
	)
	fs.writeFile(
		toolScriptsDir:join("roblox_sync_config_generator.luau"),
		syncConfigGeneratorScript
	)
	fs.writeFile(
		toolScriptsDir:join("sourcemap_generator.luau"),
		sourcemapGeneratorScript
	)
	fs.writeFile(
		toolScriptsDir:join("README.md"),
		string.format(
			README_TMPL,
			toolChoice,
			capitalisedToolChoice,
			capitalisedToolChoice
		)
	)
	fs.copy(
		pathfs.cwd():join("LICENSE"),
		toolScriptsDir:join("LICENSE"),
		true
	)

	stdio.write(
		`{INFO_PREFIX} Generated script project for tool {toolChoice} ({stdio.style(
			"dim"
		)}{string.format("%.2fms", (os.clock() - startTime) * 1000)}{stdio.style(
			"reset"
		)})\n`
	)
end

-- Now we install the dependencies for the newly created projects
-- process.exit(installDeps())
