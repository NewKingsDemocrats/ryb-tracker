#!/usr/bin/env python

import sys
import json
import googlemaps
import sqlite3
from shapely.geometry import Point, shape

class Gmaps:
	DATABASE_FILE = 'geocodedCache.db'

	def __init__(self, address, election_district_file, api_key):
		self.setup_db()
		self.client = googlemaps.Client(key=api_key)
		self.geocoded_address = self.get_geocoded_address(address)
		self.ad, self.ed = self.get_aded(election_district_file)

	def setup_db(self):
		self.db_connection = sqlite3.connect(self.DATABASE_FILE)
		self.db_cursor = self.db_connection.cursor()
		self.find_or_create_table()

	def find_or_create_table(self):
		self.db_cursor.execute("""
			SELECT name FROM sqlite_master
			WHERE type='table' AND name='cached_addresses'
		""").fetchone() or self.db_cursor.execute("""
			CREATE TABLE cached_addresses(address, longitude, latitude)
		""")

	def get_aded(self, election_district_file):
		with open(election_district_file, 'r') as f:
			for feature in json.load(f)['features']:
				district_borders = shape(feature['geometry'])
				if district_borders.contains(self.geocoded_address):
					aded = feature['properties']['elect_dist']
					return (self.get_ad(aded), self.get_ed(aded))

	def get_geocoded_address(self, address):
		cached_coordinates = self.get_cached_coordinates(address)
		if cached_coordinates:
			return Point(*cached_coordinates)

		coded_address = self.client.geocode(address)
		if coded_address:
			location = coded_address[0]['geometry']['location']
			# shapefile lists lng 1st, lat 2nd
			coordinates = (location['lng'], location['lat'])
		else:
			coordinates = (50,50)
		self.update_geocode_cache(address, coordinates)
		return Point(*coordinates)

	def get_cached_coordinates(self, address):
		return self.db_cursor.execute(f"""
			SELECT longitude, latitude FROM cached_addresses
			WHERE address='{address}'
		""").fetchone()

	def update_geocode_cache(self, address, coordinates):
		self.db_cursor.execute(f"""
			INSERT INTO cached_addresses VALUES
			('{address}', {coordinates[0]}, {coordinates[1]})
		""")
		self.db_connection.commit()

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
