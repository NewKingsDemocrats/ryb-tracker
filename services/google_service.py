from googleapiclient.discovery import build
from services.google_creds import GoogleCreds

class GoogleService:
    def __init__(self, type, version):
        self.type = type
        self.version = version

    def get_service(self):
        return build(self.type, self.version, credentials=GoogleCreds().credentials)
