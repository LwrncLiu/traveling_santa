import plotly.graph_objects as go
import numpy as np
from PIL import Image
import math
from dash import Dash, dcc, html
from testing import arc_coords, long_lat_to_coords, parse_point
import pandas as pd

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

if __name__ == '__main__':
    texture = np.asarray(Image.open('static/globe.jpg'.format())).T
    radius = 100
    x,y,z = sphere(radius, texture)

    surf = go.Surface(
        x=x, y=y, z=z,
        surfacecolor=texture,
        colorscale=colorscale,
        opacity = 1.0
    )    

    layout = go.Layout(scene=dict(aspectratio=dict(x=1, y=1, z=1)))
    fig = go.Figure(data=[surf], layout=layout)

    path = [
        "POINT(0 90)",
        "POINT(-87.8684039 42.8821595)",
        "POINT(-73.9869641 40.9390043)",
        "POINT(-73.7826309 41.0598463)",
        "POINT(-78.8431931 33.7269719)",
        "POINT(-88.1137198 30.7283717)",
        "POINT(-90.9264951 30.5447972)",
        "POINT(-95.5720002 29.770199)",
        "POINT(-105.0953399 40.4085544)",
        "POINT(-111.996804 33.6055745)",
        "POINT(-115.8093979 33.4883332)",
        "POINT(0 90)"
    ]


    x_scatter, y_scatter, z_scatter = [], [], []
    x_arcs, y_arcs, z_arcs = [], [], []
    prev_x, prev_y, prev_z = None, None, None
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

    # add location scatter points to globe
    fig.add_trace(
        go.Scatter3d(x=x_scatter, y=y_scatter, z=z_scatter, mode='markers', marker=dict(color='#F51720', size = 2))
    )

    fig.add_trace(
        go.Scatter3d(x=x_arcs, y=y_arcs, z=z_arcs, mode='lines', marker=dict(color='#00FFFF'))
    )

    app = Dash()
    app.layout = html.Div(
        [dcc.Graph(figure=fig, style={'width': '100vh', 'height': '100vh'})],
        style={'width': '100%', 'height': '100vh'}
    )

    app.run(
        host='127.0.0.1',
        port='9495',
        debug=True
    )