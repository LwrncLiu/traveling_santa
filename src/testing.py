import numpy as np
import math
import re

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


if __name__ == '__main__':

    pattern = r'POINT\(([-\d.]+) ([-\d.]+)\)'
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
    for point in path:
        match = re.match(pattern, point)

        longitude = float(match.group(1))
        latitude = float(match.group(2))

        x, y, z = long_lat_to_coords(longitude, latitude, radius=100)
    
        print(x, y, z)

