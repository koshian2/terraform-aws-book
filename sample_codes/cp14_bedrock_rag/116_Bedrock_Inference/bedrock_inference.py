import boto3

session = boto3.Session(profile_name="develop")
client = session.client("bedrock-runtime")

# Claude Sonnet 4.6の日本国内向け推論プロファイルID
model_id = "jp.anthropic.claude-sonnet-4-6"

response = client.converse(
    modelId=model_id,
    messages=[
        {
            "role": "user",
            "content": [{"text": "AWSのメリットを1文で教えてください。"}],
        }
    ],
    inferenceConfig={"maxTokens": 256},
)

for block in response["output"]["message"]["content"]:
    if "text" in block:
        print(block["text"])
