require 'rugged'
require 'pathname'

# This task is the main task for deploying to staging. The current logic
# is to walk the repo for the last commit ( one loop enumeration )
# The commit that is there should match the "shallow" commit that was cloned
# by puppet pipelines as the `rake repos:download` task checks that out on
# download. We then find changes to markdown files and derive their learning
# component name. This name allows to call their specific dynamically create
# rake task see: `rake -T`.

namespace :release do
  desc 'Build LMS content and upload a release to staging'
  task :staging do
    # Walk repo to find commits
    @config['repos'].each do |key,hash|
      git_dir = "./repos/#{key}"

      # Walk repo to find commits by date
      repo   = Rugged::Repository.new(git_dir)
      walker = Rugged::Walker.new(repo)
      walker.push(repo.head.target)
      walker.each do |commit|
        puts "Processing commit: #{commit.oid}"
        commit.parents[0].diff(commit).each_delta do |delta|
          # Join the path with path repo and read the file into Kramdown
          # TODO: Break this out into a method and allow easy additions
          # to the patterns such as allowing for changes json or css files.
          
          next unless delta.new_file[:path] =~ %r{.*\.md$}
          next unless delta.new_file[:path] =~ %r{_lmscontent/.*$}
          next if     delta.new_file[:path] =~ %r{.*README.md$}

          component_directory = Pathname.new(delta.new_file[:path]).parent.basename
          puts "Found updated component #{component_directory} at path #{delta.new_file[:path]}"

          # Allow for subfolders
          if delta.new_file[:path].split('/').length == 4
            puts "Learning component in subfolder"
            parent_component_directory = Pathname.new(delta.new_file[:path]).parent.parent.basename
            rake_task_name = "#{parent_component_directory}-#{component_directory}"
          else
            rake_task_name = File.basename(component_directory)
          end
          Rake::Task["release:#{rake_task_name}"].invoke('staging') 
        end
        break
      end
    end
  end

  # This task was the first implementation of this tool. Its still useful to run
  # if this build process is disconnected for any period of time. This is
  # because in the event of pipelines or github webhook outage learndot api
  # requests will not be made to upload the last commit. This task can "replay"
  # those requests for the last 24 hours
  # This may overwrite the custom fields with values from a single commit (HEAD)
  # however. This will correct itself overtime as the files are edited.
  desc 'Build LMS content that was edited in the last 24 hours'
  task :staing_nightly do

    # Update the repositories from github
    Rake::Task['download:repos'].invoke

    @config['repos'].each do |key,hash|
      # Push every commit to staging
      # Once repo is up to date , pull new commits from today
      git_dir = "./repos/#{key}"

      # Walk repo to find commits by date
      repo   = Rugged::Repository.new(git_dir)
      walker = Rugged::Walker.new(repo)
      walker.sorting(Rugged::SORT_DATE| Rugged::SORT_REVERSE)
      walker.push(repo.head.target)

      walker.each do |commit|
        c_time = Time.at(commit.time)
        # Find all commits that happen today or after today
        next unless c_time >=  Date.today.to_time
          # Diff the commits and their parent
          commit.parents[0].diff(commit).each_delta do |delta|
            # Join the path with path repo and read the file into Kramdown
            # TODO: break this out to avoid duplication above
            next unless delta.new_file[:path] =~ %r{.*\.md$}
            next unless delta.new_file[:path] =~ %r{_lmscontent/.*$}
            next if     delta.new_file[:path] =~ %r{.*README.md$}
            
            component_directory = Pathname.new(delta.new_file[:path]).parent.basename
            puts "Found updated component #{component_directory} at path #{delta.new_file[:path]}"
            # Allow for subfolders
            if delta.new_file[:path].split('/').length == 4
              puts "Learning component in subfolder"
              parent_component_directory = Pathname.new(delta.new_file[:path]).parent.parent.basename
              rake_task_name = "#{parent_component_directory}-#{component_directory}"
            else
              rake_task_name = File.basename(component_directory)
            end
            Rake::Task["release:#{rake_task_name}"].invoke('staging') 
          end
      end  
    end
  end
  desc 'Build LMS content and upload a release to production'
  task :production do

    # TODO: Loop through the yaml as we do in other tasks
    git_dir = "./repos/courseware-lms-content"

    repo   = Rugged::Repository.new(git_dir)

    # Push version tags to production
    # Find the latest git tag by date & time
    tags = repo.references.each("refs/tags/v*").sort_by{|r| r.target.epoch_time}.reverse! 

    raise "Can't deploy to production No matching (v*) tags found on this repository!" if tags[0].nil?

    # Use the last commit in the repo if only one tag exists
    parent = tags[1].nil? ? repo.last_commit : tags[1].target 

    # Compare that tag to the tag that historically preceded it
    parent.diff(tags[0].target).each_delta do |delta|
      # Join the path with path repo and read the file into Kramdown
      # TODO: break this out to avoid duplication above
      next unless delta.new_file[:path] =~ %r{.*\.md$}
      next unless delta.new_file[:path] =~ %r{_lmscontent/.*$}
      next if     delta.new_file[:path] =~ %r{.*README.md$}

      component_directory = Pathname.new(delta.new_file[:path]).parent.basename
      puts "Found updated component #{component_directory} at path #{delta.new_file[:path]}"

      # Allow for subfolders
      if delta.new_file[:path].split('/').length == 4
        puts "Learning component in subfolder"
        parent_component_directory = Pathname.new(delta.new_file[:path]).parent.parent.basename
        rake_task_name = "#{parent_component_directory}-#{component_directory}"
      else
        rake_task_name = File.basename(component_directory)
      end

      Rake::Task["release:#{rake_task_name}"].invoke('production') 
    end
  end
end

