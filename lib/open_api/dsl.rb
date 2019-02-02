# frozen_string_literal: true

require 'open_api/dsl/api'
require 'open_api/dsl/components'

module OpenApi
  module DSL
    extend ActiveSupport::Concern
    
    class_methods do
      def oas
        @oas ||= { doc: { }, dry_blocks: { }, apis: { }, route_base: try(:controller_path),
                   tag_name: try(:controller_name)&.camelize }
      end

      def route_base path
        oas[:route_base] = path
        oas[:tag_name] = path.split('/').last.camelize
      end

      # APIs will be grouped by tags.
      def doc_tag name: nil, **tag_info #  description: ..., externalDocs: ...
        oas[:doc][:tag] = { name: name || oas[:tag_name], **tag_info }
      end

      def components &block
        doc_tag if oas[:doc].blank?
        (current_doc = Components.new).instance_exec(&block)
        current_doc.process_objs
        (oas[:doc][:components] ||= { }).deep_merge!(current_doc)
      end

      def api action, summary = '', id: nil, tag: nil, http: nil, &block
        doc_tag if oas[:doc].blank?
        action_path = "#{oas[:route_base]}##{action}"
        routes = Generator.routes_list[oas[:route_base]]
                     &.select { |api| api[:action_path][/^#{action_path}$/].present? }
        return Tip.no_route(action_path) if routes.blank?

        tag = tag || oas[:doc][:tag][:name]
        api = Api.new(action_path)
                  .merge!(summary: summary, tags: [tag], operationId: id || "#{tag}_#{action.to_s.camelize}")
        [action, tag, :all].each { |key| api.dry_blocks.concat(oas[:dry_blocks][key] || [ ]) }
        api.instance_exec(&block) if block_given?
        api.process_objs
        api.delete_if { |_, v| v.blank? }
        _set_apis(api, routes, http)
      end

      def api_dry action_or_tags = :all, &block
        Array(action_or_tags).each { |a| (oas[:dry_blocks][a] ||= [ ]) << block }
      end

      def _set_apis(api, routes, http)
        routes.each do |route|
          path = oas[:apis][route[:path]] ||= { }
          (http || route[:http_verb]).split('|').each { |verb| path[verb] = api }
        end
        api
      end
    end
  end
end
