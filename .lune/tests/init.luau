--> Run tests using frktest runner

local fs = require("@lune/fs")
local process = require("@lune/process")

local frktest = require("../../lune_packages/frktest")
local reporter = require("./reporter")

-- HACK: Cast require to allow for dynamic paths in strict mode
-- A more proper solution would be to use luau.load instead, but
-- frktest requires its global state to be modified by test suites
local require = require :: (
	path: string
) -> (
	test: typeof(setmetatable(
		{} :: {
			case: (name: string, fn: () -> nil) -> (),
			suite: (name: string, fn: () -> ()) -> (),
		},
		{ __index = frktest.test }
	))
) -> ()


local function discoverTests(dir: string): { string }
	local tests = {}

	local entries = fs.readDir(dir)
	for _, entry in entries do
		local path = `{dir}/{entry}`

		-- Look for files ending in `.spec.luau` as tests
		if fs.isFile(path) and string.match(entry, "%.spec%.luau$") then
			table.insert(tests, path)
			continue
		end

		-- Recurse for directories
		if fs.isDir(path) then
			local dirResults = discoverTests(path)
			table.move(dirResults, 1, #dirResults, #tests + 1, tests)
			continue
		end
	end

	return tests
end

local allowedTests = process.args
for _, test in discoverTests("src") do
	-- If we are given any arguments, we only run those tests, otherwise,
	-- we run all the tests

	-- So, to include only a certain set of test files, you can provide either
	-- the full path of the test file or name of the test file, with or without
	-- the `.spec.luau` extension
	local baseName = string.match(test, "([^/\\]+)$")

	local withoutExt = string.sub(test, 1, -11)
	local baseNameWithoutExt = string.match(withoutExt, "([^/\\]+)$")

	local isAllowed = #process.args == 0
		or table.find(allowedTests, test)
		or table.find(allowedTests, withoutExt)
		or table.find(allowedTests, baseName)
		or table.find(allowedTests, baseNameWithoutExt)

	local constructors = {
		case = frktest.test.case,
		suite = frktest.test.suite,
	}

	if not isAllowed then
		constructors.case = frktest.test.skip.case
		constructors.suite = frktest.test.skip.suite
	end

	require(`../../{test}`)(
		setmetatable(constructors, { __index = frktest.test })
	)
end

reporter.init()
process.exit(tonumber(frktest.run()))
