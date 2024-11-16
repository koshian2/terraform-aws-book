import json

def lambda_handler(event, context):
    x = event.get('x')
    result = x**2
    return {
        'statusCode': 200,
        'result': result
    }
