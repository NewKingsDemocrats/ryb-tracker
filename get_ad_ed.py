#!/usr/bin/env python

import sys
import json
import googlemaps
from shapely.geometry import Point, shape

class Gmaps:
	def __init__(self, address, election_district_file, api_key):
		self.client = googlemaps.Client(key=api_key)
		self.geocoded_address = self.get_geocoded_address(address)
		self.ad, self.ed = self.get_aded(election_district_file)

	def get_aded(self, election_district_file):
		with open(election_district_file) as f:
			for feature in json.load(f)['features']:
				district_borders = shape(feature['geometry'])
				if district_borders.contains(self.geocoded_address):
					aded = feature['properties']['elect_dist']
					return (self.get_ad(aded), self.get_ed(aded))

	def get_geocoded_address(self, address):
		coded_address = self.client.geocode(address)
		if coded_address:
			location = coded_address[0]['geometry']['location']
			# shapefile lists lng 1st, lat 2nd
			coordinates = (location['lng'], location['lat'])
		else:
			coordinates = (50,50)
		return Point(*coordinates)
				
	def get_ad(self, aded):
		if str(aded).isdigit() and len(str(aded)) == 5:
			return str(aded)[:2]
		return ''
			
	def get_ed(self, aded):
		if str(aded).isdigit() and len(str(aded)) == 5:
			return str(aded)[2:]
		return ''


if __name__ == '__main__':
	'''
	pass in arguments separated by spaces after calling the executable, e.g.,
		./get_ad_ed.py '123 Anywhere Ave, Brooklyn, NY 11221' 'Election Districts.geojson' myspecialapikey
	'''

	address, election_district_file, api_key = sys.argv[1:]

	maps = Gmaps(address, election_district_file, api_key)
	print(maps.ad, maps.ed)
	sys.exit()
