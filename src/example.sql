alter session set geography_output_format = 'WKT';

create table test_points (coords GEOGRAPHY);

insert into test_points values('POINT(0 90)');
insert into test_points (
    select concat('POINT(', LON::varchar, ' ', LAT::varchar, ')')
    from test_data 
    limit 10
);


-- create stage for stored procedure to live in 
create stage SPROC_STAGE;

-- create UDF to compare if two geography points are similar
create or replace function points_equal(point1 GEOGRAPHY, point2 GEOGRAPHY)
    returns boolean
    as 
    $$
    select st_distance(point1, point2) = 0
    $$
;

-- create proc to find a path by using nearest neighbors
create or replace procedure naive_path_finder(source_table STRING)
    returns string 
    language python 
    runtime_version = '3.10'
    packages = ('snowflake-snowpark-python')
    handler = 'main'
as 
$$
import snowflake.snowpark.functions as F

def main(session, source_table):
    METHOD = 'NAIVE'
    START_COL = 'START'
    END_COL = 'END'
    DISTANCE_COL = 'DISTANCE_KM'
    COORDS_COL = 'COORDS'
    WKT_FMT_COL = 'WKT'
    coordinates = session.table(source_table)
    num_coords = coordinates.count()
    a = coordinates.rename(F.col(COORDS_COL), START_COL)
    b = coordinates.rename(F.col(COORDS_COL), END_COL)
    joined = a.join(b, F.call_builtin('POINTS_EQUAL', F.col(START_COL), F.col(END_COL)) != True)
    available_routes = joined \
        .with_column(DISTANCE_COL, F.call_builtin('ST_DISTANCE', F.col(START_COL), F.col(END_COL))/1000) \
        .withColumn(WKT_FMT_COL, F.call_builtin('ST_ASWKT', F.col(END_COL)))
    
    path = []
    total_distance = 0
    curr_point = f'POINT({0} {90})'
    path.append(curr_point)
    for _ in range(num_coords):
        next_destination = available_routes.filter(F.call_builtin('POINTS_EQUAL', F.col(START_COL), F.call_builtin('TO_GEOGRAPHY', curr_point))) \
            .orderBy(F.col(DISTANCE_COL)).limit(1) \
            .collect()
        
        next_point = next_destination[0][WKT_FMT_COL]
        path.append(next_point)
        total_distance += next_destination[0][DISTANCE_COL]
        curr_point = next_point
        
        available_routes = available_routes.filter(F.call_builtin('POINTS_EQUAL', F.col(END_COL), F.call_builtin('TO_GEOGRAPHY', curr_point)) == False)
    nearest_neighbor_path = session.create_dataframe([[path, total_distance, 'naive']], schema=["PATH", "DISTANCE", "METHOD"])
    nearest_neighbor_path.write.mode("append").save_as_table("route")
    return 'SUCCESS'
$$
;

call naive_path_finder('test_points');
select * from route;
select * from test_points;