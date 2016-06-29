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
            puts "WARNING: Unmanaged team detected named '#{name}'"
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
    end
  end
end
