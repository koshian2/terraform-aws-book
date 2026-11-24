import os

import boto3

# Terraformで作成したAIPのARNを環境変数から取得する。
AIP_ARN = os.environ["AIP_ARN"]
SYSTEM_DEFINED_ID = os.environ["SYSTEM_DEFINED_ID"]

client = boto3.client("bedrock-runtime", region_name="ap-northeast-1")


def lambda_handler(event, context):
    route = event.get("route", "aip")
    prompt = event.get("prompt", "AWSのメリットを1文で教えてください。")

    # 本文と同様に、同じ実行ロールで呼び出し経路だけを切り替える。
    model_id = AIP_ARN if route == "aip" else SYSTEM_DEFINED_ID

    response = client.converse(
        modelId=model_id,
        messages=[
            {
                "role": "user",
                "content": [{"text": prompt}],
            }
        ],
        inferenceConfig={"maxTokens": 256},
    )

    output_text = response["output"]["message"]["content"][0]["text"]
    return {"statusCode": 200, "body": output_text}
