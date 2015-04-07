require "ext/heroku/helpers/addons/api"

module Heroku::Helpers
  module Addons
    module Resolve
      include Heroku::Helpers::Addons::API

      UUID         = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      ATTACHMENT   = /^(?:([a-z][a-z0-9-]+)::)?([A-Z][A-Z0-9_]+)$/
      RESOURCE     = /^@?([a-z][a-z0-9-]+)$/
      SERVICE_PLAN = /^(?:([a-z0-9_-]+):)?([a-z0-9_-]+)$/ # service / service:plan

      # Try to find an attachment record given some String identifier.
      #
      # Always returns an array of 0 or more results.
      def resolve_attachment(identifier)
        case identifier
        when UUID
          [get_attachment(identifier)]
        when ATTACHMENT
          app  = $1 || self.app # "app::..." or current app
          name = $2

          attachment = begin
            get_attachment(name, :app => app)
          rescue Heroku::API::Errors::NotFound
          end

          return [attachment] if attachment

          get_attachments(:app => app).select { |att| att["name"][name] }
        else
          []
        end
      end

      # Try to find an attachment record given some String identifier.
      #
      # Returns a single result or exits with an error.
      def resolve_attachment!(identifier)
        results = resolve_attachment(identifier)

        case results.count
        when 1
          results[0]
        when 0
          error("Can not find attachment with #{identifier.inspect}")
        else
          app = results.first['app']['name']
          error("Multiple attachments on #{app} match #{identifier.inspect}.\n" +
                "Did you mean one of:\n\n" +
                results.map { |att| "- #{att['name']}" }.join("\n"))
        end
      end

      # Resolve unique add-on or return error using:
      #
      # * add-on resource name (@my-db / my-db)
      # * add-on resource UUID
      # * attachment name (other-app::ATTACHMENT / ATTACHMENT on current app)
      # * service name
      # * service:plan name
      #
      # Always returns an Array with zero or matches.
      def resolve_addon(identifier)
        case identifier
        when UUID
          return [get_addon(identifier)].compact
        when ATTACHMENT
          matches = resolve_attachment(identifier)
          matches.
            map { |att| att['addon']['id'] }.
            uniq.
            map { |addon_id| get_addon(addon_id) }
        else # try both resource and service identifiers, because they look similar
          if identifier =~ RESOURCE
            name = $1

            addon = begin
              get_addon(name)
            rescue Heroku::API::Errors::Forbidden
              # treat permission error as no match because there might exist a
              # resource on someone else's app that has a name which
              # corresponds to a service name that we wish to check below (e.g.
              # "memcachier")
            end

            return [addon] if addon
          end

          if identifier =~ SERVICE_PLAN
            service_name, plan_name = *[$1, $2].compact
            full_plan_name = [service_name, plan_name].join(':') if plan_name

            addons = get_addons(:app => app).select do |addon|
              addon['addon_service']['name'] == service_name &&
                [nil, addon['plan']['name']].include?(full_plan_name) &&
                # the /apps/:id/addons endpoint can return more than just those owned
                # by the app, so filter:
                addon['app']['name'] == app
            end

            return addons
          end

          []
        end
      end

      # Returns a single result or exits with an error.
      def resolve_addon!(identifier)
        results = resolve_addon(identifier)

        case results.count
        when 1
          results[0]
        when 0
          error("Can not find add-on with #{identifier.inspect}")
        else
          error("Multiple add-ons match #{identifier.inspect}.\n" +
                "Use the name of add-on resource:\n\n" +
                results.map { |a| "- #{a['name']} (#{a['plan']['name']})" }.join("\n"))
        end
      end
    end
  end
end
