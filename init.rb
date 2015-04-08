# load default addon functionality
require("heroku/command/addons")

# load overrides
require("#{File.dirname(__FILE__)}/lib/ext/heroku/command/addons")
