#!/usr/bin/env ruby
require 'json'
require 'set'
require 'pry'
require 'googleauth'
require 'google/apis/sheets_v4'
require 'google/apis/drive_v3'

ENV_VARS_SPREADSHEET_ID = '10yQzyt4_JMZmFeVYLaWi2DinP-oPiq6cfwXfSFsoEvw'
DISTRICT_TO_SPREADSHEET_ID = 'district to spreadsheet ID'
MASTER_SCHEMA_SPREADSHEET_ID = '1KABFR083wl6Ok0WEIsPs1lefZt7U9PJz1iuneQ7Prc0'
MASTER_SCHEMA_SHEET_ID = 'Candidate View'
# NB_EXPORT_SPREADSHEET_ID = '1Jl_Gr-WcRstFhHNHGOVin9IAxfuCaXhNDnOAqOfHY8s'
NB_EXPORT_SPREADSHEET_ID = '1CM9S9hbN8TIw8maz1pp8WdV6tJklOq3ZPVCg_CFKMeo'
NB_EXPORT_SHEET_ID = 'nationbuilder-people-export-2019-07-09-2131'
INVALID_ADDRESSES_SPREADSHEET_ID = '1oh5Zxl4OpgjxQZs3gKLJ4u6IXRVJo20ocXldf2KBGDw'
INVALID_ADS_SPREADSHEET_ID = '17GK6MpEz-tHK_h72Wrp68mu-Jx5a15FuYCYQD6F1iKE'
UPDATED_CANDIDATES_SPREADSHEET_ID = '1GgRV5mOZPzA9tTPDKx90ejvkXbTyTM8HaF8OWI3JmV4'
MOVED_CANDIDATES_SPREADSHEET_ID = '1tX0vGXrgXSXl3JBifoWfdeFpFfkrnNLy22GZeOTamjw'

def spreadsheets_columns_valid?
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
    false
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

def drive_service
  @drive_service ||= begin
    s = Google::Apis::DriveV3::DriveService.new
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
    .make_creds(scope: Google::Apis::SheetsV4::AUTH_DRIVE)
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

# def get_ad_sheet_id(ad)
#   assembly_district_sheets = read_sheet(
#     ENV_VARS_SPREADSHEET_ID,
#     DISTRICT_TO_SPREADSHEET_ID,
#   )
#   assembly_district_sheets.find do |row|
#     row['assembly_district'] == ad.to_s
#   end['spreadsheet_id']
# end
#
# # Call this to verify that appending to a sheet works.
# def test_append_sheet()
#   values = read_sheet(NB_EXPORT_SPREADSHEET_ID, NB_EXPORT_SHEET_ID)
#   ad = 56
#   append_candidate_to_ad_sheet(ad, values[0])
# end
#
# def append_candidate_to_ad_sheet(ad, candidate)
#   append_candidate_to_spreadsheet(candidate, get_ad_sheet_id(ad))
# end

def append_candidate_to_spreadsheet(
  candidate,
  spreadsheet_id,
  range=MASTER_SCHEMA_SHEET_ID,
  error_sheet=false
)
  service.append_spreadsheet_value(
    spreadsheet_id,
    range,
    Google::Apis::SheetsV4::ValueRange.new(
      values:
        error_sheet ? [ candidate.values ] : candidate_for_ad_sheet(candidate),
    ),
    value_input_option: 'RAW',
  )
end

def append_candidates_to_spreadsheet(
  candidiates,
  spreadsheet_id,
  range=MASTER_SCHEMA_SHEET_ID
)
  service.append_spreadsheet_value(
    spreadsheet_id,
    range,
    Google::Apis::SheetsV4::ValueRange.new(values: candidiates),
    value_input_option: 'RAW',
  )
end

def candidate_for_ad_sheet(candidate)
  [
    [
      "#{candidate['first_name']} #{candidate['last_name']}",
      candidate['nationbuilder_id'],
      format_address(candidate), # Perhaps replace with formatted address.
      format_phone_number(candidate),
      candidate['email'],
      candidate['ad'],  # AD - perhaps replace with CC Sunlight's value.
      candidate['ed'],
    ]
  ]
end

def format_phone_number(candidate)
  unless candidate['phone_number'].empty?
    candidate['phone_number']
  else
    candidate['mobile_number']
  end
end

def sheet_columns(spreadsheet_id, page_id)
  service.get_spreadsheet_values(
    spreadsheet_id,
    page_id + '!1:1',
  ).values
end

def invalid_speadsheets_columns
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

def assembly_district_sheets
  unless @ad_spreadsheets_cache_valid
    @assembly_district_sheets =
      read_sheet(ENV_VARS_SPREADSHEET_ID, DISTRICT_TO_SPREADSHEET_ID)
    @ad_spreadsheets_cache_valid = true
    @assembly_district_sheets
  end
  @assembly_district_sheets
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

# Code that runs over the exported data from NationBuilder, does validation, and adds new candidates to the appropriate AD sheet.
def process_export_from_nb
  # Load all candidates from each sheet into an object for quick lookup.
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
  raw_export_candidates = candidates_by_attribute(
    export_values,
    'nationbuilder_id',
  )
  export_candidates = formatted_candidates_to_import(raw_export_candidates)
  changed_candidates = []
  moved_candidates = []
  ad_spreadsheet_columns = sheet_columns(
    MASTER_SCHEMA_SPREADSHEET_ID,
    MASTER_SCHEMA_SHEET_ID,
  )[0]
  candidiates_to_append = {}
  export_candidates.each do |id, export_candidate|
    # See if candidate already exists
    if (existing_candidates[id])
      puts 'candidate exists'
      unless ads_match?(existing_candidates[id], export_candidate)
        moved_candidates <<
          export_candidate.values_at(*ad_spreadsheet_columns).compact
      end
      if basic_info_changed?(existing_candidates[id], export_candidate)
        changed_candidates <<
          export_candidate.values_at(*ad_spreadsheet_columns).compact
      end
    else
      puts 'new candidate'
      export_candidate_ad = export_candidate['AD']
      if assembly_district_sheets.find do |sheet|
        sheet['assembly_district'] == export_candidate_ad
      end
        if candidiates_to_append[export_candidate_ad]
          candidiates_to_append[export_candidate_ad] <<
            export_candidate.values_at(*ad_spreadsheet_columns).compact
        else
          candidiates_to_append[export_candidate_ad] =
            [ export_candidate.values_at(*ad_spreadsheet_columns).compact ]
        end
      else
        create_new_ad_spreadsheet(export_candidate_ad)
        candidiates_to_append[export_candidate_ad] =
          [ export_candidate.values_at(*ad_spreadsheet_columns).compact ]
      end
    end
  end
  append_candidates_to_spreadsheet(
    changed_candidates,
    UPDATED_CANDIDATES_SPREADSHEET_ID,
  )
  append_candidates_to_spreadsheet(
    moved_candidates,
    MOVED_CANDIDATES_SPREADSHEET_ID,
  )
  candidiates_to_append.each do |ad, candidates|
    append_candidates_to_spreadsheet(
      candidates,
      assembly_district_sheets.find do |sheet|
        sheet['assembly_district'] == ad
      end['spreadsheet_id'],
    )
  end
end

# def move_candidate_between_ads(candidate, current_ad, new_ad)
#
# end

def ads_match?(existing_candidiate, export_candidate)
  existing_candidiate['AD'].to_s == export_candidate['AD'].to_s
end

def basic_info_changed?(existing_candidate, export_candidate)
  !existing_candidate.merge(export_candidate) == existing_candidate
end

def column_to_letter(num)
  char = (num % 26 + 65).chr
  remainder = num/26
  if num >= 26
    column_to_letter(remainder - 1) + char
  else
    char
  end
end

def get_ad_and_ed_from_cc_sunlight(address)
  base_uri = 'https://ccsunlight.org/api/v1/address/'
  uri = URI(base_uri + CGI.escape(address))
  request = Net::HTTP::Get.new(path=uri)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  ad, ed = JSON.parse(response.body).values_at('ad', 'ed')
  {
    ad: ad.to_s,
    ed: ed.to_s,
  }
end

def format_address(candidate)
  return nil unless candidate_address_valid?(candidate)
  "#{
    titleize(candidate['primary_address1'])
  }#{
    if candidate['primary_address2'] && candidate['primary_address2'].length > 0
      ' ' + candidate['primary_address2']
    else
      ''
    end
  }, #{
    titleize(candidate['primary_city'])
  }, #{
    candidate['primary_state'].upcase
  } #{
    candidate['primary_zip'].match(/\d{5}/).to_s
  }"
end

def candidate_address_valid?(candidate)
  candidate['primary_address1'] &&
    candidate['primary_address1'].length > 0 &&
    candidate['primary_city'] &&
    candidate['primary_city'].length > 0 &&
    candidate['primary_city'].match(/brooklyn|new york/i) &&
    candidate['primary_state'] &&
    candidate['primary_state'].length > 0 &&
    candidate['primary_state'].match(/ny/i) &&
    candidate['primary_zip'] &&
    candidate['primary_zip'].length > 0 &&
    candidate['primary_zip'].match(/\d{5}/)
end

def titleize(str)
  str
    .to_s.split(/ |\_|\-/)
    .map(&:capitalize)
    .join(' ')
end

def formatted_candidates_to_import(export_candidates)
  candidiates_with_invalid_addresses = []
  formatted_candidates =
    export_candidates.reduce({}) do |cands_to_imp, (id, export_candidate)|
      formatted_attributes = {}
      formatted_attributes['Address'] = format_address(export_candidate)
      unless formatted_attributes['Address']
        candidiates_with_invalid_addresses << export_candidate.values
        next cands_to_imp
      end
      puts formatted_attributes['Address']
      formatted_attributes['AD'], formatted_attributes['ED'] =
        get_ad_and_ed_from_cc_sunlight(formatted_attributes['Address'])
          .values_at(:ad, :ed)
      puts "AD: #{
        formatted_attributes['AD']
      }, ED: #{
        formatted_attributes['ED']
      }"
      cands_to_imp[id] = {
        'Name' => "#{
          export_candidate['first_name']
        } #{
          export_candidate['last_name']
        }",
        'RYBID' => export_candidate['nationbuilder_id'],
        'Phone' => format_phone_number(export_candidate),
        'Email' => export_candidate['email'],
      }.merge(formatted_attributes)
      cands_to_imp
    end
  if candidiates_with_invalid_addresses.length > 0
    append_candidates_to_spreadsheet(
      candidiates_with_invalid_addresses,
      INVALID_ADDRESSES_SPREADSHEET_ID,
      NB_EXPORT_SHEET_ID,
    )
  end
  formatted_candidates
end

def ad_match?(candidiate, new_candidate)
  candidate['ad'] == new_candidate['ad']
end

def create_new_ad_spreadsheet(ad)
  new_ad_spreadsheet = drive_service.copy_file(
    '1KABFR083wl6Ok0WEIsPs1lefZt7U9PJz1iuneQ7Prc0',
    Google::Apis::DriveV3::File.new({
      name: "AD #{ad}",
      parents: ['16NtRayVsCalmmhsOurTBA_BXFwejbV25'],
    }),
  )
  service.append_spreadsheet_value(
    ENV_VARS_SPREADSHEET_ID,
    DISTRICT_TO_SPREADSHEET_ID,
    Google::Apis::SheetsV4::ValueRange.new(
      values: [[ad, new_ad_spreadsheet.id]]
    ),
    value_input_option: 'RAW',
  )
  @ad_spreadsheets_cache_valid = false
  new_ad_spreadsheet
end

process_export_from_nb
# binding.pry

# puts "the spreadsheet schemas are #{spreadsheets_columns_valid? ? '' : 'not '}valid"
