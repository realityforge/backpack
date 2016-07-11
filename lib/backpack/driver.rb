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

module Backpack #nodoc
  class Driver
    class << self
      def converge(client, organization)
        converge_teams(client, organization)
        converge_repositories(client, organization)
        converge_hooks(client, organization)
      end

      def converge_teams(client, organization)
        remote_teams = client.organization_teams(organization.name)
        remote_teams.each do |remote_team|
          name = remote_team['name']
          if organization.team_by_name?(name)
            team = organization.team_by_name(name)
            team.github_id = remote_team['id']
            converge_team(client, team, remote_team)
          else
            puts "Removing team named #{name}"
            client.delete_team(remote_team['id'])
          end
        end
        organization.teams.each do |team|
          unless remote_teams.any? { |r| r['name'] == team.name }
            puts "Creating team #{team.name}"
            remote_team = client.create_team(organization.name, :name => team.name, :permission => team.permission)
            team.github_id = remote_team['id']
          end
        end
      end

      def converge_team(client, team, remote_team)
        update = false
        update = true if remote_team['permission'] != team.permission

        if update
          puts "Updating team #{team.name}"
          client.update_team(team.github_id, :permission => team.permission)
        end
      end

      def converge_repositories(client, organization)
        remote_repositories = client.organization_repositories(organization.name)
        remote_repositories.each do |remote_repository|
          name = remote_repository['name']
          if organization.repository_by_name?(name)
            converge_repository(client, organization.repository_by_name(name), remote_repository)
          else
            puts "WARNING: Unmanaged repository detected named '#{name}'"
          end
        end
        organization.repositories.each do |repository|
          unless remote_repositories.any? { |r| r['name'] == repository.name }
            puts "Creating repository #{repository.name}"
            remote_repositories << client.create_repository(repository.name,
                                                            :organization => repository.organization.name,
                                                            :description => repository.description,
                                                            :homepage => repository.homepage,
                                                            :private => repository.private?,
                                                            :has_issues => repository.issues?,
                                                            :has_wiki => repository.wiki?,
                                                            :has_downloads => repository.downloads?)
          end
        end

        team_map = {}
        client.organization_teams(organization.name).each do |remote_team|
          id = remote_team['id']
          team_map[id] = client.team_repositories(id)
        end

        remote_repositories.each do |remote_repository|
          name = remote_repository['name']
          next unless organization.repository_by_name?(name)
          repository = organization.repository_by_name(name)

          repository_full_name = "#{organization.name}/#{repository.name}"
          remote_teams = client.repository_teams(repository_full_name, :accept => 'application/vnd.github.v3.repository+json')
          remote_teams.each do |remote_team|
            name = remote_team['name']
            if repository.team_by_name?(name)
              permission =
                repository.admin_team_by_name?(name) ? 'admin' : repository.push_team_by_name?(name) ? 'push' : 'pull'

              team = organization.team_by_name(name)
              update = false

              permissions = team_map[team.github_id].select { |t| t['name'] == repository.name }[0]['permissions']

              update = true if (permission == 'admin' && !permissions[:admin])
              update = true if (permission == 'push' && !permissions[:push])
              update = true if (permission == 'pull' && !permissions[:pull])

              if update
                puts "Updating repository team #{team.name} on #{repository.name}"
                client.add_team_repository(team.github_id, repository_full_name, :permission => permission)
              end
            else
              puts "Removing repository team #{remote_team['name']} from #{repository.name}"
              client.remove_team_repository(remote_team['id'], repository_full_name)
              remote_teams.delete(remote_team)
            end
          end
          %w(admin pull push).each do |permission|
            repository.send(:"#{permission}_teams").each do |team|
              unless remote_teams.any? { |remote_team| remote_team['name'] == team.name }
                puts "Adding #{permission} repository team #{team.name} to #{repository.name}"
                client.add_team_repository(team.github_id, repository_full_name, :permission => permission)
              end
            end
          end
        end
      end

      def converge_repository(client, repository, remote_repository)
        update = false
        update = true if remote_repository['description'].to_s != repository.description.to_s
        update = true if remote_repository['homepage'].to_s != repository.homepage.to_s
        update = true if remote_repository['private'].to_s != repository.private?.to_s
        update = true if remote_repository['has_issues'].to_s != repository.issues?.to_s
        update = true if remote_repository['has_wiki'].to_s != repository.wiki?.to_s
        update = true if remote_repository['has_downloads'].to_s != repository.downloads?.to_s

        if update
          puts "Updating repository #{repository.name}"
          client.edit_repository(remote_repository['full_name'],
                                 :description => repository.description,
                                 :homepage => repository.homepage,
                                 :private => repository.private?,
                                 :has_issues => repository.issues?,
                                 :has_wiki => repository.wiki?,
                                 :has_downloads => repository.downloads?)
        end
      end

      def converge_hooks(client, organization)
        organization.repositories.each do |repository|
          remote_hooks = client.hooks(repository.qualified_name)
          repository.hooks.each do |hook|
            if remote_hooks.any? { |r| r['name'] == hook.name }
              remote_hook = remote_hooks.select { |r| r['name'] == hook.name }[0]

              update = false

              update = true if remote_hook[:active] != hook.active?
              update = true if remote_hook[:events].sort != hook.events.sort
              update = true unless hash_same(remote_hook[:config].to_h, hook.config, hook.password_config_keys)

              if update
                puts "Updating #{hook.name} hook on repository #{repository.qualified_name}"
                client.create_hook(repository.qualified_name,
                                   hook.name,
                                   hook.config,
                                   :events => hook.events,
                                   :active => hook.active?)
              end
              remote_hooks.delete(remote_hook)
            else
              puts "Creating #{hook.name} hook on repository #{repository.qualified_name}"
              client.create_hook(repository.qualified_name,
                                 hook.name,
                                 hook.config,
                                 :events => hook.events,
                                 :active => hook.active?)
            end
          end
          remote_hooks.each do |remote_hook|
            puts "Removing #{remote_hook['name']} hook on repository #{repository.qualified_name}"
            client.remove_hook(repository.qualified_name, remote_hook['id'])
          end
        end
      end

      def hash_same(hash1, hash2, skip_keys)
        return false if hash1.size != hash2.size
        hash1.keys.each do |key|
          next if skip_keys.include?(key.to_s)
          return false if hash1[key] != hash2[key]
        end
        true
      end
    end
  end
end
