module Verse
  module Model
    module Record
      module ClassMethods
        attr_accessor :record_root_path, :repositories_root_path, :primary_key

        attr_reader :fields, :relations

        # get or set the type of the record
        # if not set, it will be infered from the class name
        # e.g. UserRecord => users
        #
        def type(value = nil)
          if value
            @type = value
          else
            @type ||= infer_record_type_by_class_name
          end
        end

        def relation(name, array: false, &block)
          @relations[name] = Relation.new(name, array: array, &block)

          define_method(name) do
            if array
              @relations[name.to_sym]
            else
              @relations[name.to_sym]&.first
            end
          end
        end

        # This is a belong to relation.
        #
        # This allow to avoid N+1 query.
        #
        # we will setup a macro belongs_to to repeat this code but for now we run out of time !
        # this is a good example of creating a custom relation
        # relation name, arity: :one|:many do |collection, auth_context, sub_included|
        #
        # - collection => current collectio of object having the relationship included
        # - auth_context
        # - sub_included => the case we have a tree of inclusion, this give the sub-included elements
        # (e.g. if we call contract and include 'property.units',
        #       the code is called on 'property' with sub_included 'units' )
        # returns:
        # an array with the collection of item fetched, and the indexing lambda method
        # used to detect and rebind the elements.
        #
        # @param relation_name [Symbol] the name of the relation
        # @param primary_key [Symbol] the primary key of the relation
        # @param foreign_key [Symbol] the foreign key of the relation
        # @param repository [String] the repository of the relation
        # @param serializer [String] the serializer of the relation
        # @param opts [Hash] the options of the relation
        #
        # @option opts [Proc] :if a proc to check if the relation should be included.
        #                     Used for example to include a relation only if a condition is met (polymorphism).
        def belongs_to(relation_name, primary_key: nil, foreign_key: nil, repository: nil, serializer: nil, **opts)
          foreign_key ||= "#{relation_name}_id"
          repository ||= "App::Model::#{relation_name.to_s.classify}Repository"

          relation relation_name, array: false do |collection, auth_context, sub_included|
            repository = repository.constantize if repository.is_a?(String)
            serializer ||= repository.model_class
            serializer = serializer.constantize if serializer.is_a?(String)
            primary_key ||= serializer.primary_key

            included = repository.new(
              auth_context
            ).index(
              filters: {
                "#{primary_key}__in" => collection.map{ |x|
                  condition = opts[:if]
                  next if condition && !condition.call(x)

                  # check key_type using model structure
                  pkey_info = serializer.fields.fetch(primary_key){ raise "primary key name not found: `#{primary_key}`" }

                  Verse::Model::Serializer::Converter.convert(x[foreign_key.to_sym], pkey_info[:type])
                }.compact
              },
              included: sub_included,
              serializer: serializer
            )

            [
              included, # the list we store
              lambda do |inc_record|
                inc_record.fetch(primary_key.to_s) do
                  raise "[belongs_to #{name}:#{relation_name}] primary key not found: #{primary_key}"
                end.to_s
              end, # Create index key
              lambda do |record| # Acces index key
                record.fetch(foreign_key.to_s) do
                  raise "[belongs_to #{name}:#{relation_name}] foreign key not found: #{foreign_key}"
                end.to_s
              end
            ]
          end
        end

        def has_many(relation_name, primary_key: nil, foreign_key: nil, repository: nil, serializer: nil, **opts)
          foreign_key ||= "#{type.singularize}_id"

          repository ||= "App::Model::#{relation_name.to_s.classify}Repository"

          relation relation_name, array: true do |collection, auth_context, sub_included|
            repository = repository.constantize if repository.is_a?(String)
            serializer ||= repository.model_class
            serializer = serializer.constantize if serializer.is_a?(String)
            primary_key ||= serializer.primary_key

            included = repository.new(
              auth_context
            ).index(
              filters: {
                "#{foreign_key}__in" => collection.map{ |x|
                  condition = opts[:if]
                  next if condition && !condition.call(x)

                  # check key_type using model structure
                  pkey_info = serializer.fields[primary_key]

                  Verse::Model::Serializer::Converter.convert(x[primary_key.to_sym], pkey_info[:type])
                }.compact
              },
              included: sub_included,
              serializer: serializer
            )

            [
              included,
              lambda do |inc_record|
                inc_record.fetch(foreign_key.to_s) do
                  raise "[belongs_to #{name}:#{relation_name}] primary key not found: #{foreign_key}"
                end.to_s
              end, # Create index key
              lambda do |record| # Acces index key
                record.fetch(primary_key.to_s) do
                  raise "[belongs_to #{name}:#{relation_name}] foreign key not found: #{primary_key}"
                end.to_s
              end
            ]
          end
        end

        def has_one(relation_name, primary_key: nil, foreign_key: nil, repository: nil, **opts)
          foreign_key ||= "#{type.singularize}_id"

          repository ||= "App::Model::#{relation_name.to_s.classify}Repository"

          relation relation_name, array: false do |collection, auth_context, sub_included|
            repository = repository.constantize if repository.is_a?(String)
            primary_key ||= repository.model_class.primary_key

            included = repository.new(
              auth_context
            ).index(
              filters: {
                "#{foreign_key}__in" => collection.map{ |x|
                  condition = opts[:if]
                  next if condition && !condition.call(x)

                  # check key_type using model structure
                  pkey_info = repository.model_class.fields[primary_key]

                  Verse::Model::Serializer::Converter.convert(x[primary_key.to_sym], pkey_info[:type])
                }.compact
              },
              included: sub_included
            )

            [
              included,
              lambda do |inc_record|
                inc_record.fetch(foreign_key.to_s) do
                  raise "[belongs_to #{name}:#{relation_name}] primary key not found: #{foreign_key}"
                end.to_s
              end, # Create index key
              lambda do |record| # Acces index key
                record.fetch(primary_key.to_s) do
                  raise "[belongs_to #{name}:#{relation_name}] foreign key not found: #{primary_key}"
                end.to_s
              end
            ]
          end
        end

        def field(name, type = :any, key: nil, primary: false, &block)
          key ||= name.to_sym
          @fields[key] = { name: name, type: type }

          @primary_key = key if primary

          block ||= -> { @fields[key] }

          define_method(name, &block)
        end

        def enum(name, values, prefix: nil)
          values.each do |value|
            method_name = prefix ? "#{prefix}_#{value}" : value

            raise "enum: redefinition of method #{method_name}?" if respond_to?(:"#{method_name}?")

            define_method(:"#{method_name}?") do
              send(name.to_sym) == value
            end
          end
        end

        protected

        def infer_record_type_by_class_name
          regexp = /(::)?([a-zA-Z0-9_]+)$/
          Verse.inflector.pluralize(
            name[regexp].gsub(regexp, "\\2").gsub(/(.?)Record$/, "\\1").underscore
          )
        end

        def infer_serializer_for(name)
          klass = name.to_s.singularize.classify

          if serializer_root_path == ""
            klass.to_s.classify
          else
            [record_root_path, "#{klass}"].join("::").classify
          end
        end
      end
    end
  end
end
