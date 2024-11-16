import boto3
import json
import random
import string
import time
from botocore.exceptions import ClientError

# ステートマシン名
STATE_MACHINE_NAME = 'RetryStateMachine'
# AWSプロファイル名
AWS_PROFILE = 'develop'

# boto3セッションの作成
session = boto3.Session(profile_name=AWS_PROFILE)
sfn_client = session.client('stepfunctions')

def get_state_machine_arn(state_machine_name):
    try:
        paginator = sfn_client.get_paginator('list_state_machines')
        for page in paginator.paginate():
            for sm in page['stateMachines']:
                if sm['name'] == state_machine_name:
                    return sm['stateMachineArn']
        raise ValueError(f"State machine with name '{state_machine_name}' not found.")
    except ClientError as e:
        print(f"Error retrieving state machine ARN: {e}")
        raise

def start_step_function_execution(sfn_arn, input_data):
    response = sfn_client.start_execution(
        stateMachineArn=sfn_arn,
        name=f"Execution_{input_data['ID']}_{int(time.time())}",
        input=json.dumps(input_data)
    )

def main():
    state_machine_arn = get_state_machine_arn(STATE_MACHINE_NAME)
    print(f"Retrieved ARN for state machine '{STATE_MACHINE_NAME}': {state_machine_arn}")

    for i in range(50):
        message = {
            "ID": i,
            "value": ''.join(random.choices(string.ascii_letters + string.digits, k=10))
        }
        print(f"Sending message ID {i}: {message}")
        start_step_function_execution(state_machine_arn, message)
        time.sleep(0.1)

if __name__ == "__main__":
    main()
