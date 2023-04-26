# frozen_string_literal: true

require_relative "./scope_dsl"

module Verse
  module Auth
    # object describing authorizations
    class Context
      @roles = {
        system: ["*.*.*"],
        anonymous: []
      }

      def self.[]=(name, rights)
        @roles[name] = rights
      end

      def self.[](name)
        new(@roles.fetch(name))
      end

      attr_reader :custom_scopes, :metadata

      # Use this class to mock an auth context for testing purposes.
      #
      # @param rights [Array] The list of rights allowed for this context.
      #        Follow the format `["resource.action.scope"]`.
      #        Wildcard `*` for all resources, actions or scopes.
      #        Wildcard `?` for custom scopes.
      # @param role [String] simulate a role name
      # @param id [Integer] simulate a user id
      #
      # Example:
      #
      # ```
      # Verse::Auth::Context.new(["users.read.*", "users.write.?"])
      # ```
      #
      def initialize(rights = ["*.*.*"], custom_scopes: {}, metadata: {})
        super()

        @custom_scopes = custom_scopes.transform_keys(&:to_sym)
        @metadata = metadata

        generate_rights(rights)
      end

      # Check whether we can perform an action on a resource.
      # Use a block to define the scoped resource for given action.
      # Example:
      #
      # ```
      #   auth_context.can!(:read, :user) do |scope|
      #     scope.all?{ table }                               # Give access to all users
      #     scope.any?{ |id| table.where(id: id) }            # Give access to a specific user
      #     scope.me?{ table.where(id: auth_context.user_id)} # Give access to the current user
      #     scope.else?(&:reject!) # Reject all other cases. This is the default behavior if a scope is not found.
      #   end
      # ```
      #
      # Only the block matching the scope of the current context will be executed.
      # If no block is matching the scope, then the else? block will be executed.
      # If no else? block is defined, then the action will be rejected.
      #
      # @param action [Symbol] the action on the resource we want to check
      # @param resource [Symbol] the resource we want to check
      # @param block [Proc] the block used to define the scope.
      #
      # @return [Object] the result of the selected block
      #
      def can!(action, resource, &block)
        mark_as_checked!

        result = ScopeDSL.new(self, action, resource, &block).result

        reject! if result.nil?

        result
      end

      def can?(action, resource)
        resource = resource.to_s
        action = action.to_s

        scope = @rights.find{ |(res, act, _)| res =~ resource && act =~ action }

        (scope && scope[2]) || false
      end

      # Confirm that the security context has been checked.
      # This method is used to bypass security check, or allow
      # free access to a resource.
      def mark_as_checked!
        @checked = true
        self
      end

      alias_method :no_authorization!, :mark_as_checked!

      # @return [Boolean] whether the security context has been checked
      def checked?
        !!@checked
      end

      # Raise an error if the security context is not met
      # @raise [Verse::Auth::Context::UnauthorizedError]
      def reject!
        raise Verse::Error::Unauthorized, "unauthorized"
      end

      # Check custom scope for a specific resource
      # @param resource [Symbol] the resource we want to check
      # @return [Object] the custom data associated with the resource
      def [](resource)
        @custom_scopes[resource.to_sym]
      end

      protected def generate_rights(rights)
        @rights = rights.map{ |x|
          resource, action, scope = x.split(/\./)

          Verse::Util::Assertion.assert(resource && action && scope) do
            "string must be in the format `[resource].[action].[scope]`"
          end

          resource_regexp = Regexp.new(resource.gsub("*", ".*"))
          action_regexp = Regexp.new(action.gsub("*", ".*"))
          scope = scope.gsub("*", "all").gsub(/^\?$/, "custom")

          if scope == "custom"
            raise "custom scope `?` not allowed for wildcard resources" if resource == "*"

            unless self[resource.to_sym]
              raise "custom scope `?` found for resource `#{resource}` but no custom data was given"
            end
          end

          [resource_regexp, action_regexp, scope.to_sym]
        }
      end
    end
  end
end
