def lambda_handler(event, context):
    print("Lambdaが実行されました / Lambda has been executed")
    return {
        'statusCode': 200,
        'body': 'Hello Lambda!'
    }