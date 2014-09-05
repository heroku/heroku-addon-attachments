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
            :addons           => {},
            :apps             => [],
            :attachments      => {},
            :collaborators    => {},
            :config_vars      => {},
            :domains          => {},
            :keys             => [],
            :maintenance_mode => [],
            :ps               => {},
            :releases         => {},
            :resources        => [],
            :user             => {}
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

      def self.get_mock_app_attachment(mock_data, app, attachment)
        mock_data[:attachments][app].detect {|attachment_data| attachment_data['name'] == attachment}
      end

      def self.get_mock_resource(mock_data, resource)
        mock_data[:resource].detect {|resource_data| resource_data['name'] == resource}
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
