import numpy as np
from PIL import Image
import plotly.graph_objects as go
import re
import math
import streamlit as st

@st.cache_data
def get_naive_globe(naive_path):
    globe = globe_fig()
    node, path = node_paths(naive_path)
    globe.add_traces([node, path])
    globe.update_layout(
        height=600,
        scene=dict(
            xaxis=dict(title='', showticklabels=False, showgrid=False),
            yaxis=dict(title='', showticklabels=False, showgrid=False),
            zaxis=dict(title='',  showticklabels=False, showgrid=False),
            camera = dict(
                eye=dict(x=0.85, y=0.85, z=0.85)
            )
        )
        
    )
    return globe

@st.cache_data
def get_genetics_globe(genetics_path):
    globe = globe_fig()
    node, path = node_paths(genetics_path)
    globe.add_traces([node, path])
    globe.update_layout(
        height=600,
        scene=dict(
            xaxis=dict(title='', showticklabels=False, showgrid=False),
            yaxis=dict(title='', showticklabels=False, showgrid=False),
            zaxis=dict(title='',  showticklabels=False, showgrid=False),
            camera = dict(
                eye=dict(x=0.85, y=0.85, z=0.85)
            )
        )
    )
    return globe

def sphere(size, texture): 
    N_lat = int(texture.shape[0])
    N_lon = int(texture.shape[1])
    theta = np.linspace(0,2*np.pi,N_lat)
    phi = np.linspace(0,np.pi,N_lon)
    
    # Set up coordinates for points on the sphere
    x0 = size * np.outer(np.cos(theta),np.sin(phi))
    y0 = size * np.outer(np.sin(theta),np.sin(phi))
    z0 = size * np.outer(np.ones(N_lat),np.cos(phi))
    
    # Set up trace
    return x0,y0,z0

def globe_fig():
    colorscale =[
        [0.0, 'rgb(30, 59, 117)'],
        [0.1, 'rgb(46, 68, 21)'],
        [0.2, 'rgb(74, 96, 28)'],
        [0.3, 'rgb(115,141,90)'],
        [0.4, 'rgb(122, 126, 75)'],
        [0.6, 'rgb(122, 126, 75)'],
        [0.7, 'rgb(141,115,96)'],
        [0.8, 'rgb(223, 197, 170)'],
        [0.9, 'rgb(237,214,183)'],
        [1.0, 'rgb(255, 255, 255)']
    ]  
    texture = np.asarray(Image.open('static/globe.jpg'.format())).T
    radius = 100
    x,y,z = sphere(radius, texture)
    
    surf = go.Surface(
        x=x, y=y, z=z,
        surfacecolor=texture,
        colorscale=colorscale,
        opacity = 1.0,
        showscale = False
    )    

    layout = go.Layout(scene=dict(aspectratio=dict(x=1, y=1, z=1)))
    fig = go.Figure(data=[surf], layout=layout)

    return fig

def arc_coords(point1, point2, radius, num_coords = 50):
    # Normalize the input points to lie on the sphere's surface
    point1 = point1 / np.linalg.norm(point1)
    point2 = point2 / np.linalg.norm(point2)

    # Calculate the great circle distance (angle) between the two points
    dot_product = np.dot(point1, point2)
    angle = np.arccos(np.clip(dot_product, -1.0, 1.0))
    
    # Parametric equations for the great circle
    t = np.linspace(0, 1, num_coords)
    circle_points = (np.sin((1 - t) * angle)[:, np.newaxis] * point1 + np.sin(t * angle)[:, np.newaxis] * point2) / np.sin(angle)

    # Convert great circle points to Cartesian coordinates
    x_line = radius * np.sin(np.arccos(circle_points[:, 2])) * np.cos(np.arctan2(circle_points[:, 1], circle_points[:, 0]))
    y_line = radius * np.sin(np.arccos(circle_points[:, 2])) * np.sin(np.arctan2(circle_points[:, 1], circle_points[:, 0]))
    z_line = radius * np.cos(np.arccos(circle_points[:, 2]))

    return x_line.tolist(), y_line.tolist(), z_line.tolist()

def long_lat_to_coords(long, lat, radius):
    phi = (90-lat)*(math.pi/180)
    theta = (long+180)*(math.pi/180)
    x = (radius) * math.sin(phi)*math.cos(theta)
    y = (radius) * math.sin(phi)*math.sin(theta)
    z = (radius) * math.cos(phi)

    return x, y, z

def parse_point(point):
    pattern = r'POINT\(([-\d.]+) ([-\d.]+)\)'
    match = re.match(pattern, point)

    long, lat = float(match.group(1)), float(match.group(2))

    return long, lat

def node_paths(path):
    x_scatter, y_scatter, z_scatter = [], [], []
    x_arcs, y_arcs, z_arcs = [], [], []
    prev_x, prev_y, prev_z = None, None, None
    radius = 100
    radius *= 1.005
    for i in range(len(path)):
        long, lat = parse_point(path[i])

        curr_x, curr_y, curr_z = long_lat_to_coords(long, lat, radius)
        x_scatter.append(curr_x)
        y_scatter.append(curr_y)
        z_scatter.append(curr_z)
        if prev_x is not None:
            arc_x, arc_y, arc_z = arc_coords([prev_x, prev_y, prev_z], [curr_x, curr_y, curr_z], radius)
            x_arcs += arc_x
            y_arcs += arc_y
            z_arcs += arc_z
            
        prev_x, prev_y, prev_z = curr_x, curr_y, curr_z

    node_scatter = go.Scatter3d(x=x_scatter, y=y_scatter, z=z_scatter, mode='markers', marker=dict(color='#F51720', size=3), name='Nodes')
    node_path = go.Scatter3d(x=x_arcs, y=y_arcs, z=z_arcs, mode='lines', marker=dict(color='#00FFFF', size=2), name='Paths')

    return node_scatter, node_path


