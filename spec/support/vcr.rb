# frozen_string_literal: true

require 'cgi'
require 'vcr'
require 'active_support/core_ext/hash/conversions'

VCR.configure do |c|
  c.configure_rspec_metadata!
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
  c.default_cassette_options = { match_requests_on: %i[method uri body] }

  c.filter_sensitive_data('bing-ads-oauth-client-id') { ENV['BING_ADS_OAUTH_CLIENT_ID'] }
  c.filter_sensitive_data('bing-ads-oauth-client-secret') do
    CGI.escape(ENV['BING_ADS_OAUTH_CLIENT_SECRET'])
  end
  c.filter_sensitive_data('bing-ads-oauth-refresh-token') do
    CGI.escape(ENV['BING_ADS_OAUTH_REFRESH_TOKEN'])
  end
  c.filter_sensitive_data('bing-ads-oauth-refresh-token') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'application/json'
      JSON.parse(interaction.response.body)['refresh_token']
    end
  end
  c.filter_sensitive_data('bing-ads-oauth-authentication-token') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'application/json'
      JSON.parse(interaction.response.body)['access_token']
    end
  end
  c.filter_sensitive_data('bing-ads-oauth-user-id') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'application/json'
      JSON.parse(interaction.response.body)['user_id']
    end
  end
  c.filter_sensitive_data('bing-ads-developer-token') { ENV['BING_ADS_DEVELOPER_TOKEN'] }
  c.filter_sensitive_data('bing-ads-account-id') { ENV['BING_ADS_ACCOUNT_ID'] }
  c.filter_sensitive_data('bing-ads-customer-id') { ENV['BING_ADS_CUSTOMER_ID'] }

  c.filter_sensitive_data('bing-ads-report-tracking-id') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'text/xml; charset=utf-8'
      Hash.from_xml(interaction.response.body)['Envelope']['Header']['TrackingId']
    end
  end
  c.filter_sensitive_data('bing-ads-report-request-id') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'text/xml; charset=utf-8'
      body = Hash.from_xml(interaction.response.body)['Envelope']['Body']
      if body['SubmitGenerateReportResponse']
        body['SubmitGenerateReportResponse']['ReportRequestId']
      end
    end
  end
  c.filter_sensitive_data('bing-ads-report-request-id') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'text/xml; charset=utf-8'
      body = Hash.from_xml(interaction.request.body)['Envelope']['Body']
      if body['PollGenerateReportRequest']
        body['PollGenerateReportRequest']['ReportRequestId']
      end
    end
  end
  c.filter_sensitive_data('bing-ads-oauth-authentication-token') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'text/xml; charset=utf-8'
      Hash.from_xml(interaction.request.body)['Envelope']['Header']['AuthenticationToken']
    end
  end
  c.filter_sensitive_data('bing-ads-report-download-id') do |interaction|
    if interaction.request.uri =~ %r{https://(.*)\?q=(.*)}
      Regexp.last_match(2)
    end
  end
  c.filter_sensitive_data('bing-ads-report-download-id') do |interaction|
    if interaction.response.headers['Content-Type'].first == 'text/xml; charset=utf-8'
      response = Hash.from_xml(interaction.response.body)
      report = response['Envelope']['Body']['PollGenerateReportResponse']
      if report && report ['ReportRequestStatus']
        if report['ReportRequestStatus']['ReportDownloadUrl'] =~ %r{https://(.*)\?q=(.*)}
          Regexp.last_match(2)
        end
      end
    end
  end

  c.before_record do |interaction|
    # auto-generate campaign_performance_report payload fixtures
    # spec/fixtures/ads/campaign_performance_report.json
    # spec/fixtures/ads/campaing_performance_report.csv
    next unless /ReportDownload/.match?(interaction.request.uri)
    if interaction.response.headers['Content-Type'].first == 'application/x-zip-compressed'
      # refactor zip into module
      csv_data = Zip::InputStream.open(StringIO.new(interaction.response.body)) do |archive_io|
        file_io = archive_io.get_next_entry.get_input_stream
        file_io.read
      end

      fixtures_dir = File.join('spec', 'fixtures', 'ads')
      File.open(File.join(fixtures_dir, 'campaign_performance_report.json'), 'wb') do |file|
        parser = SoapyBing::Ads::Parsers::ReportCsvParser.new(csv_data)
        file.write(JSON.pretty_generate(parser.rows))
      end
      File.open(File.join(fixtures_dir, 'campaign_performance_report.csv'), 'wb') do |file|
        file.write(csv_data)
      end
    end
  end

  c.before_record do |interaction, cassette|
    # auto-generate campaigns payload fixtures
    # spec/fixtures/ads/campaigns_by_account_id.json
    # spec/fixtures/ads/campaings_by_account_id.csv
    # spec/fixtures/ads/campaigns_by_campaign_ids.json
    # spec/fixtures/ads/campaings_by_campaign_ids.csv
    next unless /bulkdownloadresultfiles/.match?(interaction.request.uri)

    campaigns_ids = cassette.name =~ /by campaign_ids/
    fixture_name = "campaigns_by_#{campaigns_ids ? 'campaign_ids' : 'account_id'}"

    body_zip_entry_name = nil
    unzipped_body = Zip::InputStream.open(StringIO.new(interaction.response.body)) do |archive_io|
      entry = archive_io.get_next_entry
      body_zip_entry_name = entry.name
      entry.get_input_stream.read
    end

    unzipped_body.gsub!(ENV['BING_ADS_ACCOUNT_ID'], '123456')

    rows = SoapyBing::Ads::Parsers::BulkCsvParser.new(unzipped_body).rows[0..5]

    # Replace campaign names because it is sensitive data
    rows.map do |row|
      next unless row['Type'] == 'Campaign'
      row['Campaign'] = "Campaign #{row['Id']}"
    end

    modified_csv = CSV.generate do |csv|
      csv << rows.first.keys
      rows.each do |row|
        csv << row.values
      end
    end

    fixtures_dir = File.join('spec', 'fixtures', 'ads')
    File.open(File.join(fixtures_dir, "#{fixture_name}.csv"), 'wb') do |file|
      file.write(modified_csv)
    end

    File.open(File.join(fixtures_dir, "#{fixture_name}.json"), 'wb') do |file|
      file.write(JSON.pretty_generate(rows))
    end

    zipped_body = StringIO.new
    Zip::OutputStream.write_buffer(zipped_body) do |io|
      io.put_next_entry(body_zip_entry_name)
      io.write(modified_csv)
    end
    interaction.response.body = String.new(zipped_body.string, encoding: 'ASCII-8BIT')
  end

  # reduce response size for get_geo_locations vcr file
  c.before_record do |interaction|
    next unless /GeoLocations\.csv/.match?(interaction.request.uri)

    rows = CSV.parse(interaction.response.body)[0..5]

    modified_csv = CSV.generate do |csv|
      rows.each do |row|
        csv << row
      end
    end

    interaction.response.body = modified_csv
  end

  c.ignore_hosts 'codeclimate.com' # allow codeclimate-test-reporter to phone home
end
