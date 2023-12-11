import numpy as np

def arc_coords(point1, point2, radius, num_points=100, color='blue'):

    # Normalize the input points to lie on the sphere's surface
    point1 = point1 / np.linalg.norm(point1)
    point2 = point2 / np.linalg.norm(point2)

    # # Clip values to ensure they are within the valid range
    # point1 = np.clip(point1, -1, 1)
    # point2 = np.clip(point2, -1, 1)

    # Calculate the great circle distance (angle) between the two points
    dot_product = np.dot(point1, point2)
    angle = np.arccos(np.clip(dot_product, -1.0, 1.0))
    
    # Parametric equations for the great circle
    t = np.linspace(0, 1, 100)
    great_circle_points = (np.sin((1 - t) * angle)[:, np.newaxis] * point1 + np.sin(t * angle)[:, np.newaxis] * point2) / np.sin(angle)

    
    # Convert great circle points to Cartesian coordinates
    x_line = radius * np.sin(np.arccos(great_circle_points[:, 2])) * np.cos(np.arctan2(great_circle_points[:, 1], great_circle_points[:, 0]))
    y_line = radius * np.sin(np.arccos(great_circle_points[:, 2])) * np.sin(np.arctan2(great_circle_points[:, 1], great_circle_points[:, 0]))
    z_line = radius * np.cos(np.arccos(great_circle_points[:, 2]))

    return x_line, y_line, z_line


# if __name__ == '__main__':
#     point1 = np.array([-21.179422778121925, 73.54759054792044, 65.90283738490334])
#     point2 = np.array([-62.86023441140933, 0.12956104929307521, 79.05424810645647])
#     arc_coords(point1, point2, 100 * 1.01)