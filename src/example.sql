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
    north_pole = f'POINT({0} {90})'
    curr_point = north_pole
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


create or replace procedure genetics_path_finder(source_table STRING, population_size INT, generations INT, mutation_rate FLOAT)
    returns string 
    language python 
    runtime_version = '3.10'
    packages = ('snowflake-snowpark-python')
    handler = 'main'
as 
$$
import snowflake.snowpark.functions as F
import random

class Path:
    def __init__(self, path):
        self.path = path
        self.fitness = None
        self.fitness_normalized = None

    def mutate(self, mutation_rate):
        # TODO: make mutation depend on distance. If far (or near?) distance then do not mutate
        for _ in range(len(self.path) - 2):
            if random.random() < mutation_rate:
                swap_indicies = random.sample(range(1, len(self.path) - 2), 2)
                idx_a, idx_b = swap_indicies[0], swap_indicies[1]
                self.path[idx_a], self.path[idx_b] = self.path[idx_b], self.path[idx_a]

    def calculate_path_fitness(self, distances):
        prev_node = None
        fitness = 0
        for curr_node in self.path:
            if prev_node is not None:
                fitness += distances[(distances['START'] == prev_node) & (distances['END'] == curr_node)]['DISTANCE_KM'].iloc[0]
            prev_node = curr_node
        self.fitness = fitness

    def calculate_path_subset_fitness(self, distances, start_idx, end_idx):
        prev_node = None
        fitness = 0
        for i in range(start_idx, end_idx):
            curr_node = self.path[i]
            if prev_node is not None:
                fitness += distances[(distances['START'] == prev_node) & (distances['END'] == curr_node)]['DISTANCE_KM'].iloc[0]
            prev_node = curr_node
        return fitness

class GeneticsAlgorithm:
    def __init__(self, locations, lookup_table, population_size, generations, mutation_rate, start_end):
        self.lookup_table = lookup_table
        self.locations = locations
        self.mutation_rate = mutation_rate
        self.generations = generations
        self.population_size = population_size
        self.north_pole = start_end

        self.METHOD = 'GENETICS'
        self.START_COL = 'START'
        self.END_COL = 'END'
        self.COORDS_COL = 'COORDS'
        self.WKT_FMT_COL = 'WKT'

        self.population = []
        self.best_path = None
    
    def generate_random_path(self, root_path):
        '''
        Given a list of nodes (that does not contain the north pole), generate
        a random list of nodes and append the north pole to the start and end of the 
        generated path 
        '''
        random_path = random.sample(root_path, len(root_path))
        random_path.insert(0, self.north_pole)
        random_path.append(self.north_pole)
        
        return random_path
    
    def generate_population(self, root_path):
        for _ in range(self.population_size):
            rand_path = Path(self.generate_random_path(root_path))
            self.population.append(rand_path)
    
    def calculate_population_fitness(self):
        for path in self.population:
            path.calculate_path_fitness(self.lookup_table)
            if self.best_path is None or path.fitness < self.best_path.fitness:
                self.best_path = Path(path.path)
                self.best_path.fitness = path.fitness
    
    def normalize_fitness(self):
        total_fitness = sum([1 / path.fitness for path in self.population])
        for path in self.population:
            path.fitness_normalized = (1 / path.fitness) / total_fitness

    def select_from_population(self):
        probabilities = [path.fitness_normalized for path in self.population]
        new_population = random.choices(self.population, probabilities, k = len(self.population))
        return new_population
    
    def crossover(self, population):
        new_population = []
        for _ in range(self.population_size):
            path_a = random.choice(population)
            path_b = random.choice([path for path in population if path != path_a])
            path_len = len(path_a.path)

            start_idx = random.choice(range(1, path_len - 2))
            end_idx = random.choice(range(start_idx + 1, path_len - 1))

            path_a_subset_fitness = path_a.calculate_path_subset_fitness(self.lookup_table, start_idx, end_idx)
            path_b_subset_fitness = path_b.calculate_path_subset_fitness(self.lookup_table, start_idx, end_idx)

            new_path = [0] * path_len
            new_path[0], new_path[-1] = path_a.path[0], path_a.path[0]

            if path_a_subset_fitness < path_b_subset_fitness:
                seed_path = path_a.path
                filler_path = path_b.path
            else:
                seed_path = path_b.path
                filler_path = path_a.path
                
            new_path[start_idx:end_idx] = seed_path[start_idx:end_idx]
            for i in [i for i in range(1, path_len - 1) if i not in range(start_idx, end_idx)]:
                new_path[i] = next(node for node in filler_path if node not in new_path)

            new_population.append(Path(new_path))

        return new_population    
            
    def simulate_generations(self):
        for i in range(self.generations):
            self.normalize_fitness()
            selected_population = self.select_from_population()
            new_population = self.crossover(selected_population)
            for path in new_population:
                path.mutate(self.mutation_rate)
                path.calculate_path_fitness(self.lookup_table)
                if path.fitness < self.best_path.fitness:
                    self.best_path = Path(path.path)
                    self.best_path.fitness = path.fitness

            self.population = new_population

    def execute(self):
        print(self.locations)
        root_path = self.locations[self.COORDS_COL].tolist()
        
        self.generate_population(root_path)
        self.calculate_population_fitness()
        self.simulate_generations()

def main(session, source_table, population_size, generations, mutation_rate):
    START_COL = 'START'
    END_COL = 'END'
    COORDS_COL = 'COORDS'
    DISTANCE_COL = 'DISTANCE_KM'
    north_pole = f'POINT({0} {90})'
    
    coordinates = session.table(source_table)

    a = coordinates.rename(F.col(COORDS_COL), START_COL)
    b = coordinates.rename(F.col(COORDS_COL), END_COL)
    
    joined = a.join(b, F.call_builtin('POINTS_EQUAL', F.col(START_COL), F.col(END_COL)) != True)
    distances = joined \
        .with_column(DISTANCE_COL, F.call_builtin('ST_DISTANCE', F.col(START_COL), F.col(END_COL))/1000) \
        .with_column(START_COL, F.call_builtin('ST_ASWKT', F.col(START_COL))) \
        .with_column(END_COL, F.call_builtin('ST_ASWKT', F.col(END_COL))) \
        .to_pandas()
    nodes = coordinates.filter(F.call_builtin('POINTS_EQUAL', F.col(COORDS_COL), F.call_builtin('TO_GEOGRAPHY', north_pole)) == False) \
        .with_column(COORDS_COL, F.call_builtin('ST_ASWKT', F.col(COORDS_COL))) \
        .to_pandas()

    algorithm = GeneticsAlgorithm(nodes, distances, population_size, generations, mutation_rate, north_pole)
    algorithm.execute()
    best_path = algorithm.best_path
    genetics_best_path = session.create_dataframe([[best_path.path, float(best_path.fitness), 'genetics']], schema=["PATH", "DISTANCE", "METHOD"])
    genetics_best_path.write.mode("append").save_as_table("route")
    return 'SUCCESS'
$$
;
call naive_path_finder('test_points');
call genetics_path_finder('test_points', 100, 5, 0.05);
select * from route;
select * from test_points;