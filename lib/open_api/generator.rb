require 'open_api/config'

module OpenApi
  module Generator
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def generate_docs(api_name = nil)
        Dir['./app/controllers/**/*.rb'].each { |file| require file }
        # TODO: _doc should be configured
        Dir['./app/**/*_doc.rb'].each { |file| require file }
        if api_name.present?
          [{ api_name => generate_doc(api_name) }]
        else
          Config.docs.keys.map { |api_key| { api_key => generate_doc(api_key) } }.reduce({ }, :merge)
        end
      end

      def generate_doc(api_name)
        settings = Config.docs[api_name]
        doc = { openapi: '3.0.0' }.merge(settings.slice :info, :servers).merge(
                security: settings[:global_security], tags: [ ], paths: { },
                components: {
                    securitySchemes: settings[:global_security_schemes],
                    schemas: { }
                }
              )

        settings[:root_controller].descendants.each do |ctrl|
          ctrl_infos = ctrl.instance_variable_get('@_ctrl_infos')
          next if ctrl_infos.nil?
          doc[:paths].merge! ctrl.instance_variable_get('@_api_infos') || { }
          doc[:tags] << ctrl_infos[:tag]
          doc[:components].merge! ctrl_infos[:components] || { }
        end
        doc[:components].delete_if { |_, v| v.blank? }
        doc[:tags]  = doc[:tags].sort { |a, b| a[:name] <=> b[:name] }
        doc[:paths] = doc[:paths].sort.to_h

        ($open_apis ||= { })[api_name] ||=
            ActiveSupport::HashWithIndifferentAccess.new(doc.delete_if { |_, v| v.blank? })
      end

      def write_docs(generate_files: true)
        docs = generate_docs
        return unless generate_files
        output_path = Config.file_output_path
        FileUtils.mkdir_p output_path
        max_length = docs.keys.map(&:size).sort.last
        puts '[ZRO] * * * * * *'
        docs.each do |doc_name, doc|
          puts "[ZRO] `%#{max_length}s.json` has been generated." % "#{doc_name}"
          File.open("#{output_path}/#{doc_name}.json", 'w') { |file| file.write JSON.pretty_generate doc }
        end
        # pp $open_apis
      end
    end

    def self.generate_builder_file(action_path, builder)
      return unless Config.generate_jbuilder_file
      return if builder.nil?

      path, action = action_path.split('#')
      dir_path = "app/views/#{path}"
      FileUtils.mkdir_p dir_path
      file_path = "#{dir_path}/#{action}.json.jbuilder"

      unless !Config.overwrite_jbuilder_file && File::exists?(file_path)
        File.open(file_path, 'w') { |file| file.write Config.jbuilder_templates[builder] }
        puts "[ZRO] JBuilder file has been generated: #{path}/#{action}"
      end
    end

    def self.generate_routes_list
      # ref https://github.com/rails/rails/blob/master/railties/lib/rails/tasks/routes.rake
      require './config/routes'
      all_routes = Rails.application.routes.routes
      require 'action_dispatch/routing/inspector'
      inspector = ActionDispatch::Routing::RoutesInspector.new(all_routes)

      inspector.format(ActionDispatch::Routing::ConsoleFormatter.new, nil).split("\n").drop(1).map do |line|
        infos = line.match(/[A-Z].*/).to_s.split(' ') # => [GET, /api/v1/examples/:id, api/v1/examples#index]
        {
            http_verb: infos[0].downcase, # => "get"
            path: infos[1][0..-11].split('/').map do |item|
                    item[':'] ? "{#{item[1..-1]}}" : item
                  end.join('/'),          # => "/api/v1/examples/{id}"
            action_path: infos[2]         # => "api/v1/examples#index"
        } rescue next
      end.compact.group_by {|api| api[:action_path].split('#').first } # => { "api/v1/examples" => [..] }, group by paths
    end

    def self.get_actions_by_ctrl_path(path)
      @routes_list ||= generate_routes_list
      @routes_list[path]&.map do |action_info|
        action_info[:action_path].split('#').last
      end
    end
  end
end
