#!/usr/bin/env ruby
require 'json'
require 'googleauth'
require 'google/apis/sheets_v4'
require 'pry'

ENV_VARS_SPREADSHEET_ID = '10yQzyt4_JMZmFeVYLaWi2DinP-oPiq6cfwXfSFsoEvw'
ENV_VARS_PAGE_ID = 'district to spreadsheet ID'
MASTER_SCHEMA_SPREADSHEET_ID = '1KABFR083wl6Ok0WEIsPs1lefZt7U9PJz1iuneQ7Prc0'

def validate_spreadsheet_sheets_and_columns

end

def service
  @service ||= begin
    s = Google::Apis::SheetsV4::SheetsService.new
    s.authorization = authorize_service
    s
  rescue
    raise 'Could not authorize service.'
  end
end

def authorize_service
  googleCreds = JSON.parse(File.read('googleCreds.json'))

  [
    'GOOGLE_PRIVATE_KEY',
    'GOOGLE_CLIENT_EMAIL',
    'GOOGLE_PROJECT_ID'
  ].each do |k|
    ENV[k] = googleCreds[k.gsub(/GOOGLE_/, '').downcase]
  end

  authorizer = Google::Auth::ServiceAccountCredentials
    .make_creds(scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS)
  authorizer.fetch_access_token!
  authorizer
end

def read_sheet(spreadsheet_id, range)
  values = service.get_spreadsheet_values(
    spreadsheet_id,
    range,
  ).values

  keys = values.first

  values[1..-1].map do |row|
    row.each_with_index.reduce({}) do |obj, (value, index)|
      obj[keys[index]] = value
      obj
    end
  end
end

# def get_spreadsheet_info(spreadsheet_id)
#   ss_info = service.get_spreadsheet(spreadsheet_id)
#   binding.pry
# end

# get_spreadsheet_info(ARGV[0])

puts read_sheet(ARGV[0], ARGV[1])
