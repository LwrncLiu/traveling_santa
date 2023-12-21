create or replace procedure routes.get_n_random_locs(num_locs INT, table_name STRING)
    returns string 
    language python 
    runtime_version = '3.10'
    packages = ('snowflake-snowpark-python')
    handler = 'main'
as 
$$
import snowflake.snowpark.functions as F

def main(session, num_locs, table_name):
    all_addresses = session.table('worldwide_address_data.address.openaddress')
    num_addresses = all_addresses.filter((F.col('LON') != 0) & (F.col('LAT') != 0)) \
                        .sample(n=num_locs) \
                        .distinct() \
                        .to_pandas()

    longitudes = num_addresses['LON'].to_numpy()
    latitudes = num_addresses['LAT'].to_numpy()
    points = [f'POINT({lon} {lat})' for lon, lat in zip(longitudes, latitudes)]
    points.append('POINT(0 90)')
    points_df = session.create_dataframe(points, schema=['COORDS'])
    coords_df = points_df.with_column('COORDS', F.call_builtin('TRY_TO_GEOGRAPHY', F.col('COORDS'))).dropna(how='all')
    
    coords_df.write.mode("overwrite").save_as_table(f'routes.{table_name}')
    return 'SUCCESS'
$$;

create or replace function routes.points_equal(point1 geography, point2 geography)
    returns boolean
    language sql
    as 
    $$
    select st_distance(point1, point2) = 0
    $$
;

create or replace function routes.tbl_exist(tbl varchar)
    returns boolean
    language sql
    as
    $$
    select  to_boolean(count(1)) 
    from    information_schema.tables 
    where   table_schema = 'ROUTES' 
    and     table_name = UPPER(tbl)
    $$
;