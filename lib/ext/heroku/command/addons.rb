require "heroku/command/base"
require "heroku/helpers/heroku_postgresql"
require "ext/heroku/helpers/addons/api"

module Heroku::Command

  # manage add-on resources
  #
  class Addons < Base

    include Heroku::Helpers::HerokuPostgresql
    include Heroku::Helpers::Addons::API

    # addons [{--all,--app APP,--resource ADDON_NAME}]
    #
    # list installed add-ons
    #
    # NOTE: --all is the default unless in an application repository directory, in
    # which case --all is inferred.
    #
    # --all                  # list add-ons across all apps in account
    # --app APP              # list add-ons associated with a given app
    # --resource ADDON_NAME  # view details about add-on and all of its attachments
    #
    #Examples:
    #
    # $ heroku addons --all
    # $ heroku addons --app acme-inc-website
    # $ heroku addons --resource @acme-inc-database
    #
    def index
      validate_arguments!
      requires_preauth

      # Filters are mutually exclusive
      error("Can not use --all with --app")      if options[:app] && options[:all]
      error("Can not use --all with --resource") if options[:resource] && options[:all]
      error("Can not use --app with --resource") if options[:resource] && options[:app]

      app = (self.app rescue nil)
      if (resource = options[:resource])
        show_for_resource(resource)
      elsif app && !options[:all]
        show_for_app(app)
      else
        show_all
      end
    end

    # addons:services
    #
    # list all available add-on services
    def services
      if current_command == "addons:list"
        deprecate("`heroku #{current_command}` has been deprecated. Please use `heroku addons:services` instead.")
      end

      display_table(get_services, %w[name human_name state], %w[Slug Name State])
      display "\nSee plans with `heroku addons:plans SERVICE`"
    end

    private :list # removes docs for non-plugin implementation
    alias_command "addons:list", "addons:services"

    # addons:plans SERVICE
    #
    # list all available plans for an add-on service
    def plans
      service = args.shift
      raise CommandFailed.new("Missing add-on service") if service.nil?

      service = get_service!(service)
      display_header("#{service['human_name']} Plans")

      plans = get_plans(:service => service['id'])

      plans = plans.sort_by { |p| [(!p['default']).to_s, p['price']['cents']] }.map do |plan|
        {
          "default"    => ('default' if plan['default']),
          "name"       => plan["name"],
          "human_name" => plan["human_name"],
          "price"      => "$%.2f/%s" % [(plan["price"]["cents"] / 100.0), plan["price"]["unit"]],
        }
      end

      display_table(plans, %w[default name human_name price], [nil, 'Slug', 'Name', 'Price'])
    end

    # addons:create PLAN
    #
    # create an add-on resource
    #
    # --name NAME             # (optional) name for the resource
    # --as ATTACHMENT_NAME    # (optional) name for the initial add-on attachment
    # --confirm APP_NAME      # (optional) ovewrite existing config vars or existing add-on attachments
    #
    def create
      if current_command == "addons:add"
        deprecate("`heroku #{current_command}` has been deprecated. Please use `heroku addons:create` instead.")
      end

      requires_preauth

      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil? || %w{--fork --follow --rollback}.include?(addon)
      config = parse_options(args)

      addon = request(
        :body     => json_encode({
          "attachment" => { "name" => options[:as] },
          "config"     => config,
          "name"       => options[:name],
          "confirm"    => options[:confirm],
          "plan"       => { "name" => addon }
        }),
        :expects  => 201,
        :method   => :post,
        :path     => "/apps/#{app}/addons"
      )

      action("Creating #{addon['name'].downcase}") {}
      action("Adding #{addon['name'].downcase} to #{app}") {}
      action("Setting #{addon['config_vars'].join(', ')} and restarting #{app}") do
        @status = api.get_release(app, 'current').body['name']
      end

      #display resource['provider_data']['message'] unless resource['provider_data']['message'].strip == ""

      display("Use `heroku addons:docs #{addon['plan']['name'].split(':').first}` to view documentation.")
    end

    private :add # removes docs for non-plugin implementation
    alias_command "addons:add", "addons:create"

    # addons:attach ADDON
    #
    # attach add-on resource to an app
    #
    # --as ATTACHMENT_NAME  # (optional) name for add-on attachment
    # --confirm APP_NAME    # overwrite existing add-on attachment with same name
    #
    def attach
      unless addon = args.shift
        error("Usage: heroku addons:attach ADDON\nMust specify ADDON to attach.")
      end
      addon = addon.dup.sub('@', '')

      requires_preauth

      attachment_name = options[:as]

      msg = attachment_name ?
        "Attaching #{addon} as #{attachment_name} to #{app}" :
        "Attaching #{addon} to #{app}"

      display("#{msg}... ", false)

      response = api.request(
        :body     => json_encode({
          "app"     => {"name" => app},
          "addon"   => {"name" => addon},
          "confirm" => options[:confirm],
          "name"    => attachment_name
        }),
        :expects  => [201, 422],
        :headers  => { "Accept" => "application/vnd.heroku+json; version=3.switzerland" },
        :method   => :post,
        :path     => "/addon-attachments"
      )

      case response.status
      when 201
        display("done")
        action("Setting #{response.body["name"]} vars and restarting #{app}") do
          @status = api.get_release(app, 'current').body['name']
        end
      when 422 # add-on resource not found or cannot be attached
        display("failed")
        output_with_bang(response.body["message"])
        output_with_bang("List available resources with `heroku addons`.")
        output_with_bang("Provision a new add-on resource with `heroku addons:create ADDON_PLAN`.")
      end
    end

    # addons:upgrade ADDON PLAN
    #
    # upgrade an existing add-on resource to PLAN
    #
    def upgrade
      change_plan(:upgrade)
    end

    # addons:downgrade ADDON PLAN
    #
    # downgrade an existing add-on resource to PLAN
    #
    def downgrade
      change_plan(:downgrade)
    end

    # addons:detach ATTACHMENT
    #
    # detach add-on resource from an app
    #
    def detach
      attachment_name = args.shift
      raise CommandFailed.new("Missing add-on attachment name") if attachment_name.nil?

      requires_preauth

      addon_attachment = get_attachment(attachment_name, :app => app)

      unless addon_attachment
        error("Add-on attachment not found")
      end

      action("Removing #{attachment_name} attachment to #{addon_attachment['addon']['name']} from #{app}") do
        api.request(
          :expects  => 200..300,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=3.switzerland" },
          :method   => :delete,
          :path     => "/addon-attachments/#{addon_attachment['id']}"
        ).body
      end
      action("Unsetting #{attachment_name}_URL and restarting #{app}") do
        @status = api.get_release(app, 'current').body['name']
      end
    end

    # addons:destroy ADDON
    #
    # destroy an add-on resources
    #
    # -f, --force # allow destruction even if this in not the final attachment
    #
    def destroy
      if current_command == "addons:remove"
        deprecate("`heroku #{current_command}` has been deprecated. Please use `heroku addons:destroy` instead.")
      end

      requires_preauth

      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil?

      return unless confirm_command

      addon = addon.dup.sub('@', '')
      addon_attachments = get_attachments(:resource => addon)

      addon_attachments.each do |attachment|
        name = attachment['name']
        app = attachment['app']['name']
        action("Removing #{addon} as #{name} from #{app}") {}
        action("Unsetting #{name} vars and restarting #{app}") {}
      end

      @status = api.get_release(app, 'current').body['name']
      action("Destroying #{addon} on #{app}") do
        api.request(
          :body     => json_encode({
            "force" => options[:force],
          }),
          :expects  => 200..300,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=3.switzerland" },
          :method   => :delete,
          :path     => "/apps/#{app}/addons/#{addon}"
        )
      end
    end

    private :remove # removes docs for non-plugin implementation
    alias_command "addons:remove", "addons:destroy"

    # addons:docs ADDON
    #
    # open an add-on's documentation in your browser
    #
    def docs
      unless addon = shift_argument
        error("Usage: heroku addons:docs ADDON\nMust specify ADDON to open docs for.")
      end
      validate_arguments!

      addon_names = api.get_addons.body.map {|a| a['name']}
      addon_types = addon_names.map {|name| name.split(':').first}.uniq

      name_matches = addon_names.select {|name| name =~ /^#{addon}/}
      type_matches = addon_types.select {|name| name =~ /^#{addon}/}

      if name_matches.include?(addon) || type_matches.include?(addon)
        type_matches = [addon]
      end

      case type_matches.length
      when 0 then
        error([
          "`#{addon}` is not a heroku add-on.",
          suggestion(addon, addon_names + addon_types),
          "See `heroku addons:list` for all available add-ons."
        ].compact.join("\n"))
      when 1
        addon_type = type_matches.first
        launchy("Opening #{addon_type} docs", addon_docs_url(addon_type))
      else
        error("Ambiguous add-on name: #{addon}\nPerhaps you meant #{name_matches[0...-1].map {|match| "`#{match}`"}.join(', ')} or `#{name_matches.last}`.\n")
      end
    end

    # addons:open ADDON
    #
    # open an add-on's dashboard in your browser
    #
    def open
      unless addon = shift_argument
        error("Usage: heroku addons:open ADDON\nMust specify ADDON to open.")
      end
      validate_arguments!

      addons = get_addons(:app => app)

      # When passed the @-name (@whatever-foo-1234)
      matches = addons.select { |a| a["name"] =~ /@?#{addon}/ }

      # When passed the service name and plan (heroku-postgresql:hobby-dev)
      if matches.empty?
        matches = addons.select { |a| a["plan"]["name"] == addon }
      end

      # When passed the service name (heroku-postgresql)
      if matches.empty?
        matches = addons.select { |a| a["addon_service"]["name"] == addon }
      end

      case matches.length
      when 0 then
        addon_names = get_addons.map { |a| a["name"] }

        if addon_names.any? {|name| name =~ /^#{addon}/}
          error("Add-on not installed: #{addon}.")
        else
          error([
            "`#{addon}` is not a heroku add-on.",
            suggestion(addon, addon_names + addon_names.map {|name| name.split(':').first}.uniq),
            "See `heroku addons:list` for all available add-ons."
          ].compact.join("\n"))
        end
      when 1 then
        addon_to_open = matches.first
        launchy("Opening #{addon_to_open["addon_service"]["name"]} (#{addon_to_open["name"]}) for #{app}", addon_to_open["web_url"])
      else
        message         = "Ambiguous add-on name. Perhaps you meant one of the following: "
        suggestions     = matches[0...-1].map { |a| "`#{a["name"]}`" }.join(", ")
        last_suggestion = "`#{matches.last["name"]}`"
        error([message, suggestions, " or ", last_suggestion].join)
      end
    end

    private

    # Shows details about and attachments for a specified resource. For example:
    #
    # $ heroku addons --resource practicing-nobly-1495
    # === Resource Info
    # Name:        practicing-nobly-1495
    # Plan:        heroku-postgresql:premium-yanari
    # Billing App: addons-reports
    # Price:       $200.00/month
    #
    # === Attachments
    # App             Name
    # --------------  ------------------------
    # addons          ADDONS_REPORTS
    # addons-reports  DATABASE
    # addons-reports  HEROKU_POSTGRESQL_SILVER
    def show_for_resource(identifier)
      styled_header("Resource Info")

      resource = get_addon(identifier)

      styled_hash({
        'Name'        => resource['name'],
        'Plan'        => resource['plan']['name'],
        'Billing App' => resource['app']['name'],
        'Price'       => format_price(resource['plan']['price'])
      }, ['Name', 'Plan', 'Billing App', 'Price'])

      display("") # separate sections

      styled_header("Attachments")
      display_attachments(get_attachments(:resource => identifier), ['App', 'Name'])
    end

    # Shows all add-ons owned by and attachments attached to the provided app. For example:
    #
    # === Add-on Resources for bjeanes
    # Plan                     Name                    Price
    # -----------------------  ----------------------  -----
    # heroku-postgresql:dev    budding-busily-2230     free
    # memcachier-staging:test  sighing-ably-6278       free
    # memcachier-staging:test  rolling-carefully-8506  free
    # newrelic:wayne           unwinding-kindly-4330   free
    # pgbackups:plus           pgbackups-8071074       free
    #
    # === Add-on Attachments for bjeanes
    # Name                      Add-on                  Billing App
    # ------------------------  ----------------------  -----------
    # DATABASE                  budding-busily-2230     bjeanes
    # HEROKU_POSTGRESQL_VIOLET  budding-busily-2230     bjeanes
    # MEMCACHE                  sighing-ably-6278       bjeanes
    # MEMCACHIER_STAGING        rolling-carefully-8506  bjeanes
    # NEWRELIC                  unwinding-kindly-4330   bjeanes
    # PGBACKUPS                 pgbackups-8071074       bjeanes
    def show_for_app(app)
      styled_header("Resources for #{app}")

      addons = get_addons(:app => app).
        select { |addon| addon['app']['name'] == app }

      display_addons(addons, %w[Plan Name Price])

      display('') # separate sections

      styled_header("Attachments for #{app}")
      display_attachments(get_attachments(:app => app), ['Name', 'Add-on', 'Billing App'])
    end

    # Shows a table of all add-ons on the account. For example:
    #
    # === Add-on Resources
    # Plan                     Name                         Billing App     Price
    # -----------------------  ---------------------------  --------------  ------------
    # bugsnag:sagittaron       bugsnag-9174150              addons          $9.00/month
    # deployhooks:hipchat      deployhooks-hipchat-9852225  addons-staging  free
    # heroku-postgresql:crane  advising-fairly-3183         ion-bo          $50.00/month
    # newrelic:wayne           unwinding-kindly-4330        bjeanes         free
    def show_all
      styled_header('Resources')

      display_addons(get_addons, ['Plan', 'Name', 'Billed to', 'Price'])
    end

    def display_attachments(attachments, fields)
      if attachments.empty?
        display('There are no attachments.')
      else
        table = attachments.map do |attachment|
          {
            'Name'        => attachment['name'],
            # 'Service'     => attachment['addon_service']['name'],
            'Add-on'      => attachment['addon']['name'],
            'Billing App' => attachment['addon']['app']['name'],
            'App'         => attachment['app']['name']
          }
        end.sort_by { |addon| fields.map { |f| addon[f] } }

        display_table(table, fields, fields)
      end
    end

    def display_addons(addons, fields)
      if addons.empty?
        display('There are no add-ons.')
      else
        table = addons.map do |addon|
          {
            'Plan'      => addon['plan']['name'],
            'Name'      => addon['name'],
            'Billed to' => addon['app']['name'],
            'Price'     => format_price(addon['plan']['price'])
          }
        end.sort_by { |addon| fields.map { |f| addon[f] } }

        display_table(table, fields, fields)
      end
    end

    def change_plan(direction)
      addon_name, plan = args.shift, args.shift

      if addon_name && !plan # If invocated as `addons:Xgrade service:plan`
        deprecate("No add-on name specified (see `heroku help #{current_command}`)")

        addon = nil
        plan = addon_name
        service = plan.split(':').first

        action("Finding add-on from service #{service} on app #{app}") do
          addon = resolve_addon(app, service)
          addon_name = addon['name']
        end
        display "Found #{addon_name} (#{addon['plan']['name']}) on #{app}."
      else
        addon_name = addon_name.sub(/^@/, '')
      end

      raise CommandFailed.new("Missing add-on plan") if plan.nil?
      raise CommandFailed.new("Missing add-on name") if addon_name.nil?

      labels = {upgrade: 'Upgrading', downgrade: 'Downgrading'}
      action("#{labels[direction]} #{addon_name} to #{plan}") do
        api.request(
          :body     => json_encode({
            "plan"   => { "name" => plan }
          }),
          :expects  => 200..300,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=3.switzerland" },
          :method   => :patch,
          :path     => "/apps/#{app}/addons/#{addon_name}"
        )
      end
    end

    def resolve_addon(app_name, service_plan_specifier)
      service_name, plan_name = service_plan_specifier.split(':')

      addons = get_addons(:app => app)

      addons.select! do |addon|
        addon['addon_service']['name'] == service_name &&
          (plan_name.nil? || addon['plan']['name'] == plan_name) &&
          # the /apps/:id/addons endpoint can return more than just those owned
          # by the app, so filter:
          addon['app']['name'] == app_name
      end

      case addons.count
      when 1
        return addons[0]
      when 0
        error("No #{service_name} add-on on app #{app_name} found")
      else
        error("Ambiguous add-on identifier #{service_plan_specifier}\nList your add-ons with `heroku addons`")
      end
    end

    def addon_docs_url(addon)
      "https://devcenter.#{heroku.host}/articles/#{addon.split(':').first}"
    end

    def format_price(price)
      if price['cents'] == 0
        'free'
      else
        '$%.2f/%s' % [(price['cents'] / 100.0), price['unit']]
      end
    end
  end
end
