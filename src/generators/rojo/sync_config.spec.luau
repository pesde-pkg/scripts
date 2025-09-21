local fs = require("@lune/fs")
local serde = require("@lune/serde")

local frktest = require("../../../luau_packages/frktest")
local check = frktest.assert.check

local syncConfig = require("./sync_config")

local TEST_PROJECTS_DIRS = {
	"./test-files/rojo/test-projects",
	"./test-files/rojo/rojo-test/serve-tests",
}

return function(test: typeof(frktest.test))
	test.suite("Generates Rojo valid sync configs", function()
		for _, entry in TEST_PROJECTS_DIRS do
			for _, subEntry in fs.readDir(entry) do
				local path = `{entry}/{subEntry}`
				test.case(`{subEntry}`, function()
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
		end
	end)
end
