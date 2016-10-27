#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Backpack
  class RepositoryHook < BaseElement
    def initialize(repository, name, options, &block)
      @repository, @name = repository, name
      @events = ['push']
      @active = true
      @config = {}
      super(options, &block)
    end

    attr_reader :name
    attr_reader :repository

    attr_writer :type

    def type
      @type.nil? ? self.name : @type
    end

    attr_writer :active

    def active?
      !!@active
    end

    def singleton?
      @config_key.nil?
    end

    # Key inside config data that uniquely identifies hook
    attr_accessor :config_key

    attr_writer :password_config_keys

    def password_config_keys
      @password_config_keys ||= []
    end

    attr_accessor :events
    attr_accessor :config
  end

  class Repository < BaseElement
    def initialize(organization, name, options, &block)
      @organization, @name = organization, name

      @tags = []

      @admin_teams = []
      @pull_teams = []
      @push_teams = []

      @hooks = {}

      options = options.dup

      (options.delete(:admin_teams) || {}).each do |team|
        add_admin_team(team)
      end
      (options.delete(:push_teams) || {}).each do |team|
        add_push_team(team)
      end
      (options.delete(:pull_teams) || {}).each do |team|
        add_pull_team(team)
      end

      super(options, &block)
    end

    attr_reader :organization
    attr_reader :name

    def qualified_name
      "#{self.organization.name}/#{self.name}"
    end

    attr_accessor :tags

    attr_writer :description

    def description
      @description || ''
    end

    attr_writer :homepage

    def homepage
      @homepage || ''
    end

    attr_writer :private

    def private?
      @private.nil? ? true : !!@private
    end

    attr_writer :issues

    def issues?
      @issues.nil? ? false : !!@issues
    end

    attr_writer :wiki

    def wiki?
      @wiki.nil? ? false : !!@wiki
    end

    attr_writer :downloads

    def downloads?
      @downloads.nil? ? false : !!@downloads
    end

    def hook(name, config = {}, &block)
      raise "Hook already exists with name #{name} for repository #{self.name}" if @hooks[name.to_s]
      @hooks[name.to_s] = RepositoryHook.new(self, name, config, &block)
    end

    def hook_by_name?(name)
      !!@hooks[name.to_s]
    end

    def hook_by_name(name)
      raise "Hook with name #{name} does not exist for repository #{self.name}" unless @hooks[name.to_s]
      @hooks[name.to_s]
    end

    def hooks
      @hooks.values.dup
    end

    def admin_teams
      @admin_teams.dup
    end

    def admin_team_by_name?(name)
      @admin_teams.any? { |team| team.name.to_s == name.to_s }
    end

    def add_admin_team(team)
      team = team.is_a?(Team) ? team : organization.team_by_name(team)
      @admin_teams << team
      team.admin_repositories << self
      team
    end

    def pull_teams
      @pull_teams.dup
    end

    def pull_team_by_name?(name)
      @pull_teams.any? { |team| team.name.to_s == name.to_s }
    end

    def add_pull_team(team)
      team = team.is_a?(Team) ? team : organization.team_by_name(team)
      @pull_teams << team
      team.pull_repositories << self
      team
    end

    def push_teams
      @push_teams.dup
    end

    def push_team_by_name?(name)
      @push_teams.any? { |team| team.name.to_s == name.to_s }
    end

    def add_push_team(team)
      team = team.is_a?(Team) ? team : organization.team_by_name(team)
      @push_teams << team
      team.push_repositories << self
      team
    end

    def team_by_name?(name)
      admin_team_by_name?(name) || push_team_by_name?(name) || pull_team_by_name?(name)
    end
  end

  class Team < BaseElement
    def initialize(organization, name, options, &block)
      @organization, @name = organization, name

      @admin_repositories = []
      @pull_repositories = []
      @push_repositories = []

      super(options, &block)
    end

    attr_reader :organization
    attr_reader :name

    attr_writer :permission

    def permission
      @permission || 'pull'
    end

    # This id begins null and is populated during converge with the actual github id
    attr_accessor :github_id

    # List of repositories with admin access. Is automatically updated
    def admin_repositories
      @admin_repositories
    end

    # List of repositories with pull access. Is automatically updated
    def pull_repositories
      @pull_repositories
    end

    # List of repositories with push access. Is automatically updated
    def push_repositories
      @push_repositories
    end
  end

  class Organization < BaseElement
    def initialize(name, options, &block)
      @name = name
      @repositories = {}
      @teams = {}

      super(options, &block)
    end

    attr_reader :name

    def repository(name, options = {}, &block)
      raise "Repository named #{name} already defined in organization #{self.name}" if @repositories[name.to_s]
      @repositories[name.to_s] = Repository.new(self, name, options, &block)
    end

    def repository_by_name?(name)
      !!@repositories[name.to_s]
    end

    def repository_by_name(name)
      raise "No repository named #{name} defined in organisation #{self.name}" unless @repositories[name.to_s]
      @repositories[name.to_s]
    end

    def repositories
      @repositories.values
    end

    def team(name, options = {}, &block)
      raise "Repository named #{name} already defined in organization #{self.name}" if @teams[name.to_s]
      @teams[name.to_s] = Team.new(self, name, options, &block)
    end

    def team_by_name?(name)
      !!@teams[name.to_s]
    end

    def team_by_name(name)
      raise "No team named #{name} defined in organisation #{self.name}" unless @teams[name.to_s]
      @teams[name.to_s]
    end

    def teams
      @teams.values
    end
  end

  class << self
    def organization(name, options = {}, &block)
      raise "Organization named #{name} already defined" if self.organization_map[name.to_s]
      self.organization_map[name.to_s] = Organization.new(name, options, &block)
    end

    def organization_by_name?(name)
      !!@organizations[name.to_s]
    end

    def organization_by_name(name)
      raise "No organization named #{name} defined." unless self.organization_map[name.to_s]
      self.organization_map[name.to_s]
    end

    def organizations
      self.organization_map.values
    end

    def organization_map
      @organizations ||= {}
    end
  end
end
