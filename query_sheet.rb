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
NB_EXPORT_SPREADSHEET_ID = '1Jl_Gr-WcRstFhHNHGOVin9IAxfuCaXhNDnOAqOfHY8s'
NB_EXPORT_SHEET_ID = 'nationbuilder-people-export-2019-07-09-2131'

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

  keys = values.first

  values[1..-1].map do |row|
    row.each_with_index.reduce({}) do |obj, (value, index)|
      obj[keys[index]] = value
      obj
    end
  end
end

def get_ad_sheet_id(ad)
  assembly_district_sheets = read_sheet(
    ENV_VARS_SPREADSHEET_ID,
    DISTRICT_TO_SPREADSHEET_ID,
  )	
  assembly_district_sheets.find{|row| row['assembly_district'] == ad.to_s}['spreadsheet_id']
end

# Call this to verify that appending to a sheet works.
def test_append_sheet()
  values = read_sheet(NB_EXPORT_SPREADSHEET_ID, NB_EXPORT_SHEET_ID) 
  ad = 56
  append_user_to_ad_sheet(ad, values[0])
end

def append_user_to_ad_sheet(ad, user)
  user_for_ad_sheet = [
    [user['first_name'] + ' ' + user['last_name'], 
     user['nationbuilder_id'], 
     user['primary_address1'], # Perhaps replace with formatted address.
     user['phone_number'].empty? ? user['mobile_empty'] : user['phone_number'],
     user['email'],
     user['state_lower_district'],  # AD - perhaps replace with CC Sunlight's value.
    ]
  ]

  service.append_spreadsheet_value(
    get_ad_sheet_id(ad), 
    MASTER_SCHEMA_SHEET_ID, 
    Google::Apis::SheetsV4::ValueRange.new(values: user_for_ad_sheet),
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

def candidates_by_attribute(candidates, attribute, one_to_many=false)
  candidates.select do |candidate|
    candidate[attribute] &&
      candidate[attribute].length > 0
  end.reduce({}) do |obj, candidate|
    if obj[candidate[attribute]]
      obj[candidate[attribute]] << candidate
    else
      obj[candidate[attribute]] = one_to_many ? [candidate] : candidate
    end
    obj
  end
end

# Code that runs over the exported data from NationBuilder, does validation, and adds new users to the appropriate AD sheet.
def process_export_from_nb 
  assembly_district_sheets = read_sheet(
    ENV_VARS_SPREADSHEET_ID,
    DISTRICT_TO_SPREADSHEET_ID,
  )
  # Load all users from each sheet into an object for quick lookup.
  existing_candidates = candidates_by_attribute(  
    assembly_district_sheets.map{ |admapping|
      read_sheet(
        admapping['spreadsheet_id'],
        MASTER_SCHEMA_SHEET_ID,
      )
    }.flatten, 
    'RYBID',
  )

  # Get all candidates from the export.
  export_values = read_sheet(NB_EXPORT_SPREADSHEET_ID, NB_EXPORT_SHEET_ID)
  export_candidates = candidates_by_attribute(export_values, 'nationbuilder_id')
  export_candidates.each { |id, candidate|
    # See if user already exists
    if (existing_candidates[id]) 
      puts 'user exists'
      # TODO: Check if they're in the correct AD.
    else 
      puts 'new user'
      # TODO: Data validation
      # TODO: Append to correct AD sheet
    end
  }

end

validate_spreadsheets_columns
process_export_from_nb
# puts read_sheet(ARGV[0], ARGV[1])
