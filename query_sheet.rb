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
NB_EXPORT_SPREADSHEET_ID = '1Jl_Gr-WcRstFhHNHGOVin9IAxfuCaXhNDnOAqOfHY8s'
# NB_EXPORT_SPREADSHEET_ID = '1CM9S9hbN8TIw8maz1pp8WdV6tJklOq3ZPVCg_CFKMeo'
NB_EXPORT_SHEET_ID = 'nationbuilder-people-export-2019-07-09-2131'
INVALID_ADDRESSES_SPREADSHEET_ID = '1dlC9ZM1tMLW5XazyR6BVRDRapbllx_d6gko--41p7a8'
INVALID_ADS_SPREADSHEET_ID = '17GK6MpEz-tHK_h72Wrp68mu-Jx5a15FuYCYQD6F1iKE'
UPDATED_CANDIDATES_SPREADSHEET_ID = '13-xUnEJScMhvrBFq7niyd2ZWy1iO3M41Aro-L_Cwg8o'
MOVED_CANDIDATES_SPREADSHEET_ID = '10qTJW5MLbyf8jKNrFyQPYz_wpLsM3EG4Zgbnizv-fIU'

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
    standardize_phone_number_format(candidate['phone_number'])
  else
    standardize_phone_number_format(candidate['mobile_number'])
  end
end

def standardize_phone_number_format(phone_number)
  begin
    phone_number.split('').select do |c|
      c.match(/\d/)
    end.join('').match(/(\d{3})(\d{3})(\d{4})$/).to_a[1..-1].join('-')
  rescue
    nil
  end
end

def sheet_columns(spreadsheet_id, page_id)
  service.get_spreadsheet_values(
    spreadsheet_id,
    page_id + (page_id.match(/!/) ? '' : '!1:1'),
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
  # Get all candidates from the export.
  updated_candidates = []
  moved_candidates = []
  candidates_to_append = {}
  export_candidates.each do |id, export_candidate|
    unless (existing_candidates[id])
      process_new_candidate(export_candidate, candidates_to_append)
    end
  end
  add_candidates_to_spreadsheets(candidates_to_append)
  puts "#{
    candidates_to_append.values.reduce(0) do |sum, cands|
      sum += cands.count
      sum
    end
  } new candidates processed."
end

def existing_candidates
  # Load all candidates from each sheet into an object for quick lookup.
  @existing_candidates ||= candidates_by_attribute(
    existing_candidates_by_ad.values.flatten,
    'RYBID',
  )
end

def existing_candidates_by_ad
  @existing_candidates_by_ad ||=
    assembly_district_sheets.reduce({}) do |candidates, admapping|
      candidates[admapping['assembly_district']] = read_sheet(
        admapping['spreadsheet_id'],
        MASTER_SCHEMA_SHEET_ID,
      )
      candidates
    end
end

def export_candidates
  @export_candidates ||= formatted_candidates_to_import(
    candidates_by_attribute(
      read_sheet(NB_EXPORT_SPREADSHEET_ID, NB_EXPORT_SHEET_ID),
      'nationbuilder_id',
    )
  )
end

def check_and_move_existing_candidates
  candidates_to_move.each do |ad, candidates|
    append_candidates_to_spreadsheet(
      candidates.map do |candidate|
        candidate.values_at(*ad_spreadsheet_columns)
      end,
      assembly_district_sheets.find do |sheet|
        sheet['assembly_district'] == ad
      end['spreadsheet_id'],
    )
  end
  remove_outdated_candidiates
  puts "moved #{
    candidates_to_move.values.flatten.count
  } candidates"
end

def remove_outdated_candidiates
  current_moved_candidates_rows.each do |ad, rows|
    spreadsheet_id = assembly_district_sheets.find do |sheet|
      sheet['assembly_district'] == ad
    end['spreadsheet_id']
    sheet_id = candidate_view_sheet_id(spreadsheet_id)
    service.batch_update_spreadsheet(
      spreadsheet_id,
      Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new({
        requests: rows.map do |row|
          {
            delete_dimension:
              Google::Apis::SheetsV4::DeleteDimensionRequest.new({
                range: Google::Apis::SheetsV4::DimensionRange.new({
                  sheet_id: sheet_id,
                  dimension: 'ROWS',
                  start_index: row + 1,
                  end_index: row + 2
                })
              })
          }
        end
      }),
    )
  end
end

def candidate_view_sheet_id(spreadsheet_id)
  service
    .get_spreadsheet('1SDpSo1sD0DykFa82IiJOy9iSV7iJn9KaTFbmNBz_zqE')
    .sheets
    .find { |sheet| sheet.properties.title = MASTER_SCHEMA_SHEET_ID }
    .properties
    .sheet_id
end

def current_moved_candidates_rows
  moved_candidates_by_current_ad
    .reduce({}) do |ad_rows, (current_ad, moved_candidates)|
      moved_candidates.each do |moved_candidate|
        index =
          existing_candidates_by_ad[current_ad]
            .find_index do |existing_candidate|
              moved_candidate['RYBID'] == existing_candidate['RYBID']
            end
        if ad_rows[current_ad]
          ad_rows[current_ad] << index - ad_rows[current_ad].length
        else
          ad_rows[current_ad] = [index]
        end
      end
      ad_rows
    end
end

def moved_candidates_by_current_ad
  candidates_to_move.values.flatten.reduce({}) do |candidates, candidate|
    current_ad = existing_candidates[candidate['RYBID']]['AD']
    if candidates[current_ad]
      candidates[current_ad] << candidate
    else
      candidates[current_ad] = [candidate]
    end
    candidates
  end
end

def candidates_to_move
  @candidates_to_move ||=
    existing_candidates.reduce({}) do |candidates, (id, candidate)|
      current_ad, current_ed = candidate.values_at('AD', 'ED')
      new_ad, new_ed = get_ad_and_ed_from_cc_sunlight(candidate['Address']).values_at(:ad, :ed)
      unless current_ad == new_ad
        updated_candidate = candidate.dup
        updated_candidate['AD'] = new_ad
        updated_candidate['ED'] = new_ed
        if candidates[new_ad]
          candidates[new_ad] << updated_candidate
        else
          candidates[new_ad] = [updated_candidate]
        end
      end
      candidates
    end
end

def process_new_candidate(export_candidate, candidates_to_append)
  puts 'new candidate'
  export_candidate_ad = export_candidate['AD']
  if ad_sheet_exists?(assembly_district_sheets, export_candidate_ad)
    if candidates_to_append[export_candidate_ad]
      candidates_to_append[export_candidate_ad] <<
        export_candidate.values_at(*ad_spreadsheet_columns)
    else
      candidates_to_append[export_candidate_ad] =
        [ export_candidate.values_at(*ad_spreadsheet_columns) ]
    end
  else
    create_new_ad_spreadsheet(export_candidate_ad)
    candidates_to_append[export_candidate_ad] =
      [ export_candidate.values_at(*ad_spreadsheet_columns) ]
  end
end

def ad_sheet_exists?(assembly_district_sheets, ad)
  assembly_district_sheets.find do |sheet|
    sheet['assembly_district'] == ad
  end
end

def ad_spreadsheet_columns
  @ad_spreadsheet_columns ||= sheet_columns(
    MASTER_SCHEMA_SPREADSHEET_ID,
    MASTER_SCHEMA_SHEET_ID + '!A:H',
  )[0]
end

def add_candidates_to_spreadsheets(candidates_to_append)
  candidates_to_append.each do |ad, candidates|
    append_candidates_to_spreadsheet(
      candidates,
      assembly_district_sheets.find do |sheet|
        sheet['assembly_district'] == ad
      end['spreadsheet_id'],
    )
  end
end

def ads_match?(existing_candidiate, export_candidate)
  existing_candidiate['AD'].to_s == export_candidate['AD'].to_s
end

def basic_info_changed?(existing_candidate, export_candidate)
   !(export_candidate == existing_candidate)
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
    candidate['primary_zip'] &&
    candidate['primary_zip'].length > 0 &&
    candidate['primary_zip'].match(/\d{5}/) &&
    candidate['primary_zip'].match(/112/)
end

def titleize(str)
  str
    .to_s.split(/ |\_|\-/)
    .map(&:capitalize)
    .join(' ')
end

def formatted_candidates_to_import(candidates)
  candidiates_with_invalid_addresses = []
  candidiates_with_invalid_ads = []
  formatted_candidates =
    candidates.reduce({}) do |cands_to_imp, (id, export_candidate)|
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
      unless ad_valid?(formatted_attributes['AD'])
        candidiates_with_invalid_ads << export_candidate.values
        next cands_to_imp
      end
      cands_to_imp[id] = {
        'Name' => "#{
          export_candidate['first_name']
        } #{
          export_candidate['last_name']
        }",
        'Type' => ARGV[1] || '2020',
        'RYBID' => export_candidate['nationbuilder_id'],
        'Phone' => format_phone_number(export_candidate),
        'Email' => export_candidate['email'],
      }.merge(formatted_attributes)
      cands_to_imp
    end
    add_invalid_candidates_to_spreadsheets(
      candidiates_with_invalid_addresses,
      candidiates_with_invalid_ads
    )
  formatted_candidates
end

def ad_valid?(ad)
  (41..60) === ad&.to_i || 64 == ad&.to_i
end

def add_invalid_candidates_to_spreadsheets(
  candidiates_with_invalid_addresses,
  candidiates_with_invalid_ads
)
  if candidiates_with_invalid_addresses.length > 0
    append_candidates_to_spreadsheet(
      candidiates_with_invalid_addresses.select do |candidate|
        !existing_candidates_with_invalid_addresses
          .keys
          .include?(candidate.first)
      end,
      INVALID_ADDRESSES_SPREADSHEET_ID,
      NB_EXPORT_SHEET_ID,
    )
  end
  if candidiates_with_invalid_ads.length > 0
    append_candidates_to_spreadsheet(
      candidiates_with_invalid_ads.select do |candidate|
        !existing_candidates_with_invalid_ads
          .keys
          .include?(candidate.first)
      end,
      INVALID_ADS_SPREADSHEET_ID,
      NB_EXPORT_SHEET_ID,
    )
  end
end

def existing_candidates_with_invalid_addresses
  # Load all candidates from each sheet into an object for quick lookup.
  @existing_candidates_with_invalid_addresses ||= candidates_by_attribute(
    read_sheet(
      INVALID_ADDRESSES_SPREADSHEET_ID,
      NB_EXPORT_SHEET_ID,
    ),
    'nationbuilder_id',
  )
end

def existing_candidates_with_invalid_ads
  # Load all candidates from each sheet into an object for quick lookup.
  @existing_candidates_with_invalid_ads ||= candidates_by_attribute(
    read_sheet(
      INVALID_ADS_SPREADSHEET_ID,
      NB_EXPORT_SHEET_ID,
    ),
    'nationbuilder_id',
  )
end

def create_new_ad_spreadsheet(ad)
  new_ad_spreadsheet = drive_service.copy_file(
    MASTER_SCHEMA_SPREADSHEET_ID,
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

case ARGV[0]
when /import/
  process_export_from_nb
when /check/
  check_and_move_existing_candidates
else
  puts "\npass either an \"import\" flag (and an optional \"task\" flag)\n"\
    'to IMPORT candidates from the RYB NationBuilder dump, e.g.'\
    "\n\truby query_sheet.rb import 2019"\
    "\n\n\t\t\t***OR***\n\n"\
    "a \"check\" flag to move any of the imported candidates to their\n"\
    'appropriate AD spreadsheets if their AD has changed, e.g.'\
    "\n\truby query_sheet.rb check"
end
