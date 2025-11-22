import json

def lambda_handler(event, context):
    return {
        "isBase64Encoded": False,
        "statusCode": 200,
        "statusDescription": "200 OK",
        # "headers": {"content-type": "application/json"}, # multi-value-headerがOFFの場合
        "multiValueHeaders": {
            "Content-Type": ["application/json; charset=utf-8"]
        },
        "body": json.dumps({"message": "Hello from Lambda via ALB"})
    }