require 'process_helper'
require 'tmpdir'
require 'open-uri'

module Cbm
  # Creates/updates pipeline via fly
  class PipelineUpdater
    include Logger
    include ProcessHelper

    attr_reader :url, :username, :password, :team, :pipeline_file, :fly_path
    attr_reader :load_vars_from_entries, :pipeline_name

    # TODO: do http://www.refactoring.com/catalog/introduceParameterObject.html
    # rubocop:disable Metrics/ParameterLists
    def initialize(url, username, password, team, pipeline_file, load_vars_from_entries, pipeline_name)
      @url = url
      @username = username
      @password = password
      @team = team
      @pipeline_file = pipeline_file
      @fly_path = "#{Dir.mktmpdir}/fly"
      @load_vars_from_entries = load_vars_from_entries
      @pipeline_name = pipeline_name
    end

    def set_pipeline
      download_fly

      log 'Logging into concourse...'
      team_argument = team != nil && team != "" ? "--team-name=#{team}" : ''
      process(
        "#{fly_path} --target=concourse -k login --concourse-url=#{url} #{team_argument} -u #{username} -p #{password}",
        timeout: 5)

      log 'Updating pipeline...'
      process(generate_set_pipeline_cmd, timeout: 5, input_lines: %w(y))

      log 'Unpausing pipeline...'
      unpause_pipeline_cmd = "#{fly_path} --target=concourse unpause-pipeline " \
        "--pipeline=#{pipeline_name}"
      process(unpause_pipeline_cmd, timeout: 5)
    end

    private

    def generate_set_pipeline_cmd
      load_vars_from_options = load_vars_from_entries.reduce('') do |options, entry|
        "#{options}--load-vars-from=#{entry} "
      end.strip
      "#{fly_path} --target=concourse set-pipeline --config=#{pipeline_file} " \
        "--pipeline=#{pipeline_name} #{load_vars_from_options}"
    end

    def download_fly
      log 'Trying to download fly executable...'

      fly_download_url = "https://github.com/concourse/concourse/releases/download/v3.8.0/fly_linux_amd64"
      log fly_download_url
      read_binary_open_mode = 'rb'
      proxy_uri = URI.parse(ENV.fetch('PROXY_URI'))
      stream = open(
        fly_download_url,
        read_binary_open_mode,
        :proxy_http_basic_authentication => [proxy_uri, ENV.fetch('PROXY_USER'), ENV.fetch('PROXY_PASSWORD')]
      )
      IO.copy_stream(stream, fly_path)
      process("chmod +x #{fly_path}")
    end
  end
end
