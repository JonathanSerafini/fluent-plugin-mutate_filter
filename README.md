# fluent-plugin-mutate

[Fluentd](https://fluentd.org/) filter plugin to transform records.

This gem provides the `mutate` filter for Fluentd which is designed to replicate the way `mutate` works in Logstash.

## Installation

### RubyGems

```
$ gem install fluent-plugin-mutate_filter
```

### Bundler

Add following line to your Gemfile:

```ruby
gem "fluent-plugin-mutate"
```

And then execute:

```
$ bundle
```

## Configuration

The mutate filter accepts a list of `<mutate>` blocks which will be executed
in sequence, applying their respective mutation `@type`.

Each block will be evaluated in the order with which they were defined in the
configuration file. Multiple keys within a same block _should_ be evaluated in
the defined order, however this shouldn't be relied upon.

While evaluating mutations, should an exception occur, it will be logged and
further mutations will continue to be evaluated.

```
<filter **>
  @type mutate

  <mutate>
    @type     rename
    old_key1  "new_key1"
    old_key2  "new_key2"
  </mutate>

  <mutate>
    @type     gsub
    new_key2  ["^\\[log \\d{4}-\\d{2}-\\d{2}T.*\\] {","{"]
  </mutate>
</filter
```

Global options:

* `expand_nesting (true)|false`: Treat periods in field names as separators. Allowing you to reference `{ deeply: { nested: { key: value } } }` as deeply.nested.key.
* `prune_empty (true)|false`: At the end of the list of mutations, delete any values with empty Maps or Arrays or Nil values.

### Replacement Patterns

Certain mutators, such as `gsub`, `replace` and `update` may contain special patterns which will be evaluated during the mutation. Supported patterns are:

* `%{key}`: Pattern will be replaced by record key value. When `expand_nesting` is enabled, the key may be in dot notation.
* `%e{ENV_VAR}`: Pattern will be replaced by an environment variable. If `ENV\_VAR` is `hostname`, then the machine's hostname will be injected.

### Mutation Types

##### `convert string|integer|float|boolean|datetime`

Convert the key's value to a given type.

##### `gsub [pattern, replace]`

Apply a regex find and replace on a key's value.

Additionally, new\_value may contain replacement patterns which will be evaluated during the replacement.

##### `join <separator>`

Join the components of an Array key using separator, converting it to a String.

##### `lowercase true|false`

Lowercase the key's value. If the value is an Array, then apply the filter to all array elements.

##### `merge <source_field>`

Merge the value of source\_field, which may be an Array or a Map, into the key's value.

##### `rename <new_name>`

Rename a key to a new key name.

##### `remove true|false`

Remove a key and it's value, whether the value be a string or an object.

##### `replace <new_value>

Replace the value of a key with new\_value, if the key exists. Otherwise, set the value of the key to new\_value.

Additionally, new\_value may contain replacement patterns which will be evaluated during the replacement.

##### `update <new_value>`

Replace the value of a key with new\_value, if the key exists. Otherwise, ignore this operation.

Additionally, new\_value may contain replacement patterns which will be evaluated during the replacement.

##### `uppercase true|false`

Uppercase the key's value. If the value is an Array, then apply the filter to all array elements.

##### `split <separator>`

Split the value of key using separator, converting it to an Array.

##### `strip true|false`

Remove whitespace surrounding a key's value. If the value is an Array, apply the filter to each element.

## Copyright

* Copyright(c) 2018- Jonathan Serafini
* License
  * Apache License, Version 2.0
