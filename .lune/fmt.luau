--> Run stylua to check for formatting errors

local process = require("@lune/process")

local CommandBuilder = require("./lib/exec")

process.exit(
	CommandBuilder.new("stylua")
		:withArg(".")
		:withArgs(process.args)
		:withStdioStrategy("forward")
		:exec().code
)
