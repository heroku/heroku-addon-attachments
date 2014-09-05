# load default addon functionality
require("heroku/command/addons")

# load overrides
require("#{File.dirname(__FILE__)}/lib/ext/heroku/api/mock")
require("#{File.dirname(__FILE__)}/lib/ext/heroku/api/mock/attachments")
require("#{File.dirname(__FILE__)}/lib/ext/heroku/api/mock/resources")
require("#{File.dirname(__FILE__)}/lib/ext/heroku/command/addons")
