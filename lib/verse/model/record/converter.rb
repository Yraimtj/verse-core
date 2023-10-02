# frozen_string_literal: true

module Verse
  module Model
    module Record
      module Converter
        extend self

        def convert(value, type)
          return value if value.nil? || type.nil?

          conv = @converters.fetch(type) { raise "unsupported field type: `#{type}`" }

          conv&.call(value)
        end

        def add_converter(type, &block)
          @converters ||= {}
          @converters[type] = block
        end

        add_converter(:any){ |obj| obj }

        add_converter(:string, &:to_s)
        add_converter(String, &:to_s)

        add_converter(:uuid,   &:to_s)

        add_converter(:int,    &:to_i)
        add_converter(Integer, &:to_i)

        add_converter :json do |obj|
          case obj
          when Hash
            obj
          when String
            JSON.parse(obj)
          else
            raise "cannot convert from `#{obj.class}`"
          end
        end
      end
    end
  end
end
