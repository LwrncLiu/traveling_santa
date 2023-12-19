import streamlit as st 
import ast
from utils import get_naive_globe, get_genetics_globe

st.set_page_config(layout='wide')

conn = st.connection("snowflake")
df = conn.query("select * from routes.route")

col1, col2 = st.columns(2)

table_name = None
get_loc_output = None
data_ready = False

naive_solution = None 
genetics_solution = None

with st.sidebar:
    num_locs = st.slider('Number of locations', 2, 50, 10)

    st.write('For genetics algorithm: ')
    population_size = st.slider('Population size', num_locs, 300, 50)
    generations = st.slider('Generations', 1, 100, 20)
    mutation_rate = st.slider('Mutation Rate', 0.0, 1.0, 0.05)

    if 'table' not in st.session_state:
        st.session_state['table'] = table_name

    if st.button('Get locations and generate flight path!'):
        try:
            if num_locs is not None:
                table_name = f"random_{num_locs}_locs"
                conn.query(f"call routes.get_n_random_locs({num_locs}, '{table_name}');")
                conn.query(f"call routes.naive_path_finder('{table_name}')")
                conn.query(f"call routes.genetics_path_finder('{table_name}', {population_size}, {generations}, {mutation_rate})")
                data_ready = True 
        finally:
            st.session_state.table = table_name

if 'clicked' not in st.session_state:
    st.session_state.clicked = False

def click_button():
    st.session_state.clicked = True 

if data_ready:
    st.button("Visualize Paths!", on_click=click_button)

if st.session_state.clicked:
    table_name = st.session_state.table
    df = conn.query(f"select * from routes.{table_name}_route")

    naive_solution = df[df['METHOD'] == 'naive']
    naive_path = ast.literal_eval(naive_solution['PATH'].iloc[0])
    naive_path_distance = naive_solution['DISTANCE'].iloc[0]

    genetics_solution = df[df['METHOD'] == 'genetics']
    genetics_path = ast.literal_eval(genetics_solution['PATH'].iloc[0])
    genetics_path_distance = genetics_solution['DISTANCE'].iloc[0]

    naive_fig = get_naive_globe(naive_path)
    globe_fig = get_genetics_globe(genetics_path)
    
    
    with col1:
        st.header('Naive (Nearest Neighbor) Solution') 
        st.write(f'Total path distance (km): {int(naive_path_distance)}')
        st.plotly_chart(naive_fig, use_container_width=True)

    with col2:
        st.header('Genetics Solution')
        st.write(f'Total travel distance (km): {int(genetics_path_distance)}')
        st.plotly_chart(globe_fig, use_container_width=True)