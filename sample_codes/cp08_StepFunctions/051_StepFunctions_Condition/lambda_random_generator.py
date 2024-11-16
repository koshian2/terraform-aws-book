import random

def lambda_handler(event, context):
    number = random.randint(0, 9)
    return {
        'statusCode': 200,
        'number': number
    }