def lambda_handler(event, context):
    print("Lambdaが実行されました")
    return {
        'statusCode': 200,
        'body': 'Hello Lambda!'
    }