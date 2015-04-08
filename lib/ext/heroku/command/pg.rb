require "heroku/helpers/heroku_postgresql"
require "ext/heroku/helpers/addons/resolve"
require "ext/heroku/helpers/addons/api"

module Heroku::Command

  # manage heroku-postgresql databases
  #
  class Pg < Base
    include Heroku::Helpers::Addons::Resolve
    include Heroku::Helpers::Addons::API

    # pg:promote DATABASE
    #
    # sets DATABASE as your DATABASE_URL
    #
    def promote
      requires_preauth
      unless db = shift_argument
        error("Usage: heroku pg:promote DATABASE\nMust specify DATABASE to promote.")
      end
      validate_arguments!

      addon = resolve_addon!(db)

      attachment_name = 'DATABASE'
      action "Promoting #{addon['name']} to #{attachment_name}_URL on #{app}" do
        request(
          :body     => json_encode({
            "app"     => {"name" => app},
            "addon"   => {"name" => addon['name']},
            "confirm" => app,
            "name"    => attachment_name
          }),
          :expects  => 201,
          :method   => :post,
          :path     => "/addon-attachments"
        )
      end
    end
  end
end
