require "heroku/command/base"
require "heroku/helpers/heroku_postgresql"

module Heroku::Command

  # manage add-on resources
  #
  class Addons < Base

    include Heroku::Helpers::HerokuPostgresql

    # addons
    #
    # list installed add-ons
    #
    def index
      validate_arguments!

      addons = api.request(
        :expects  => 200,
        :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
        :method   => :get,
        :path     => "/apps/#{app}/addons"
      ).body

      if addons.empty?
        display("#{app} has no add-ons.")
      else
        styled_header("#{app} Add-on Resources")
        styled_array(addons.map do |addon|
          [
            addon['plan']['name'],
            addon['config_vars'].join(', '),
            "@#{addon['name'].downcase}"
          ]
        end)
      end
    end

    # addons:plans
    #
    # list all available add-on plans
    #
    # --region REGION      # specify a region for add-on plan availability
    #
    #Example:
    #
    # $ heroku addons:plans --region eu
    # === available
    # adept-scale:battleship, corvette...
    # adminium:enterprise, petproject...
    #
    def plans
      addons = heroku.addons(options)
      if addons.empty?
        display "No add-ons available currently"
      else
        partitioned_addons = partition_addons(addons)
        partitioned_addons.each do |key, addons|
          partitioned_addons[key] = format_for_display(addons)
        end
        display_object(partitioned_addons)
      end
    end

    alias_command "addons:list", "addons:plans"

    # addons:attachments
    #
    # list add-on attachments
    #
    def attachments
      begin
        # will raise if no app specified
        attachments = api.request(
          :expects  => 200,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
          :method   => :get,
          :path     => "/apps/#{app}/addon-attachments"
        ).body
        if attachments.empty?
          display("There are no add-on attachments for this app.")
        else
          attachments_by_resource = {}
          attachments.each do |attachment|
            attachments_by_resource["@#{attachment['addon']['name'].downcase}"] ||= []
            attachments_by_resource["@#{attachment['addon']['name'].downcase}"] << attachment['name']
          end
          styled_header("#{app} Add-on Attachments")
          styled_array(attachments_by_resource.map do |resource, attachments|
            [
              attachments.join(', '),
              resource
            ]
          end)
        end
      rescue Heroku::Command::CommandFailed => error
        if error.message =~ /No app specified/
          attachments = api.request(
            :expects  => 200,
            :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
            :method   => :get,
            :path     => "/addon-attachments"
          ).body
          if attachments.empty?
            display("You have no add-on attachments.")
          else
            styled_header("Add-on Attachments")
            styled_array(attachments.map do |attachment|
              [
                attachment['app']['name'],
                attachment['name'],
                "@#{attachment['addon']['name'].downcase}"
              ]
            end.sort)
          end
        else
          raise error
        end
      end
    end

    # addons:create PLAN
    #
    # create an add-on resource
    #
    def create
      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil? || %w{--fork --follow --rollback}.include?(addon)
      config = parse_options(args)

      addon = api.request(
        :body     => json_encode({
          # FIXME: "attachment"  => { "name" => options[:as] },
          "config"      => config,
          # FIXME: "force"       => options[:force],
          "name"        => options[:addon],
          "plan"        => { "name" => addon }
        }),
        :expects  => 201,
        :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
        :method   => :post,
        :path     => "/apps/#{app}/addons"
      ).body

      action("Creating #{addon['name'].downcase}") {}
      action("Adding #{addon['name'].downcase} to #{app}") {}
      action("Setting #{addon['config_vars']} and restarting #{app}") do
        @status = api.get_release(app, 'current').body['name']
      end

      #display resource['provider_data']['message'] unless resource['provider_data']['message'].strip == ""

      display("Use `heroku addons:docs #{addon['plan']['name'].split(':').first}` to view documentation.")
    end

    # addons:add ADDON
    #
    # add add-on attachment from an add-on resource to an app
    #
    # -n, --name NAME         # name for add-on attachment
    # -f, --force             # overwrite existing add-on attachment with same name
    #
    def add
      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil?

      attachment_name = options[:name] || addon.gsub('-','_').upcase
      action("Adding #{addon} as #{attachment_name} to #{app}") do
        api.request(
          :body     => json_encode({
            "app"     => {"name" => app},
            "addon"   => {"name" => addon},
            "confirm" => options[:force],
            "name"    => options[:name]
          }),
          :expects  => 201,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
          :method   => :post,
          :path     => "/addon-attachments"
        ).body
      end
      action("Setting #{attachment_name}_URL and restarting #{app}") do
        @status = api.get_release(app, 'current').body['name']
      end
    end

    # addons:upgrade ADDON PLAN
    #
    # upgrade an existing add-on resource to PLAN
    #
    def upgrade
      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil?

      plan = args.shift
      raise CommandFailed.new("Missing add-on plan") if addon.nil?

      config = parse_options(args)

      action("Upgrading #{addon} to #{plan}") do
        api.request(
          :body     => json_encode({
            "config"      => config,
            "name"        => addon,
            "plan"        => { "name" => plan }
          }),
          :expects  => 200,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
          :method   => :patch,
          :path     => "/apps/#{app}/addons/#{addon}"
        )
      end
    end

    # addons:downgrade ADDON PLAN
    #
    # downgrade an existing add-on resource to PLAN
    #
    def downgrade
      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil?

      plan = args.shift
      raise CommandFailed.new("Missing add-on plan") if addon.nil?

      config = parse_options(args)

      action("Downgrading #{addon} to #{plan}") do
        api.request(
          :body     => json_encode({
            "config"      => config,
            "name"        => addon,
            "plan"        => { "name" => plan }
          }),
          :expects  => 200,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
          :method   => :patch,
          :path     => "/apps/#{app}/addons/#{addon}"
        )
      end
    end

    # addons:remove ATTACHMENT
    #
    # remove add-on attachment from an add-on resource to an app
    #
    def remove
      attachment_name = args.shift
      raise CommandFailed.new("Missing add-on attachment name") if attachment_name.nil?

      addon_attachment = api.request(
        :expects => 200,
        :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
        :method   => :get,
        :path     => "/apps/#{app}/addon-attachments"
      ).body.detect do |attachment|
        attachment['name'] == attachment_name
      end

      unless addon_attachment
        error("Add-on attachment not found")
      end

      action("Removing #{addon_attachment['addon']['name']} as #{attachment_name} from #{app}") do
        api.request(
          :expects  => 200,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
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
      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil?

      return unless confirm_command

      as = options[:as] || addon.gsub('-','_').upcase
      action("Removing #{addon} as #{as} from #{app}") {}
      action("Unsetting #{as}_URL and restarting #{app}") do
        @status = api.get_release(app, 'current').body['name']
      end
      action("Destroying #{addon} on #{app}") do
        api.request(
          :body     => json_encode({
            "force" => options[:force],
          }),
          :expects  => 200,
          :headers  => { "Accept" => "application/vnd.heroku+json; version=edge" },
          :method   => :delete,
          :path     => "/apps/#{app}/addons/#{addon}"
        )
      end
    end

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

      app_addons = api.get_addons(app).body.map {|a| a['name']}
      matches = app_addons.select {|a| a =~ /^#{addon}/}.sort

      case matches.length
      when 0 then
        addon_names = api.get_addons.body.map {|a| a['name']}
        if addon_names.any? {|name| name =~ /^#{addon}/}
          error("Add-on not installed: #{addon}")
        else
          error([
            "`#{addon}` is not a heroku add-on.",
            suggestion(addon, addon_names + addon_names.map {|name| name.split(':').first}.uniq),
            "See `heroku addons:list` for all available add-ons."
          ].compact.join("\n"))
        end
      when 1 then
        addon_to_open = matches.first
        launchy("Opening #{addon_to_open} for #{app}", app_addon_url(addon_to_open))
      else
        error("Ambiguous add-on name: #{addon}\nPerhaps you meant #{matches[0...-1].map {|match| "`#{match}`"}.join(', ')} or `#{matches.last}`.\n")
      end
    end

    private

    def addon_docs_url(addon)
      "https://devcenter.#{heroku.host}/articles/#{addon.split(':').first}"
    end

    def app_addon_url(addon)
      "https://addons-sso.heroku.com/apps/#{app}/addons/#{addon}"
    end

    def partition_addons(addons)
      addons.group_by{ |a| (a["state"] == "public" ? "available" : a["state"]) }
    end

    def format_for_display(addons)
      grouped = addons.inject({}) do |base, addon|
        group, short = addon['name'].split(':')
        base[group] ||= []
        base[group] << addon.merge('short' => short)
        base
      end
      grouped.keys.sort.map do |name|
        addons = grouped[name]
        row = name.dup
        if addons.any? { |a| a['short'] }
          row << ':'
          size = row.size
          stop = false
          row << addons.map { |a| a['short'] }.compact.sort.map do |short|
            size += short.size
            if size < 31
              short
            else
              stop = true
              nil
            end
          end.compact.join(', ')
          row << '...' if stop
        end
        row
      end
    end

    def addon_run
      response = yield

      if response
        price = "(#{ response['price'] })" if response['price']

        if response['message'] =~ /(Attached as [A-Z0-9_]+)\n(.*)/m
          attachment = $1
          message = $2
        else
          attachment = nil
          message = response['message']
        end

        begin
          release = api.get_release(app, 'current').body
          release = release['name']
        rescue Heroku::API::Errors::Error
          release = nil
        end
      end

      status [ release, price ].compact.join(' ')
      { :attachment => attachment, :message => message }
    rescue RestClient::ResourceNotFound => e
      error Heroku::Command.extract_error(e.http_body) {
        e.http_body =~ /^([\w\s]+ not found).?$/ ? $1 : "Resource not found"
      }
    rescue RestClient::Locked => ex
      raise
    rescue RestClient::RequestFailed => e
      error Heroku::Command.extract_error(e.http_body)
    end

    def configure_addon(label, &install_or_upgrade)
      addon = args.shift
      raise CommandFailed.new("Missing add-on name") if addon.nil? || %w{--fork --follow --rollback}.include?(addon)

      config = parse_options(args)
      addon_name, plan = addon.split(':')

      # For Heroku Postgres, if no plan is specified with fork/follow/rollback,
      # default to the plan of the current postgresql plan
      if addon_name =~ /heroku-postgresql/ then
        hpg_flag  = %w{rollback fork follow}.select {|flag| config.keys.include? flag}.first
        if plan.nil? &&  config[hpg_flag] =~ /^postgres:\/\// then
          raise CommandFailed.new("Cross application database Forking/Following requires you specify a plan type")
        elsif (hpg_flag && plan.nil?) then
          resolver = Resolver.new(app, api)
          addon = addon + ':' + resolver.resolve(config[hpg_flag]).plan
        end
      end

      config.merge!(:confirm => app) if app == options[:confirm]
      raise CommandFailed.new("Unexpected arguments: #{args.join(' ')}") unless args.empty?

      hpg_translate_db_opts_to_urls(addon, config)

      messages = nil
      action("#{label} #{addon} on #{app}") do
        messages = addon_run { install_or_upgrade.call(addon, config) }
      end
      display(messages[:attachment]) unless messages[:attachment].to_s.strip == ""
      display(messages[:message]) unless messages[:message].to_s.strip == ""

      display("Use `heroku addons:docs #{addon_name}` to view documentation.")
    end

    #this will clean up when we officially deprecate
    def parse_options(args)
      config = {}
      deprecated_args = []
      flag = /^--/

      args.size.times do
        break if args.empty?
        peek = args.first
        next unless peek && (peek.match(flag) || peek.match(/=/))
        arg  = args.shift
        peek = args.first
        key  = arg
        if key.match(/=/)
          deprecated_args << key unless key.match(flag)
          key, value = key.split('=', 2)
        elsif peek.nil? || peek.match(flag)
          value = true
        else
          value = args.shift
        end
        value = true if value == 'true'
        config[key.sub(flag, '')] = value

        if !deprecated_args.empty?
          out_string = deprecated_args.map{|a| "--#{a}"}.join(' ')
          display("Warning: non-unix style params have been deprecated, use #{out_string} instead")
        end
      end

      config
    end

  end
end
