#!/usr/bin/env python

import os
import sys
import json
import googlemaps
from shapely.geometry import Point, shape

class Gmaps:
	GEOCODED_ADDRESSES_CACHE_FILE = 'geocodedCache.json'

	def __init__(self, address, election_district_file, api_key):
		self.client = googlemaps.Client(key=api_key)
		self.cached_coordinates = self.get_geocode_cache()
		self.geocoded_address = self.get_geocoded_address(address)
		self.ad, self.ed = self.get_aded(election_district_file)

	def get_geocode_cache(self):
		if not os.path.isfile(self.GEOCODED_ADDRESSES_CACHE_FILE):
			f = open(self.GEOCODED_ADDRESSES_CACHE_FILE, 'x')
			f.close()
		with open(self.GEOCODED_ADDRESSES_CACHE_FILE, 'r') as f:
			data = f.read()
			return json.loads(data) if data else {}

	def get_aded(self, election_district_file):
		with open(election_district_file, 'r') as f:
			for feature in json.load(f)['features']:
				district_borders = shape(feature['geometry'])
				if district_borders.contains(self.geocoded_address):
					aded = feature['properties']['elect_dist']
					return (self.get_ad(aded), self.get_ed(aded))

	def get_geocoded_address(self, address):
		if address in self.cached_coordinates:
			return Point(*self.cached_coordinates[address])

		coded_address = self.client.geocode(address)
		if coded_address:
			location = coded_address[0]['geometry']['location']
			# shapefile lists lng 1st, lat 2nd
			coordinates = (location['lng'], location['lat'])
		else:
			coordinates = (50,50)
		self.update_geocode_cache(address, coordinates)
		return Point(*coordinates)

	def update_geocode_cache(self, address, coordinates):
		self.cached_coordinates[address] = coordinates
		with open(self.GEOCODED_ADDRESSES_CACHE_FILE, 'w') as f:
			f.write(json.dumps(self.cached_coordinates, indent=4))
				
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
		./get_ad_ed.py '123 Anywhere Ave, Brooklyn, NY 11221' 'ElectionDistricts.geojson' myspecialapikey
	'''
	address, election_district_file, api_key = sys.argv[1:]

	maps = Gmaps(address, election_district_file, api_key)
	print(maps.ad, maps.ed)
	sys.exit()
