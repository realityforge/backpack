# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name               = %q{backpack}
  s.version            = '0.1.0.dev'
  s.platform           = Gem::Platform::RUBY

  s.authors            = ['Peter Donald']
  s.email              = %q{peter@realityforge.org}

  s.homepage           = %q{https://github.com/realityforge/backpack}
  s.summary            = %q{Backpack manages GitHub organizations declaratively.}
  s.description        = %q{Backpack is a very simple tool that helps you manage GitHub organizations declaratively.}

  s.rubyforge_project  = %q{backpack}
  s.licenses           = ['Apache-2.0']

  s.files              = `git ls-files`.split("\n")
  s.test_files         = `git ls-files -- {spec}/*`.split("\n")
  s.executables        = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.default_executable = []
  s.require_paths      = %w(lib)

  s.has_rdoc           = false
  s.rdoc_options       = %w(--line-numbers --inline-source --title backpack)

  s.add_dependency 'reality-core', '= 1.4.0'
  s.add_dependency(%q<octokit>, ['~> 4.0'])
  s.add_dependency(%q<netrc>, ['~> 0.11'])
  s.add_dependency(%q<travis>, ['= 1.8.2'])
end
