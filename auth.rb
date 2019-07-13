require 'googleauth'

module GoogleApisService
  module Auth
    googleCreds = JSON.parse(File.read('googleCreds.json'))
    [
      'GOOGLE_PRIVATE_KEY',
      'GOOGLE_CLIENT_EMAIL',
      'GOOGLE_PROJECT_ID'
    ].each do |k|
      ENV[k] = googleCreds[k.gsub(/GOOGLE_/, '').downcase]
      puts ENV[k]
    end

    class << self
      def authorize(scope)
        authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
          scope: scope
        )
        authorizer.fetch_access_token!
        authorizer
      end
    end
  end
end

def initialize
  @service = Google::Apis::SheetsV4::SheetsService.new
  service.authorization = GoogleApisService::Auth.authorize(SCOPE)
end


SCOPES =
