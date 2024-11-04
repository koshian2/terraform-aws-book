import numpy as np

def lambda_handler(event, context):
    n = event.get("n", 10)

    rand_array = np.random.randn(n, n)
    inv_array = np.linalg.inv(rand_array)
    dot_array = np.dot(inv_array, rand_array)

    return {
        'statusCode': 200,
        'body': np.sum(dot_array)
    }

