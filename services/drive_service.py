from services.google_service import GoogleService

class DriveService(GoogleService):
    def __init__(self):
        GoogleService.__init__(self, 'drive', 'v3')
        self.service = self.get_service().drive()
