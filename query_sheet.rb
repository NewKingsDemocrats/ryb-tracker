#!/usr/bin/env ruby
require 'json'
require 'set'
require 'pry'
require 'googleauth'
require 'google/apis/sheets_v4'

ENV_VARS_SPREADSHEET_ID = '10yQzyt4_JMZmFeVYLaWi2DinP-oPiq6cfwXfSFsoEvw'
DISTRICT_TO_SPREADSHEET_ID = 'district to spreadsheet ID'
MASTER_SCHEMA_SPREADSHEET_ID = '1KABFR083wl6Ok0WEIsPs1lefZt7U9PJz1iuneQ7Prc0'
MASTER_SCHEMA_SHEET_ID = 'Candidate View'

def validate_spreadsheets_columns
  if invalid_speadsheets_columns && invalid_speadsheets_columns.length > 0
    error_message = "The following spreadsheets had errors:\n"
    invalid_speadsheets_columns.each do |invalid_spreadsheet|
      ad,
      spreadsheet_id,
      missing_columns,
      superfluous_columns = invalid_spreadsheet.values_at(
        :assembly_district,
        :spreadsheet_id,
        :missing_columns,
        :superfluous_columns,
      )
      error_message = add_errors_to_message(
        error_message,
        ad,
        spreadsheet_id,
        missing_columns,
        superfluous_columns,
      )
    end
    puts error_message
    raise "Check spreadsheet schemas."
  else
    true
  end
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

  test_append_sheet(values[2])

#  keys = values.first
#
#  values[1..-1].map do |row|
#    row.each_with_index.reduce({}) do |obj, (value, index)|
#      obj[keys[index]] = value
#      obj
#    end
#  end
end

def test_append_sheet(value)
  puts 'Testing append sheet'
  ad = 56
  append_user_to_ad_sheet(ad, value)
end

def append_user_to_ad_sheet(ad, user)
  # TODO(turnbull): Get the correct sheet ID from the ad.
  ad_sheet_id = '1GMjgr9iws3mkuCM5Le7TQOEbjnB5d0DVMPDMbRcOEqw'
  # TODO(turnbull): Turn the user object into the formatted value for the new sheet.
  value = Google::Apis::SheetsV4::ValueRange.new(values: [user])

  service.append_spreadsheet_value(
    ad_sheet_id, 
    MASTER_SCHEMA_SHEET_ID, 
    value,
    value_input_option: 'RAW',
  )
end

def sheet_columns(spreadsheet_id, page_id)
  service.get_spreadsheet_values(
    spreadsheet_id,
    page_id + '!1:1',
  ).values
end

def invalid_speadsheets_columns
  assembly_district_sheets = read_sheet(
    ENV_VARS_SPREADSHEET_ID,
    DISTRICT_TO_SPREADSHEET_ID,
  )
  master_schema_columns = sheet_columns(
    MASTER_SCHEMA_SPREADSHEET_ID,
    MASTER_SCHEMA_SHEET_ID,
  )
  assembly_district_sheets.reduce([]) do |arr, ad_sheet|
    ad_sheet_columns = sheet_columns(
      ad_sheet['spreadsheet_id'],
      MASTER_SCHEMA_SHEET_ID,
    )
    unless ad_sheet_columns == master_schema_columns
      arr << {
        assembly_district: ad_sheet['assembly_district'],
        spreadsheet_id: ad_sheet['spreadsheet_id'],
        missing_columns: missing_columns(
          master_schema_columns,
          ad_sheet_columns,
        ),
        superfluous_columns: superfluous_columns(
          master_schema_columns,
          ad_sheet_columns,
        ),
      }
    end
    arr
  end
end

def missing_columns(schema_columns, ad_sheet_columns)
  (Set.new(*schema_columns) - Set.new(*ad_sheet_columns)).to_a
end

def superfluous_columns(schema_columns, ad_sheet_columns)
  (Set.new(*ad_sheet_columns) - Set.new(*schema_columns)).to_a
end

def add_errors_to_message(
  error_message,
  ad,
  spreadsheet_id,
  missing_columns,
  superfluous_columns
)
  ad_message = "\tAD #{ad} (spreadsheet ID: #{spreadsheet_id}) "
  if missing_columns && missing_columns.length > 0
    ad_message += "is missing the following columns:\n\t\t" +
      missing_columns.join("\n\t\t")
    if superfluous_columns && superfluous_columns.length > 0
      ad_message += "\n\tand "
    end
  end
  if superfluous_columns && superfluous_columns.length > 0
    ad_message += "has the following superfluous columns:\n\t\t" +
      superfluous_columns.join("\n\t\t")
  end
  error_message += ad_message + "\n"
end

validate_spreadsheets_columns

# puts read_sheet(ARGV[0], ARGV[1])
