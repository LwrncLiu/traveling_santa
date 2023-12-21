create or replace procedure genetic_path_finder(source_table STRING, population_size INT, generations INT, mutation_rate FLOAT)
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

    def mutate(self, distances):
        swap_indicies = random.sample(range(1, len(self.path) - 2), 2)
        idx_a, idx_b = swap_indicies[0], swap_indicies[1]
        if self.fitness is None:
            self.calculate_path_fitness(distances)
        if distances[self.path[idx_a]][self.path[idx_b]] < self.fitness / len(self.path):
            self.path[idx_a], self.path[idx_b] = self.path[idx_b], self.path[idx_a]

    def calculate_path_fitness(self, distances):
        prev_node = None
        fitness = 0
        for curr_node in self.path:
            if prev_node is not None:
                fitness += distances[prev_node][curr_node]
            prev_node = curr_node
        self.fitness = fitness

    def calculate_path_subset_fitness(self, distances, start_idx, end_idx):
        prev_node = None
        fitness = 0
        for i in range(start_idx, end_idx):
            curr_node = self.path[i]
            if prev_node is not None:
                fitness += distances[prev_node][curr_node]
            prev_node = curr_node
        return fitness

class GeneticAlgorithm:
    def __init__(self, locations, lookup_table, population_size, generations, mutation_rate, start_end):
        self.lookup_table = lookup_table
        self.locations = locations
        self.mutation_rate = mutation_rate
        self.generations = generations
        self.population_size = population_size
        self.north_pole = start_end

        self.METHOD = 'GENETIC'
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
                if random.random() < self.mutation_rate:
                    path.mutate(self.lookup_table)
                path.calculate_path_fitness(self.lookup_table)
                if path.fitness < self.best_path.fitness:
                    self.best_path = Path(path.path)
                    self.best_path.fitness = path.fitness

            self.population = new_population

    def execute(self):
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
    distances_dict = joined \
        .with_column(DISTANCE_COL, F.call_builtin('ST_DISTANCE', F.col(START_COL), F.col(END_COL))/1000) \
        .with_column(START_COL, F.call_builtin('ST_ASWKT', F.col(START_COL))) \
        .with_column(END_COL, F.call_builtin('ST_ASWKT', F.col(END_COL))) \
        .to_pandas() \
        .groupby([START_COL, END_COL])[DISTANCE_COL].agg('first').to_dict()

    nested_lookup = {}
    for (start, end), distance in distances_dict.items():
        if start not in nested_lookup:
            nested_lookup[start] = {}
        nested_lookup[start][end] = distance
    
    nodes = coordinates.filter(F.call_builtin('POINTS_EQUAL', F.col(COORDS_COL), F.call_builtin('TO_GEOGRAPHY', north_pole)) == False) \
        .with_column(COORDS_COL, F.call_builtin('ST_ASWKT', F.col(COORDS_COL))) \
        .to_pandas()

    algorithm = GeneticsAlgorithm(nodes, nested_lookup, population_size, generations, mutation_rate, north_pole)
    algorithm.execute()
    best_path = algorithm.best_path
    genetics_best_path = session.create_dataframe([[best_path.path, float(best_path.fitness), 'genetics']], schema=["PATH", "DISTANCE", "METHOD"])
    
    # check if table already exists
    output_table_name = f'{source_table}_route'
    exists = session.sql(f"select routes.tbl_exist('{output_table_name}')").to_pandas()
    if exists.loc[0].iloc[0]:
        existing_table = session.table(output_table_name)
        removed_genetics = existing_table.filter(F.col("METHOD") != 'genetics')
        removed_genetics.write.mode("overwrite").save_as_table(f'routes.{output_table_name}')
    
    genetics_best_path.write.mode("append").save_as_table(f'routes.{output_table_name}')
    return 'SUCCESS'
$$
;