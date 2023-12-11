import plotly.graph_objects as go
import numpy as np
from PIL import Image
import math
from dash import Dash, dcc, html
from testing import arc_coords

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

    # NYC long, lat
    coords = [
        [-73.935242, 40.730610], # NYC 
        [-0.118092, 51.509865], # London
        [139.839478, 35.652832] # Tokyo
    ]
    x, y, z = [], [], []
    radius *= 1.01
    for coord in coords:
        long = coord[0]
        lat = coord[1]
        phi   = (90-lat)*(math.pi/180)
        theta = (long+180)*(math.pi/180)
        x.append((radius) * math.sin(phi)*math.cos(theta))
        y.append((radius) * math.sin(phi)*math.sin(theta))
        z.append((radius) * math.cos(phi))

    fig.add_trace(
        go.Scatter3d(x=x, y=y, z=z, mode='markers', marker=dict(color='#FF0000', size = 3))
    )
    
    start = [x[0], y[0], z[0]]
    end = [x[1], y[1], z[1]]
    arc_x, arc_y, arc_z = arc_coords(start, end, radius=radius)

    fig.add_trace(
        go.Scatter3d(x=arc_x, y=arc_y, z=arc_z, mode='lines')
    )

    start = [x[1], y[1], z[1]]
    end = [x[2], y[2], z[2]]
    arc_x, arc_y, arc_z = arc_coords(start, end, radius=radius)

    fig.add_trace(
        go.Scatter3d(x=arc_x, y=arc_y, z=arc_z, mode='lines')
    )

    app = Dash()
    app.layout = html.Div(
        [dcc.Graph(figure=fig, style={'width': '90vh', 'height': '90vh'})],
        style={'width': '80%', 'height': '90vh'}
    )

    app.run(
        host='127.0.0.1',
        port='9495',
        debug=True
    )