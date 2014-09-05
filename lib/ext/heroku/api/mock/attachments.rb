module Heroku
  class API
    module Mock

      # stub DELETE /apps/:app/attachments/:attachment
      Excon.stub(:expects => 200, :method => :delete, :path => %r{^/apps/([^/]+)/attachments/([^/]+)$}) do |params|
        request_params, mock_data = parse_stub_params(params)
        app, attachment, _ = request_params[:captures][:path]

        with_mock_app(mock_data, app) do
          # FIXME: should ensure it exists or else throw not found

          attachment_data = mock_data[:attachments][app].detect {|data| data['name'] == attachment}

          mock_data[:config_vars][app].delete("#{attachment_data['name']}_URL")
          add_mock_release(mock_data, app, {'descr' => "Add-on resource remove #{attachment_data['name']}"})
          mock_data[:attachments][app].delete(attachment_data)
        end
      end

      # stub POST /apps/:app/attachments
      Excon.stub(:expects => 200, :method => :post, :path => %r{^/apps/([^/]+)/attachments$}) do |params|
        request_params, mock_data = parse_stub_params(params)
        app, _ = request_params[:captures][:path]

        attachment = request_params[:body]['name'] || resource.gsub('-','_').upcase
        resource = request_params[:body]['resource']['name'].split('/',2).last
        addon = mock_data[:resources].detect {|resource_data| resource_data['name'] == resource}['addon']['name'].split(':',2).first

        mock_data[:attachments][app] ||= []
        attachment_data = {
          'resource' => {
            'name' => request_params[:body]['resource']['name']
          },
          'name' => attachment
        }
        mock_data[:attachments][app] << attachment_data

        mock_data[:config_vars][app]["#{attachment}_URL"] = "@#{addon}/#{resource}"
        add_mock_release(mock_data, app, {'descr' => "Add-on resource add #{addon}/#{resource}"})

        {
          :body   => MultiJson.dump(attachment_data),
          :status => 200
        }
      end

    end
  end
end
