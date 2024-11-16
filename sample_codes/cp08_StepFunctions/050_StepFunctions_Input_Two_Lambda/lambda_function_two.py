import json

def lambda_handler(event, context):
    x = event.get('x')
    squared = event.get('squared')
    result = x + squared
    return {
        'statusCode': 200,
        'result': result
    }
