#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to find duplicated devlogs for a project or all projects
# Usage:
#   rails runner script/find_duplicated_devlogs.rb                    # Check all projects (dry-run)
#   rails runner script/find_duplicated_devlogs.rb --delete            # Delete duplicates from all projects
#   rails runner script/find_duplicated_devlogs.rb [project_id_or_title]  # Check specific project (dry-run)
#   rails runner script/find_duplicated_devlogs.rb [project_id_or_title] --delete  # Delete duplicates from project

require_relative "../config/environment"

class DuplicatedDevlogsFinder
  def initialize(project_identifier: nil, check_all: false, delete: false)
    @project = find_project(project_identifier) unless check_all
    @check_all = check_all
    @delete = delete
    @duplicates = []
    @project_results = {}
    @deleted_count = 0
    @deleted_devlog_ids = []
  end

  def find_project(identifier)
    return nil if identifier.nil?

    # Try to find by ID first
    project = Project.find_by(id: identifier)
    return project if project

    # Try to find by title (case-insensitive, partial match)
    project = Project.where("LOWER(title) LIKE ?", "%#{identifier.downcase}%").first
    return project if project

    puts "❌ Project not found: #{identifier}"
    nil
  end

  def run
    if @check_all
      check_all_projects
    elsif @project.nil?
      puts "Usage: rails runner script/find_duplicated_devlogs.rb [project_id_or_title] [--delete]"
      puts "       (Run without arguments to check all projects)"
      puts "       Add --delete flag to actually delete duplicates (keeps first, deletes rest)"
      puts "\nAvailable projects:"
      Project.limit(10).each do |p|
        puts "  ID: #{p.id}, Title: #{p.title}"
      end
      puts "\n... and #{Project.count - 10} more" if Project.count > 10
      nil
    else
      check_single_project(@project)
    end
  end

  def check_all_projects
    mode = @delete ? "🔴 DELETING" : "🔍 Finding"
    puts "#{mode} duplicated devlogs for ALL projects with devlogs..."
    puts @delete ? "⚠️  DELETION MODE: Duplicates will be deleted!" : "ℹ️  DRY-RUN MODE: No deletions will be made"
    puts "\n"

    # Find all projects that have at least one devlog
    projects_with_devlogs = Project.joins("INNER JOIN posts ON posts.project_id = projects.id")
                                   .where("posts.postable_type = ?", "Post::Devlog")
                                   .distinct

    total_projects = projects_with_devlogs.count
    puts "Found #{total_projects} projects with devlogs\n\n"

    projects_with_duplicates = 0
    total_duplicate_pairs = 0

    index = 0
    projects_with_devlogs.find_each do |project|
      index += 1
      print "\rProcessing project #{index}/#{total_projects}: #{project.title} (#{project.id})"
      STDOUT.flush

      result = check_single_project(project, silent: true)
      if result[:has_duplicates]
        projects_with_duplicates += 1
        total_duplicate_pairs += result[:by_body_and_attachments]
      end
    end

    puts "\n\n" + "=" * 80
    puts "📊 FINAL SUMMARY"
    puts "=" * 80
    puts "Total projects checked: #{total_projects}"
    puts "Projects with consecutive duplicates: #{projects_with_duplicates}"
    puts "Projects without duplicates: #{total_projects - projects_with_duplicates}"
    puts "\nTotal consecutive duplicate pairs found: #{total_duplicate_pairs}"
    if @delete
      puts "\nTotal devlogs deleted: #{@deleted_count}"
      puts "Deleted devlog IDs: #{@deleted_devlog_ids.join(', ')}" if @deleted_devlog_ids.any?
    end
    puts "=" * 80

    if projects_with_duplicates > 0
      puts "\n📋 Projects with consecutive duplicates:"
      @project_results.each do |project_id, result|
        next unless result[:has_duplicates]

        project = Project.find(project_id)
        puts "\n  Project ##{project.id}: #{project.title}"
        puts "    - Consecutive duplicate pairs: #{result[:by_body_and_attachments]}"
      end
    end
  end

  def check_single_project(project, silent: false)
    unless silent
      mode = @delete ? "🔴 DELETING" : "🔍 Finding"
      puts "#{mode} duplicated devlogs for project:"
      puts "   ID: #{project.id}"
      puts "   Title: #{project.title}"
      puts "   Total devlogs: #{project.devlogs.count}"
      puts @delete ? "   ⚠️  DELETION MODE: Duplicates will be deleted!" : "   ℹ️  DRY-RUN MODE: No deletions will be made"
      puts "\n"
    end

    # Reset duplicates for this project
    @duplicates = []

    devlogs = project.devlogs
                     .where(deleted_at: nil)
                     .includes(:post, attachments_attachments: :blob)
                     .order(created_at: :asc)
                     .to_a

    analyze_devlogs(devlogs)
    result = report_duplicates(silent: silent)

    # Delete duplicates if in delete mode
    if @delete && result[:has_duplicates]
      delete_duplicates(silent: silent)
    end

    @project_results[project.id] = result
    result
  end

  private

  def analyze_devlogs(devlogs)
    # Check for consecutive duplicates (one after the other)
    # A duplicate is when body matches, attachments match, and they are consecutive
    devlogs.each_cons(2) do |prev_devlog, current_devlog|
      prev_body = normalize_body(prev_devlog.body)
      current_body = normalize_body(current_devlog.body)
      prev_attachments = attachment_signature(prev_devlog)
      current_attachments = attachment_signature(current_devlog)

      # Check if both have body and attachments, and they match
      if prev_body.present? && current_body.present? &&
         prev_attachments.present? && current_attachments.present? &&
         prev_body == current_body &&
         prev_attachments == current_attachments

        # Found a duplicate pair (consecutive devlogs with matching body and attachments)
        @duplicates << [ prev_devlog, current_devlog ]
      end
    end
  end

  def normalize_body(body)
    return nil if body.blank?

    body.strip.downcase
  end

  def attachment_signature(devlog)
    return nil unless devlog.attachments.attached?

    # Create a signature from blob IDs and checksums
    blobs = devlog.attachments_attachments.includes(:blob).map do |attachment|
      blob = attachment.blob
      "#{blob.id}:#{blob.checksum}:#{blob.filename}"
    end.sort.join("|")
  end

  def report_duplicates(silent: false)
    found_duplicates = @duplicates.any?

    if found_duplicates
      unless silent
        puts "🔀 Found #{@duplicates.size} consecutive duplicate pair(s):"
        puts "\n"
        @duplicates.each_with_index do |(prev_devlog, current_devlog), index|
          puts "Duplicate Pair ##{index + 1}:"
          puts "  Body: #{prev_devlog.body&.truncate(100)}"
          puts "  Attachments: #{prev_devlog.attachments.map(&:filename).join(', ')}"
          puts "\n  First devlog (KEEPING):"
          puts "    - Devlog ##{prev_devlog.id}"
          puts "    - Created: #{prev_devlog.created_at}"
          puts "    - Post ID: #{prev_devlog.post&.id}"
          puts "\n  Duplicate devlog (#{@delete ? 'DELETING' : 'would delete'}):"
          puts "    - Devlog ##{current_devlog.id}"
          puts "    - Created: #{current_devlog.created_at}"
          puts "    - Post ID: #{current_devlog.post&.id}"
          puts "\n" + "-" * 60 + "\n"
        end

        puts "\n" + "=" * 60
        puts "📊 Summary:"
        puts "   Total consecutive duplicate pairs: #{@duplicates.size}"
        puts "   Devlogs to #{@delete ? 'delete' : 'be deleted'}: #{@duplicates.size}"
        puts "=" * 60
      end
    else
      unless silent
        puts "✅ No consecutive duplicates found for this project!"
      end
    end

    {
      has_duplicates: found_duplicates,
      by_body: 0,
      by_attachments: 0,
      by_body_and_attachments: @duplicates.size
    }
  end

  def delete_duplicates(silent: false)
    # Collect all devlogs to delete (the second one in each pair)
    # This handles cases where there are multiple consecutive duplicates
    devlogs_to_delete = @duplicates.map { |_prev, current| current }.uniq

    deleted_in_project = 0

    devlogs_to_delete.each do |devlog|
      # Skip if already deleted (shouldn't happen, but safety check)
      next if devlog.deleted?

      begin
        devlog.soft_delete!
        @deleted_count += 1
        @deleted_devlog_ids << devlog.id
        deleted_in_project += 1

        unless silent
          puts "✅ Deleted devlog ##{devlog.id} (Post ID: #{devlog.post&.id})"
        end
      rescue => e
        unless silent
          puts "❌ Error deleting devlog ##{devlog.id}: #{e.message}"
        end
      end
    end

    unless silent
      puts "\n🗑️  Deleted #{deleted_in_project} duplicate devlog(s) from this project"
    end
  end
end

# Run the script
if __FILE__ == $PROGRAM_NAME
  args = ARGV.dup
  delete_mode = args.delete("--delete")

  project_identifier = args[0]
  check_all = project_identifier.nil?

  finder = DuplicatedDevlogsFinder.new(
    project_identifier: project_identifier,
    check_all: check_all,
    delete: delete_mode
  )
  finder.run
end
