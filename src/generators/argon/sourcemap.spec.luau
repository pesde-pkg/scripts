local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local regex = require("@lune/regex")
local serde = require("@lune/serde")

local frktest = require("../../../lune_packages/frktest")
local check = frktest.assert.check

local TEST_PROJECTS_DIR = "./test-files/argon"

local BUILTIN_PATCHES: {
	[string]: { [string]: (...any) -> ...any? },
} = {
	["@lune/process"] = {
		spawn = function(
			program: string,
			params: { string },
			options: process.ExecOptions
		): process.ExecResult
			local patchedOptions: process.ExecOptions = options or {}
			patchedOptions.stdio = "default"

			local result = process.exec(program, params, patchedOptions)

			-- First we make sure the command exited properly
			assert(
				result.ok,
				`Expected \`rojo\` command to not error, got:\n{string.rep(
					"  ",
					6
				)}{result.stderr}`
			)

			-- We also make sure that the output JSON was valid
			serde.decode("json", result.stdout)

			return result
		end,
	},

	["@lune/stdio"] = {
		write = function(msg: string)
			-- Only make sure output JSON is valid
			serde.decode("json", msg)
		end,
	},
}

local function requireWithPatches(path: string)
	for builtin, patch in BUILTIN_PATCHES do
		if path == builtin then
			return setmetatable(patch, { __index = require(builtin) })
		end
	end

	return require(path)
end

return function(test: typeof(frktest.test))
	test.suite(
		"Generates Argon sourcemaps for test projects successfully",
		function()
			for _, entry in fs.readDir(TEST_PROJECTS_DIR) do
				local path = `{TEST_PROJECTS_DIR}/{entry}`
				if not fs.isDir(path) or entry == ".git" then
					-- Skip files that are not project directories
					continue
				end

				test.case(entry, function()
					-- If a file starts with `bad_` but not `bad_meta_`, we should expect a failure
					-- Also, sorry about this shitty regex, regex-rs does not support look-around :(
					local isBadMeta = regex.new(
						"^bad_[^m]|^bad_m[^e]|^bad_me[^t]|^bad_met[^a]"
					)
					local expect = if isBadMeta:isMatch(entry)
						then check.should_error
						else check.should_not_error

					expect(function()
						-- We override the require which applies some patches to some builtins, mainly preventing
						-- command stdout forwarding and `stdio.write` outputs to stdout in order to not fill
						-- test ouput with large amounts of JSON data
						local sourcemap: (string) -> boolean = luau.load(
							fs.readFile("./src/generators/argon/sourcemap.luau"),
							{
								environment = {
									require = requireWithPatches,
								},
							}
						)()

						return check.is_true(sourcemap(path))
					end)
				end)
			end
		end
	)
end
