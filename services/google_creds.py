from google.oauth2 import service_account

class GoogleCreds:
    SCOPES = ['https://www.googleapis.com/auth/drive']

    def __init__(self, creds_file='googleCreds.json'):
        self.credentials = self.get_credentials(creds_file)

    def get_credentials(self, creds_file):
        return service_account.Credentials.from_service_account_file(
            creds_file, scopes=self.SCOPES)
