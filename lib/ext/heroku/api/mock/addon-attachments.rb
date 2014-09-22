module Heroku
  class API
    module Mock

      ADDON_ATTACHMENT_NOT_FOUND = { :body => 'Add-on attachment not found.', :status => 404 }

      # stub GET /apps/:app/addon-attachments
      Excon.stub(:expects => 200, :method => :get, :path => %r{^/apps/([^/]+)/addon-attachments$}) do |params|
        request_params, mock_data = parse_stub_params(params)
        app_name, _ = request_params[:captures][:path]

        with_mock_app(mock_data, app_name) do |app|
          {
            :body   => MultiJson.dump(mock_data[:addon_attachments][app_name] || []),
            :status => 200
          }
        end
      end

      # stub GET /addon-attachments
      Excon.stub(:expects => 200, :method => :get, :path => %r{^/addon-attachments$}) do |params|
        request_params, mock_data = parse_stub_params(params)

        {
          :body   => MultiJson.dump(mock_data[:addon_attachments].values.flatten),
          :status => 200
        }
      end

      # stub DELETE /apps/:app/addon-attachments/:attachment
      Excon.stub(:expects => 200, :method => :delete, :path => %r{^/apps/([^/]+)/addon-attachments/([^/]+)$}) do |params|
        request_params, mock_data = parse_stub_params(params)
        app_name, attachment_name, _ = request_params[:captures][:path]

        with_mock_app(mock_data, app_name) do |app|
          if attachment_data = mock_data[:addon_attachments][app].detect {|data| data['name'] == attachment_name}
            mock_data[:config_vars][app].delete("#{attachment_name}_URL")
            add_mock_release(mock_data, app, {'descr' => "Add-on resource remove #{attachment_name}"})
            mock_data[:addon_attachments][app].delete(attachment_data)

            {
              :status => 200
            }
          else
            ADDON_ATTACHMENT_NOT_FOUND
          end
        end
      end

      # stub POST /addon-attachments
      Excon.stub(:expects => 200, :method => :post, :path => %r{^/addon-attachments$}) do |params|
        request_params, mock_data = parse_stub_params(params)

        with_mock_app(request_params[:body]['app']['name']) do |app|
          attachment_name = request_params[:body]['addon-attachment'] && request_params[:body]['addon-attachment']['name'] || resource.gsub('-','_').upcase
          resource = get_mock_resource(request_params[:body]['resource']['name'].split('/',2).last)

          add_mock_addon_attachment(mock_data, app, resource, { 'name' => attachment_name })

          mock_data[:config_vars][app['name']]["#{attachment_name}_URL"] = "@#{addon}/#{resource}"
          add_mock_release(mock_data, app['name'], {'descr' => "Add-on resource add #{addon}/#{resource}"})

          {
            :body   => MultiJson.dump(attachment_data),
            :status => 200
          }
        end
      end

    end
  end
end
