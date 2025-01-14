#!/opt/puppetlabs/bolt/bin/ruby

require 'fileutils'
require 'json'

require 'tempfile'
require 'tmpdir'

require 'fileutils'


def bump_version(file)
  # Read content from metadata.json file
  warn "file: '#{file}'"
  raise('No metadata.json path given') unless file
  dir = File.dirname(file)
  content = File.read(file)
  data = JSON.parse(content)

  # bump y version
  parts = data['version'].split(/[\.-]/)
  parts[1] = (parts[1].to_i + 1).to_s
  parts[2] = '0'
  new_version = parts.join('.')
  data['version'] = new_version

  File.open(file,'w'){|f| f.puts(JSON.pretty_generate(data)) }
  warn "\n\n++ processed '#{file}'"

  if new_version
    next if file =~ /\.erb$/
    changelog_file = File.join(dir,'CHANGELOG')
    changelog = File.read(changelog_file)
    require 'date'
    new_lines = []
    new_lines << DateTime.now.strftime("* %a %b %d %Y Chris Tessmer <chris.tessmer@onyxpoint.com> - #{new_version}")
    new_lines << '- Update from camptocamp/systemd to puppet/systemd'
    changelog = new_lines.join("\n") + "\n\n" + changelog
    File.open(changelog_file,'w'){|f| f.puts changelog }
  end
end


def tmp_bundle_rake_execs(repo_path, tasks)
  Dir.mktmpdir('tmp_bundle_rake_execs') do |tmp_dir|
    Dir.chdir repo_path
    gemfile_lock = false
    if File.exist?('Gemfile.lock')
      gemfile_lock = File.expand_path('Gemfile.lock',tmp_dir)
      FileUtils.cp File.join(repo_path, 'Gemfile.lock'), gemfile_lock
    end
    results = []
    require 'bundler'
    require 'rake'
    Bundler.with_unbundled_env do
      sh "/opt/puppetlabs/bolt/bin/bundle config path .vendor/bundle &> /dev/null"
      sh "/opt/puppetlabs/bolt/bin/bundle install &> /dev/null"
      tasks.each do |task|
        puts
        cmd = "/opt/puppetlabs/bolt/bin/bundle exec /opt/puppetlabs/bolt/bin/rake #{task}"
        results << sh(cmd)
      end
      if gemfile_lock
        FileUtils.cp gemfile_lock, File.join(repo_path, 'Gemfile.lock')
      else
        FileUtils.rm('Gemfile.lock')
      end
    end
    unless results.all?{ |x| x }
      warn 'bad result'
    end
  end
end


# ARGF hack to allow use run the task directly as a ruby script while testing
if ARGF.filename == '-'
  stdin = ''
  warn "ARGF.file.lineno: '#{ARGF.file.lineno}'"
  stdin = ARGF.file.read
  warn "== stdin: '#{stdin}'"
  params = JSON.parse(stdin)
  file = params['filename']
else
  file = ARGF.filename
end

# Read content from metadata.json file
warn "file: '#{file}'"
raise('No metadata.json path given') unless file
content = JSON.parse File.read(file)

# Transform content
warn "\n== Modernizing metadata.json content"
original_content_str = content.to_s

#regexp_for_low_high_bounds = %r[\A(?<low_op>>=?) (?<low_ver>\d+.*) (?<high_op><=?) (?<high_ver>\d+.*)\Z]

content['requirements'].select{|x| x['name'] == 'puppet' }.map do |x|
  #x['version_requirement'].gsub!( regexp_for_low_high_bounds ) do |y|
  #  m = Regexp.last_match
  #  "#{m[:low_op} #{m[:low_ver]} >= 6.22.1 < 8.0.0"
  #end
  x['version_requirement'] = '>= 6.22.1 < 8.0.0'
end

dep_sections = [
  content['dependencies'],
  (content['simp']||{})['optional_dependencies']
].select{|x| x }
dep_sections.each do |dependencies|
  dependencies.select{|x| x['name'] == 'camptocamp/systemd' }.map do |x|
    x['name'] = 'puppet/systemd'
    x['version_requirement'] = '>= 3.0.0 < 4.0.0'
  end
  dependencies.select{|x| x['name'] == 'puppetlabs/stdlib' }.map do |x|
    x['version_requirement'] = '>= 6.6.0 < 8.0.0'  # FIXME: is >= 6.6.0 necessary?
  end
end

# Write content back to original file
File.open(file, 'w') { |f| f.puts JSON.pretty_generate(content) }

if content.to_s == original_content_str
  warn '  == content unchanged'
else
  warn '  ++ content was changed!'
  repo_path = File.dirname file
  bump_version(file) # Not needed so soon
  tmp_bundle_rake_execs(repo_path, ['pkg:check_version', 'pkg:compare_latest_tag'])
end


# Sanity check: Validate that the file is still valid JSON
# NOTE: Handle heavier, gitlab/domain-aware lint checks in other tasks
warn "\n== Running a test json load #{file} to validate its syntax"
require 'json'
JSON.parse File.read(file)
warn "  ++ Test load (JSON syntax)  on #{file} succeeded!"

warn "\n\nFINIS: #{__FILE__}"
