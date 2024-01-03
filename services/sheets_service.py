from services.google_service import GoogleService

class SheetsService(GoogleService):
    def __init__(self):
        GoogleService.__init__(self, 'sheets', 'v4')
        self.service = self.get_service().spreadsheets()
