require "fluent/config/types"
require "fluent/plugin/filter"
require "fluent/plugin/mixin/mutate_event"

module Fluent
  module Plugin
    class MutateFilter < Fluent::Plugin::Filter
      Fluent::Plugin.register_filter("mutate", self)

      # Treat periods as nested field names
      config_param :expand_nesting, :bool, default: true

      # Remove any empty hashes or arrays
      config_param :prune_empty,    :bool, default: true

      # Define mutators
      config_section :mutate, param_name: :mutators, multi: true do
        config_param :@type, :string, default: nil
      end

      def initialize
        super

        @actions = []
      end

      # Initialize attributes and parameters
      # @since 0.1.0
      # @return [NilClass]
      def configure(conf)
        super

        @mutators.each do |mutator|
          section = mutator.corresponding_config_element

          type = section["@type"]
          data = section.to_h.tap { |h| h.delete("@type") }

          unless type
            raise Fluent::ConfigError, "Missing '@type' parameter in <mutator>"
          end

          unless self.respond_to?(type.to_sym, :include_private)
            raise Fluent::ConfigError, "Invalid mutator #{type}"
          end

          # Iterate over section keys to remove access warnings, we'll be
          # iterating over the data which has been dumped to array later
          data.keys.each do |key|
            section.has_key?(key)
          end

          # Validate config section types
          case type
            when "convert"
              data.each do |key, value|
                unless VALID_CONVERSIONS.include?(value)
                  raise Fluent::ConfigError, "mutate #{type} action " +
                        "received an invalid type for #{key}, should be one " +
                        "of #{VALID_CONVERSIONS.join(', ')}."
                end
              end
            when "parse"
              data.each do |key, value|
                unless VALID_PARSERS.include?(value)
                  raise Fluent::ConfigError, "mutate #{type} action " +
                        "received an invalid type for #{key}, should be one " +
                        "of #{VALID_PARSERS.join(', ')}."
                end
              end
            when "lowercase", "uppercase", "remove", "strip"
              data.each do |key, value|
                v = Fluent::Config.bool_value(value)
                if v.nil?
                  raise Fluent::ConfigError, "mutate #{type} action " +
                        "requires boolean values, received '#{value}' " +
                        "for #{key}."
                end
                data[key] = v
              end
            when "gsub"
              data.each do |key, value|
                v = Fluent::Config::ARRAY_TYPE.call(value, {value_type: :string})
                if not v.is_a?(Array) or not v.length == 2
                    raise Fluent::ConfigError, "mutate #{type} action " +
                          "requires array values, representing " +
                          "[pattern, replacement] for #{key}, " +
                          "received '#{value}'"
                end

                pattern = v[0]
                replacement = v[1]

                data[key] = {
                  pattern: (
                    pattern.index("%{").nil?? Regexp.new(pattern): pattern\
                  ),
                  replacement: replacement
                }
              end
          end

          @actions << {
            "@type": type,
            "data": data
          }
        end
      end

      # Convert valid types
      VALID_CONVERSIONS = %w(string integer float boolean datetime)

      # Parser valid types
      VALID_PARSERS = %w(json)

      # Convert helper method prefix
      CONVERT_PREFIX = "convert_".freeze

      # Convert boolean regex
      TRUE_REGEX = (/^(true|t|yes|y|1)$/i).freeze
      FALSE_REGEX = (/^(false|f|no|n|0)$/i).freeze

      # Placeholder regex
      ENVIRONMENT_TAG_REGEXP = /%e\{[^}]+\}/

      # Placeholder regex
      TEMPLATE_TAG_REGEXP = /%\{[^}]+\}/

      # Filter action which will manipulate records
      # @since 0.1.0
      # @return [Hash] the modified event record
      def filter(tag, time, record)
        # In order to more easily navigate the record, we wrap the record in a
        # delegator. We additionally pass the `expand_nesting` option which
        # determines whether we should treat periods as field separators.
        result = Fluent::Plugin::Mixin::MutateEvent.
          new(record, expand_nesting: @expand_nesting)
        result.event_time = time.to_i
        result.event_tag = tag

        @actions.each do |action|
          type = action[:@type]
          data = action[:data]

          begin
            send(type.to_sym, data, result)
          rescue => e
            log.warn "failed to mutate #{action} action", error: e
            log.warn_backtrace
          end
        end

        result.prune if @prune_empty
        result.to_record
      end

      protected

      # Expand replacable patterns on the event
      # @since 0.3.0
      # @return [String] the modified string
      def expand_patterns(event, string)
        string = expand_references(event, string)
        string = expand_environment(event, string)
        string
      end

      # Expand %{} strings to the related event fields.
      # @since 0.1.0
      # @return [String] the modified string
      def expand_references(event, string)
        new_string = ''

        position = 0
        matches = string.scan(TEMPLATE_TAG_REGEXP).map{|m| $~}

        matches.each do |match|
          reference_tag = match[0][2..-2]
          reference_value = case reference_tag
                            when "event_time" then event.event_time.to_s
                            when "event_tag"  then event.event_tag
                            else  event.get(reference_tag.downcase).to_s
                            end
          if reference_value.nil?
            @log.error "failed to replace tag", field: reference_tag.downcase
            reference_value = match.to_s
          end

          start = match.offset(0).first
          new_string << string[position..(start-1)] if start > 0
          new_string << reference_value
          position = match.offset(0).last
        end

        if position < string.size
          new_string << string[position..-1]
        end

        new_string
      end

      # Expand %e{} strings to the related environment variables.
      # @since 0.3.0
      # @return [String] the modified string
      def expand_environment(event, string)
        new_string = ''

        position = 0
        matches = string.scan(ENVIRONMENT_TAG_REGEXP).map{|m| $~}

        matches.each do |match|
          reference_tag = match[0][3..-2]
          reference_value = case reference_tag
                            when "hostname" then Socket.gethostname
                            else ENV[reference_tag]
                            end
          if reference_value.nil?
            @log.error "failed to replace tag", field: reference_tag
            reference_value = match.to_s
          end

          start = match.offset(0).first
          new_string << string[position..(start-1)] if start > 0
          new_string << reference_value
          position = match.offset(0).last
        end

        if position < string.size
          new_string << string[position..-1]
        end

        new_string
      end

      # Remove fields from the event hash
      # @since 0.1.0
      def remove(params, event)
        params.each do |field, bool|
          next unless bool
          event.remove(field)
        end
      end

      # Rename fields in the event hash
      # @since 0.1.0
      def rename(params, event)
        params.each do |old, new|
          item = event.get(old)
          next if item.nil?
          event.set(new, item)
          event.remove(old)
        end
      end

      # Update (existing) fields in the event hash
      # @since 0.1.0
      def update(params, event)
        params.each do |field, newvalue|
          newvalue = expand_patterns(event, newvalue)
          next unless event.include?(field)
          event.set(field, newvalue)
        end
      end

      # Replace fields in the event hash
      # @since 0.1.0
      def replace(params, event)
        params.each do |field, newvalue|
          newvalue = expand_patterns(event, newvalue)
          event.set(field, newvalue)
        end
      end

      # Convert fields to given types in the record hash
      # @since 0.1.0
      def convert(params, event)
        params.each do |field, type|
          converter = method(CONVERT_PREFIX + type)

          case original = event.get(field)
          when NilClass
            next
          when Hash
            @log.error("cannot convert hash", field: field, value: original)
          when Array
            event.set(field, original.map{|v| converter.call(v)})
          else
            event.set(field, converter.call(original))
          end
        end
      end

      def convert_string(value)
        value.to_s.force_encoding(Encoding::UTF_8)
      end

      def convert_integer(value)
        value.to_i
      end

      def convert_float(value)
        value.to_f
      end

      def convert_datetime(value)
        value = convert_integer(value) if value.is_a?(String)
        Time.at(value).to_datetime.to_s
      end

      def convert_boolean(value)
        return true if value =~ TRUE_REGEX
        return false if value.empty? || value =~ FALSE_REGEX
        @log.error("failed to convert to boolean", value: value)
      end

      # Convert field values to uppercase in the record hash
      # @since 0.1.0
      def uppercase(params, event)
        params.each do |field, bool|
          next unless bool

          original = event.get(field)
          result = case original
                   when Array
                     original.map do |elem|
                       (elem.is_a?(String) ? elemen.upcase : elem)
                     end
                   when String
                     original.upcase! || original
                   else
                     @log.error("can't uppercase field",
                                field: field,
                                value: original)
                     original
                   end
          event.set(field, result)
        end
      end

      # Convert field values to lowercase in the record hash
      # @since 0.1.0
      def lowercase(params, event)
        params.each do |field, bool|
          next unless bool
          original = event.get(field)
          result = case original
                   when Array
                     original.map do |elem|
                       (elem.is_a?(String) ? elemen.downcase : elem)
                     end
                   when String
                     original.downcase! || original
                   else
                     @log.error("can't lowercase field",
                                field: field,
                                value: original)
                     original
                   end
          event.set(field, result)
        end
      end

      # Split fields based on delimiters in the record hash
      # @since 0.1.0
      def split(params, event)
        params.each do |field, separator|
          value = event.get(field)
          if value.is_a?(String)
            event.set(field, value.split(separator))
          else
            @log.error("can't split field",
                         field: field,
                         value: value)
          end
        end
      end

      # Join fields based on delimiters in the record hash
      # @since 0.1.0
      def join(params, event)
        params.each do |field, separator|
          value = event.get(field)
          if value.is_a?(Array)
            event.set(field, value.join(separator))
          end
        end
      end

      # Strip whitespace surrounding fields in the record hash
      # @since 0.1.0
      def strip(params, event)
        params.each do |field, bool|
          next unless bool
          value = event.get(field)
          case value
          when Array
            event.set(field, value.map{|s| s.strip})
          when String
            event.set(field, value.strip)
          end
        end
      end

      # Merge hashes and arrays in the record hash
      # @since 0.1.0
      def merge(params, event)
        params.each do |dest_field, added_fields|
          dest_field_value = event.get(dest_field)

          Array(added_fields).each do |added_field|
            added_field_value = event.get(added_field)

            if dest_field_value.is_a?(Hash) ^ added_field_value.is_a?(Hash)
              @log.error('cannot merge an array and hash',
                         dest_field: dest_field,
                         added_field: added_field)
              next
            end

            if dest_field_value.is_a?(Hash)
              event.set(dest_field, dest_field_value.update(added_field_value))
            else
              event.set(dest_field, Array(dest_field_value).
                                    concat(Array(added_field_value)))
            end
          end
        end
      end

      # Parse the value of a field
      # Lazily just support json for now
      # @since 1.0.0
      def parse(params, event)
        params.each do |field, parser|
          value = event.get(field)

          unless value.is_a?(String)
            @log.warn("field value cannot be parsed by #{parser}")
            next
          end

          if value.start_with?('{') and value.ends_with?('}') \
          or value.start_with?('[') and value.ends_with?(']')
            value = JSON.load(value)
            event.set(field, value)
          end
        end
      end

      # Perform regular expression substitutions in the record hahs
      # @since 0.1.0
      def gsub(params, event)
        params.each do |key, config|
          pattern = config[:pattern]
          replacement = config[:replacement]

          value = event.get(key)
          case value
          when Array
            result = value.map do |v|
              if v.is_a?(String)
                gsub_dynamic_fields(event, v, pattern, replacement)
              else
                @log.error('cannot gsub non Strings',
                           field: key,
                           value: v)
              end
              event.set(key, result)
            end
          when String
            v = gsub_dynamic_fields(event, value, pattern, replacement)
            event.set(key, v)
          else
            @log.error('cannot gsub non Strings', field: key, value: value)
          end
        end
      end

      def gsub_dynamic_fields(event, original, pattern, replacement)
        replacement = expand_patterns(event, replacement)
        if pattern.is_a?(Regexp)
          original.gsub(pattern, replacement)
        else
          original.gsub(Regexp.new(pattern), replacement)
        end
      end
    end
  end
end
