#!/usr/bin/env ruby
# frozen_string_literal: true

# Rolls the resume forward to a new month: recomputes the duration on every
# "Mon YYYY - Mon YYYY (duration)" and "Mon YYYY - Present (duration)" line, and
# writes the result to YYYY-mon-tod-beardsley-resume.md.
#
# Durations count both the first and last month, the way LinkedIn does, so
# "Oct 2024 - Feb 2025" is 5 months and a job started this month is 1 month.
#
# The newest existing resume is the source and is left in place. This script
# never touches git; it prints the commands to run.
#
#   bin/update-resume.rb                    # write this month's resume
#   bin/update-resume.rb --check            # report changes, write nothing
#   bin/update-resume.rb --as-of 2026-12    # pretend it is another month

require "date"
require "optparse"

REPO_ROOT = File.expand_path("..", __dir__)
FILE_NAME = /\A(\d{4})-([a-z]{3})-tod-beardsley-resume\.md\z/i
MONTH = Date::ABBR_MONTHNAMES.compact.join("|")
DATE_LINE = /^((?:#{MONTH}) \d{4}) - ((?:#{MONTH}) \d{4}|Present)(?: \([^)\n]*\))?(?=[ \t]*\r?$)/

def month_index(date)
  (date.year * 12) + date.month
end

def parse_month(text)
  Date.strptime(text, "%b %Y")
end

def format_duration(months)
  years, remainder = months.divmod(12)
  parts = []
  parts << "#{years} #{years == 1 ? 'year' : 'years'}" if years.positive?
  parts << "#{remainder} #{remainder == 1 ? 'month' : 'months'}" if remainder.positive?
  parts.join(" ")
end

def duration_between(start, finish)
  months = month_index(finish) - month_index(start) + 1
  raise ArgumentError, "#{start.strftime('%b %Y')} starts after #{finish.strftime('%b %Y')}" unless months.positive?

  format_duration(months)
end

# Returns [updated_text, [[old_line, new_line], ...]].
def roll_forward(text, as_of)
  changes = []
  updated = text.gsub(DATE_LINE) do
    old_line = Regexp.last_match(0)
    start_text = Regexp.last_match(1)
    finish_text = Regexp.last_match(2)
    finish = finish_text == "Present" ? as_of : parse_month(finish_text)
    new_line = "#{start_text} - #{finish_text} (#{duration_between(parse_month(start_text), finish)})"
    changes << [old_line, new_line] unless old_line == new_line
    new_line
  end
  [updated, changes]
end

def latest_resume
  dated = Dir.children(REPO_ROOT).filter_map do |name|
    match = FILE_NAME.match(name)
    next unless match

    [parse_month("#{match[2].capitalize} #{match[1]}"), name]
  end
  abort "No resume found in #{REPO_ROOT}" if dated.empty?

  dated.max_by(&:first)
end

as_of = Date.today
check_only = false
OptionParser.new do |opts|
  opts.banner = "Usage: bin/update-resume.rb [--check] [--as-of YYYY-MM]"
  opts.on("--check", "Report changes without writing anything") { check_only = true }
  opts.on("--as-of YYYY-MM", "Month to compute durations for (default: this month)") do |value|
    as_of = Date.strptime(value, "%Y-%m")
  end
end.parse!

source_month, source_name = latest_resume
if !check_only && month_index(as_of) < month_index(source_month)
  abort "#{source_name} is newer than #{as_of.strftime('%b %Y')}; refusing to write an older resume."
end

target_name = "#{as_of.strftime('%Y-%b').downcase}-tod-beardsley-resume.md"
updated, changes = roll_forward(File.read(File.join(REPO_ROOT, source_name)), as_of)

puts "Source: #{source_name}"
puts "As of:  #{as_of.strftime('%b %Y')}"
puts "#{changes.size} date line(s) changed:"
changes.each { |old_line, new_line| puts "  #{old_line}\n    -> #{new_line}" }

if check_only
  exit(changes.empty? ? 0 : 1)
end

File.write(File.join(REPO_ROOT, target_name), updated)
puts "Wrote:  #{target_name}"

unless target_name.casecmp?(source_name)
  puts "\nTo retire the old copy and commit:"
  puts "  git rm #{source_name}"
  puts "  git add #{target_name}"
  puts "  git commit -m 'Update resume for #{as_of.strftime('%B %Y')}'"
end
