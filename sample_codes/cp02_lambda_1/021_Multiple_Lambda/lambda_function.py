import os

def lambda_handler(event, context):
    env_name = os.environ.get('ENV_NAME', 'unknown') 

    return {
        'statusCode': 200,
        'body': f"Hello from {env_name} environment!"
    }
