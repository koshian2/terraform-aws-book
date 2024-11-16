import json

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'message': 'YOU LOSE\n俺の勝ち！　何で負けたか、明日まで考えといてください。'
    }