module Heroku
  class API
    module Mock

      # stub DELETE /resources/:resource
      Excon.stub(:expects => 200, :method => :delete, :path => %r{^/resources/([^/]+)$}) do |params|
        request_params, mock_data = parse_stub_params(params)
        resource, _ = request_params[:captures][:path]

        # FIXME: should ensure it exists or else throw not found

        resource_data = mock_data[:resources].detect {|data| data['name'] == resource}
        mock_data[:resources].delete(resource_data)

        mock_data[:attachments].each do |app, app_attachments|
          app_attachments.select {|attachment_data| attachment_data['resource']['name'] == resource}.each do |attachment_data|
            mock_data[:config_vars][app].delete("#{attachment_data['name']}_URL")
            add_mock_release(mock_data, app, {'descr' => "Add-on resource remove #{attachment_data['name']}"})
            app_attachments.delete(attachment_data)
          end
        end

        {
          :body   => MultiJson.dump(resource_data),
          :status => 200
        }
      end

      # stub POST /resources
      Excon.stub(:expects => 200, :method => :post, :path => '/resources') do |params|
        request_params, mock_data = parse_stub_params(params)
        app = request_params[:body]['app']['name']

        with_mock_app(mock_data, app) do
          resource = request_params[:body]['name'] || "generated-name-#{rand(999)}"
          addon = request_params[:body]['addon']['name']

          # FIXME: should check if resource already exists, check force and fallback if appropriate

          resource_data = {
            'addon' => {
              'id'   => '',
              'name' => addon
            },
            'name'  => resource
          }
          mock_data[:resources] << resource_data

          attachment = request_params[:body]['attachment']['name'] || resource.gsub('-','_').upcase
          mock_data[:config_vars][app]["#{attachment}_URL"] = "@#{addon}/#{resource}"

          mock_data[:attachments][app] ||= []
          mock_data[:attachments][app] << {
            'resource' => {
              'name' => resource
            },
            'name' => attachment
          }

          add_mock_release(mock_data, app, {'descr' => "Add-on resource add #{addon}/#{resource}"})

          {
            :body   => MultiJson.dump(resource_data),
            :status => 200
          }
        end
      end


      # stub PUT /resources

    end
  end
end
