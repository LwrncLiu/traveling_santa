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
    '''
    Takes a given source table that contains a set of coordinates, then starting from
    the north pole, traverse to the next nearest coordinate and repeat until all coordinates 
    have been traversed, finally ending up at the north pole. Output path is returned in the
    table f'{source_table}_route'.
    '''
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
    all_routes = joined \
        .with_column(DISTANCE_COL, F.call_builtin('ST_DISTANCE', F.col(START_COL), F.col(END_COL))/1000) \
        .withColumn(WKT_FMT_COL, F.call_builtin('ST_ASWKT', F.col(END_COL)))
    
    available_routes = all_routes
    path = []
    total_distance = 0
    north_pole = f'POINT({0} {90})'
    curr_point = north_pole
    path.append(curr_point)
    for i in range(num_coords):
        if i == num_coords - 1:
            next_destination = all_routes.filter(F.call_builtin('POINTS_EQUAL', F.col(START_COL), F.call_builtin('TO_GEOGRAPHY', curr_point))) \
                .filter(F.call_builtin('POINTS_EQUAL', F.col(END_COL), F.call_builtin('TO_GEOGRAPHY', north_pole))) \
                .orderBy(F.col(DISTANCE_COL)).limit(1) \
                .collect()
        else:
            next_destination = available_routes.filter(F.call_builtin('POINTS_EQUAL', F.col(START_COL), F.call_builtin('TO_GEOGRAPHY', curr_point))) \
                .orderBy(F.col(DISTANCE_COL)).limit(1) \
                .collect()
        next_point = next_destination[0][WKT_FMT_COL]
        path.append(next_point)
        total_distance += next_destination[0][DISTANCE_COL]
        
        available_routes = available_routes.filter(F.call_builtin('POINTS_EQUAL', F.col(END_COL), F.call_builtin('TO_GEOGRAPHY', curr_point)) == False)
        curr_point = next_point
    nearest_neighbor_path = session.create_dataframe([[path, total_distance, 'naive']], schema=["PATH", "DISTANCE", "METHOD"])
    
    # check if table already exists
    output_table_name = f'{source_table}_route'
    exists = session.sql(f"select routes.tbl_exist('{output_table_name}')").to_pandas()
    if exists.loc[0].iloc[0]:
        existing_table = session.table(output_table_name)
        removed_naive = existing_table.filter(F.col("METHOD") != 'naive')
        removed_naive.write.mode("overwrite").save_as_table(f'routes.{output_table_name}')

    nearest_neighbor_path.write.mode("append").save_as_table(f'routes.{output_table_name}')
    return 'SUCCESS'
$$
;
