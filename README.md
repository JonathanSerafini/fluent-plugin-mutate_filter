# Fluent::MutateFilter

This gem provides the `mutate` filter for Fluentd which is designed to replicate the way `mutate` works in Logstash as much as possible. 

To be honest, this is a translation of [logstash-filter-mutate](https://github.com/logstash-plugins/logstash-filter-mutate) bordering on copy-paste.

## Requirements

* Fluentd v0.12+

## Installation

```bash
gem install fluent-plugin-mutate_filter
```

## Configuration Options

All of the documentation and potential options are documented in the config_params section of the filter module. Below, only a subset of the options are displayed.

```
<filter *>
  @type     mutate
  rename {
    "old_field_name": "new_field_name",
    "old_nest.field_name": "new_nest.field_name"
  }
  replace {
    "new_nest.field_name": "%{old_nest.field_name}"
  }
</filter>
```

