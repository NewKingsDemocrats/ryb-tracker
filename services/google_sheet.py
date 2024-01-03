from services.sheets_service import SheetsService

class GoogleSheet(SheetsService):
    def __init__(self, spreadsheet_id):
        SheetsService.__init__(self)
        self.spreadsheet_id = spreadsheet_id
        self.first_sheet_title = self.get_first_sheet_title()

    def values(self):
        vals = self.values_by_range(self.first_sheet_title)
        vals_as_dicts = []
        cols = vals[0]
        for row in vals[1:]:
            row_as_dict = {}
            for i, val in enumerate(row):
                row_as_dict[cols[i]] = val
            vals_as_dicts.append(row_as_dict)
        return vals_as_dicts

    def get_first_sheet_title(self):
        return self.service \
                   .get(spreadsheetId=self.spreadsheet_id) \
                   .execute()['sheets'][0]['properties']['title']

    def columns(self):
        return self.values_by_range(self.first_sheet_title + '!1:1')

    def values_by_range(self, range):
        return self.service \
                   .values() \
                   .get(
                       spreadsheetId=self.spreadsheet_id,
                       range=range) \
                   .execute()['values']
