import pandas as pd
import geopandas as gpd
import googlemaps
from shapely.geometry import Point

home = "d:/dropbox/politics/datateam/"

#my google API key
gmaps = googlemaps.Client(key='AIzaSyCzMvGLMd73xvbq6M7Hi8ItiOBVe6ABGQU')

address_file = home + "ryb2024/test_addresses.csv"
election_district_file = home + "mapping/election districts.geojson"

#the address file is just a list of addresses in the format "123 Fake St, Apt 12, Brooklyn, NY 11206" 
addresses_df = pd.read_csv(address_file)
election_districts_gdf = gpd.read_file(election_district_file)


#use google maps API to get the lat/long geocoding of the addresses, return in a list of format [longitude, latitute] to match the format used by NYC Open Data
#if google maps doesn't return a correct answer, it gives a geocoding somewhere in the eurasian steppe which then will not match to a Brooklyn ED and will give a null result later
def geocode_address(address):
	coded_address = gmaps.geocode(address)
	print(coded_address)
	if coded_address:
		lat = coded_address[0]['geometry']['location']['lat']
		lng = coded_address[0]['geometry']['location']['lng']
		return [lng,lat]
	else:
		return [50,50]

#this cuts the AD and ED from the "elect_dist" field in the Open Data file, but returns blanks if it isn't in the proper format
def get_ad(aded):
	if str(aded).isdigit() and len(str(aded)) == 5:
		return str(aded)[:2]
	else:
		return ''
		
def get_ed(aded):
	if str(aded).isdigit() and len(str(aded)) == 5:
		return str(aded)[2:]
	else:
		return ''



#apply the geocoding to each address in the address file
addresses_df['coordinates'] = addresses_df['Primary Address'].apply(geocode_address)

#turn the addresses dataframe into a geopandas dataframe based on the coordinates
addresses_gdf = gpd.GeoDataFrame(addresses_df, geometry=addresses_df['coordinates'].apply(Point),crs='EPSG:4326')

#join the coded addresses with the election districts. In theory there should never be a location that is within two election districts. I guess we'll find out? But so long as there isn't anything like that, just doing a simple left join should do it. 
addresses_with_aded_gdf = gpd.sjoin(addresses_gdf, election_districts_gdf,predicate='within',how='left')

#the "elect_dist" column in the Election Districts file is listed in '#####' format where the first two digits are the assembly district and the final three digits are the election district in 001 format. Break these out into two new columns AD and ED.

addresses_with_aded_gdf['AD'] = addresses_with_aded_gdf['elect_dist'].apply(get_ad)
addresses_with_aded_gdf['ED'] = addresses_with_aded_gdf['elect_dist'].apply(get_ed)

outputfile = home + "ryb2024/test_addresses_mapped.csv"

addresses_with_aded_gdf.to_csv(outputfile)