from re import findall, match
from services.google_sheet import GoogleSheet

class FormattedCandidate:
    ENV_VARS_SPREADSHEET_ID = '10yQzyt4_JMZmFeVYLaWi2DinP-oPiq6cfwXfSFsoEvw'

    def __init__(self, raw_data, candidate_type='2020'):
        self.candidate_type = candidate_type
        self.attributes = self.get_attributes(raw_data)

    def get_attributes(self, raw_data):
        excel_formulae = self.get_excel_formulae()
        return {
            'Name': self.get_name(raw_data),
            'Type': self.candidate_type,
            'RYBID': self.get_rybid(raw_data),
            'Phone': self.format_phone_number(raw_data),
            'Email': self.get_email(self, raw_data),
            'Status': excel_formulae['Status'],
            'Pronouns': excel_formulae['Pronouns'],
            'Enough': excel_formulae['Enough'],
            'Seats': excel_formulae['Seats'],
            'Sigs': excel_formulae['Sigs'],
        }

    def get_name(self, raw_data):
        return f'{raw_data["first_name"]} {raw_data["last_name"]}'

    def get_rybid(self, raw_data):
        return raw_data['nationbuilder_id']

    def get_email(self, raw_data):
        return raw_data['email']

    def format_phone_number(self, raw_data):
        if raw_data['phone_number']:
           return self.standardize_phone_number_format(raw_data['phone_number'])
        return self.standardize_phone_number_format(raw_data['mobile_number'])

    def standardize_phone_number_format(self, raw_phone_number):
        nums = ''
        for c in raw_phone_number:
            if match('\d', c):
                nums += c
        try:
            return '-'.join(findall('(\d{3})(\d{3})(\d{4})$', nums)[0])
        except:
            None

    def get_excel_formulae(self):
        data = GoogleSheet(self.ENV_VARS_SPREADSHEET_ID, 'excel formulas')[0]
        formulae = {}
        for field in ('Pronouns', 'Status', 'Enough', 'Seats', 'Sigs'):
            formulae[field] = f'=#{data[field]}'
        return formulae
