require("#{File.dirname(__FILE__)}/mock/addon-attachments")
require("#{File.dirname(__FILE__)}/mock/resources")

module Heroku
  class API
    module Mock

      if ENV['HEROKU_MOCK']
        Excon.defaults[:mock] = true
        ENV['HEROKU_CLOUD'] = "mock" # skip org stuff
      end

      @mock_data = nil

      def self.cached_mock_data
        @mock_data ||= begin
          mock_data = if File.exists?(File.expand_path("~/.heroku/cached_mock_data"))
            Marshal.load(File.read(File.expand_path("~/.heroku/cached_mock_data")))
          else
            {}
          end
          # setup expectations without default procs so it can be marshalled
          mock_data[@api_key] ||= {
            :addons             => {},
            :apps               => [],
            :addon_attachments  => {},
            :collaborators      => {},
            :config_vars        => {},
            :domains            => {},
            :keys               => [],
            :maintenance_mode   => [],
            :ps                 => {},
            :releases           => {},
            :resources          => [],
            :user               => {}
          }
          mock_data
        end
      end

      def self.parse_stub_params(params)
        mock_data = nil

        if params[:headers].has_key?('Authorization')
          @api_key = Base64.decode64(params[:headers]['Authorization'].split(' ').last).split(':').last

          parsed = params.dup
          begin # try to JSON decode
            parsed[:body] &&= MultiJson.load(parsed[:body])
          rescue # else leave as is
          end

          mock_data = cached_mock_data[@api_key]
        end

        [parsed, mock_data]
      end

      #Excon.stub(
        #{:expects => 200, :method => :get, :path => "/v1/user/info"},
        #{:status => 200}
      #)

      def self.add_mock_addon_attachmont(mock_data, app, addon, attachment_data)
        attachment_name = attachment_data['name'] || addon['name'].split(':').first
        mock_data[:addon_attachments][app] ||= []
        mock_data[:addon_attachments][app] << {
          'addon'       => {
            'id'    => addon['id'],
            'name'  => addon['name']
          },
          'app'         => {
            'id'    => app['id'],
            'name'  => app['name']
          },
          'created_at'  => timestamp,
          'id'          => uuid,
          'name'        => attachment_name,
          'updated_at'  => timestamp
        }.merge(attachment_data)
        mock_data[:config_vars][app['name']]["#{attachment_name.gsub('-','_').upcase}_URL"] = "@#{addon['name']}"
      end

      def self.get_mock_app_attachment(mock_data, app, attachment)
        mock_data[:addon_attachments][app].detect {|attachment_data| attachment_data['name'] == attachment}
      end

      def self.get_mock_resource(mock_data, resource)
        mock_data[:resource].detect {|resource_data| resource_data['name'] == resource}
      end

      def self.addon_name(addon_service)
        colors = %w(
          amber aqua black blue bronze brown charcoal crimson cyan gray
          green indigo ivory jade maroon mauve navy olive onyx orange
          pink purple red rose teal violet white yellow
        )
        elements = %w(
          hydrogen helium lithium beryllium boron carbon nitrogen flourine neon sodium
          magnesium aluminium silicon phosphorus sulfur chlorine argon potassium calcium scandium
          titanium vanadium chromium manganese iron cobalt nickel copper zinc gallium
          germanium arsenic
        )

        addon_name = "#{addon_service}/"
        addon_name << [
          colors.sample,
          elements.sample,
          [rand(10), rand(10), rand(10), rand(10)].map {|x| x.to_s}.join
        ].join("-")

          addon_name
      end

      def self.uuid
        uuid = ''
        8.times   { uuid << rand(16).to_s(16) }
        3.times   { 4.times { uuid << rand(16).to_s(16) } }
        12.times  { uuid << rand(16).to_s(16) }
        uuid
      end

    end
  end
end

at_exit do
  File.write(
    File.expand_path("~/.heroku/cached_mock_data"),
    Marshal.dump(Heroku::API::Mock.cached_mock_data)
  )
end
