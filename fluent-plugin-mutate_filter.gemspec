# coding: utf-8
Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-mutate_filter"
  spec.version       = "0.3.0"
  spec.authors       = ["Jonathan Serafini"]
  spec.email         = ["jonathan@serafini.ca"]
  spec.summary       = %q{A mutate filter for Fluent which functions like Logstash.}
  spec.description   = spec.description
  spec.homepage      = "https://github.com/JonathanSerafini/fluent-plugin-mutate_filter"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd", [">= 0.12.0", "< 0.15.0"]
  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
end
