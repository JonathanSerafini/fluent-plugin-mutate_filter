require 'fluent/filter'
require 'fluent/plugin_mixin/mutate_event'

module Fluent
  class MutateFilter < Filter
    Fluent::Plugin.register_filter('mutate', self)

    # Treat periods as nested field names
    config_param :expand_nesting, :bool, default: true

    # Remove any empty hashes or arrays
    config_param :prune_empty,    :bool, default: true

    # Rename one or more fields
    # @example
    #   rename {
    #     "timestamp": "@timestamp"
    #   }
    config_param :rename,     :hash,  default: Hash.new

    # Update an existing field with a new value.
    # - If the field does not exist then no action will be taken.
    # - If the new value contains a placeholder %{}, then the value will be
    #   expanded to the related event record field.
    # @example
    #   update {
    #     "message": "%{hostname}: new message"
    #   }
    config_param :update,     :hash,  default: Hash.new

    # Remove an existing field
    # @example
    #   remove [
    #     "dummy1", "placeholder1"
    #   ]
    config_param :remove,     :array, default: Array.new

    # Replace a field with a new value
    # - If the field does not exist, then it will be created.
    # - If the new value contains a placeholder %{}, then the value will be
    #   expanded to the related event record field.
    # @example
    #   replace {
    #     "new_message": "a new field"
    #   }
    config_param :replace,    :hash,  default: Hash.new

    # Convert a field's value to a different type, like turning a string to an
    # integer.
    # - If the field value is an array, all members will be converted.
    # - If the field value is a hash, then no action will be taken.
    # - Valid conversion types are integer, float, string, boolean
    # @example
    #   convert {
    #     "id": "integer",
    #     "message": "string"
    #   }
    config_param :convert,    :hash,  default: Hash.new

    # Convert a string field by applying a regular expression and replacement.
    # - If the field is not a string, then no action will be taken.
    #
    # The configuration takes an array consisting of 3 elements per field/sub.
    #
    # @example
    #   gsub [
    #     "fieldname",  "/", "_",
    #     "fieldname2", "[\\?#-]", "."
    #   ]
    config_param :gsub,       :array, default: Array.new

    # Convert a string to it's uppercase equivalent
    # @example
    #   uppercase [
    #     "field1", "field2"
    #   ]
    config_param :uppercase,  :array, default: Array.new

    # Convert a string to it's lowercase equivalent
    # @example
    #   lowercase [
    #     "field1", "field2"
    #   ]
    config_param :lowercase,  :array, default: Array.new

    # Strip whitespace from field.
    # @example
    #   strip [
    #     "field1"
    #   ]
    config_param :strip,      :array, default: Array.new

    # Split a field to an array using a separator character
    # @example
    #   split {
    #     "field1": ","
    #   }
    config_param :split,      :hash, default: Hash.new

    # Join an array using a separator character
    # @example
    #   join {
    #     "field1": " "
    #   }
    config_param :join,      :hash, default: Hash.new

    # Merge two fields of arrays or hashes
    # @example
    #   merge {
    #     "dest_field": "added_field"
    #   }
    config_param :merge,      :hash, default: Hash.new

    # List of all possible mutate actions, in the order that we will apply
    # them. As it stands, this is the order in which Logstash would apply them.
    MUTATE_ACTIONS = %w(
      rename
      update
      replace
      convert
      gsub
      uppercase
      lowercase
      strip
      remove
      split
      join
      merge
    )

    # Convert valid types
    VALID_CONVERSIONS = %w(string integer float boolean datetime)

    # Convert helper method prefix
    CONVERT_PREFIX = "convert_".freeze

    # Convert boolean regex
    TRUE_REGEX = (/^(true|t|yes|y|1)$/i).freeze
    FALSE_REGEX = (/^(false|f|no|n|0)$/i).freeze

    # Placeholder regex
    TEMPLATE_TAG_REGEXP = /%\{[^}]+\}/

    # Initialize attributes and parameters
    # @since 0.1.0
    # @return [NilClass]
    def configure(conf)
      super

      @convert.nil? or @convert.each do |field, type|
        if !VALID_CONVERSIONS.include?(type)
          raise ConfigError,
            "convert #{type} is not one of #{VALID_CONVERSIONS.join(',')}."
        end
      end

      @gsub_parsed = []
      @gsub.nil? or
      @gsub.each_slice(3) do |field, needle, replacement|
        if [field, needle, replacement].any? {|n| n.nil?}
          raise ConfigError,
            "gsub #{[field,needle,replacement]} requires 3 elements."
        end

        @gsub_parsed << {
          field: field,
          needle: (needle.index("%{").nil?? Regexp.new(needle): needle),
          replacement: replacement
        }
      end
    end

    # Filter action which will manipulate records
    # @since 0.1.0
    # @return [Hash] the modified event record
    def filter(tag, time, record)
      # In order to more easily navigate the record, we wrap the record in a
      # delegator. We additionally pass the `expand_nesting` option which
      # determines whether we should treat periods as field separators.
      result = Fluent::PluginMixin::MutateEvent.
        new(record, expand_nesting: @expand_nesting)
      result.event_time = time.to_i
      result.event_tag = tag

      MUTATE_ACTIONS.each do |action|
        begin
          send(action.to_sym, result) if instance_variable_get("@#{action}")
        rescue => e
          log.warn "failed to mutate #{action} action", error: e
          log.warn_backtrace
        end
      end

      result.prune if @prune_empty
      result.to_record
    end

    protected

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

    # Remove fields from the event hash
    # @since 0.1.0
    def remove(event)
      @remove.each do |field|
        event.remove(field)
      end
    end

    # Rename fields in the event hash
    # @since 0.1.0
    def rename(event)
      @rename.each do |old, new|
        item = event.get(old)
        next if item.nil?
        event.set(new, item)
        event.remove(old)
      end
    end

    # Update (existing) fields in the event hash
    # @since 0.1.0
    def update(event)
      @update.each do |field, newvalue|
        newvalue = expand_references(event, newvalue)
        next unless event.include?(field)
        event.set(field, newvalue)
      end
    end

    # Replace fields in the event hash
    # @since 0.1.0
    def replace(event)
      @replace.each do |field, newvalue|
        newvalue = expand_references(event, newvalue)
        event.set(field, newvalue)
      end
    end

    # Convert fields to given types in the record hash
    # @since 0.1.0
    def convert(event)
      @convert.each do |field, type|
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
    def uppercase(event)
      @uppercase.each do |field|
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
    def lowercase(event)
      @lowercase.each do |field|
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
    def split(event)
      @split.each do |field, separator|
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
    def join(event)
      @join.each do |field, separator|
        value = event.get(field)
        if value.is_a?(Array)
          event.set(field, value.join(separator))
        end
      end
    end

    # Strip whitespace surrounding fields in the record hash
    # @since 0.1.0
    def strip(event)
      @strip.each do |field|
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
    def merge(event)
      @merge.each do |dest_field, added_fields|
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

    # Perform regular expression substitutions in the record hahs
    # @since 0.1.0
    def gsub(event)
      @gsub_parsed.each do |config|
        field = config[:field]
        needle = config[:needle]
        replacement = config[:replacement]

        value = event.get(field)
        case value
        when Array
          result = value.map do |v|
            if v.is_a?(String)
              gsub_dynamic_fields(event, v, needle, replacement)
            else
              @log.error('cannot gsub non Strings',
                         field: field,
                         value: v)
            end
            event.set(field, result)
          end
        when String
          v = gsub_dynamic_fields(event, value, needle, replacement)
          event.set(field, v)
        else
          @log.error('cannot gsub non Strings', field: field, value: value)
        end
      end
    end

    def gsub_dynamic_fields(event, original, needle, replacement)
      replacement = expand_references(event, replacement)
      if needle.is_a?(Regexp)
        original.gsub(needle, replacement)
      else
        original.gsub(Regexp.new(needle), replacement)
      end
    end
  end
end

