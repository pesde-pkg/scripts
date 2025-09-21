local fs = require("@lune/fs")
local serde = require("@lune/serde")

local frktest = require("../../../luau_packages/frktest")
local check = frktest.assert.check

local syncConfig = require("./sync_config")

local TEST_PROJECTS_DIR = "./test-files/argon"

return function(test: typeof(frktest.test))
	test.suite("Generates valid Argon sync configs", function()
		for _, entry in fs.readDir(TEST_PROJECTS_DIR) do
			local path = `{TEST_PROJECTS_DIR}/{entry}`
			if not fs.isDir(path) or entry == ".git" then
				continue
			end

			test.case(`{entry}`, function()
				local ok, config = syncConfig(
					path,
					fs.readDir(path),
					{ writeToFile = false, force = true }
				)
				check.is_true(ok)

				-- Make sure that the generated config and the real configs are similar
				local generatedConfig, realConfig =
					serde.decode("json", config :: string),
					serde.decode(
						"json",
						fs.readFile(`{path}/default.project.json`)
					)

				check.table.contains(realConfig, generatedConfig)
			end)
		end
	end)
end
