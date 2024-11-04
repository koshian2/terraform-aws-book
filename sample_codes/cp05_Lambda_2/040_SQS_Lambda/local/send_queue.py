import boto3

def send_message_to_sqs(queue_name, n=20, profile_name="develop"):
    # SQSクライアントの作成
    session = boto3.Session(profile_name=profile_name)
    sqs_client = session.client('sqs')

    # キュー名からキューURLを取得
    response = sqs_client.get_queue_url(
        QueueName=queue_name
    )
    queue_url = response['QueueUrl']
    print(f"キューURL: {queue_url}")

    # メッセージを送信
    for i in range(n):
        if ".fifo" in queue_name:
            send_response = sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=f"こんにちは、SQS！ ID={i}",
                MessageGroupId="default"
            )
        else:
            send_response = sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=f"こんにちは、SQS！ ID={i}"
            )
        message_id = send_response.get('MessageId')
        print(f"メッセージが送信されました。Message ID: {message_id}")

if __name__ == "__main__":
    queue_name = "my-standard-queue"
    # queue_name = "my-fifo-queue.fifo"
    send_message_to_sqs(queue_name)
