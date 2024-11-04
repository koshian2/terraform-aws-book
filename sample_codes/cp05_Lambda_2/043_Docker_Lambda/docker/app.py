import json
import boto3
from urllib.parse import unquote_plus
import os
import cv2
import numpy as np

def apply_oil_painting(image_bytes):
    """
    OpenCVを使用して画像にOil Paintingフィルタを適用します。
    """
    # 画像をバイトデータからNumPy配列に変換
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    if img is None:
        raise ValueError("画像のデコードに失敗しました。")
    
    # Oil Paintingフィルタを適用
    oil_painting = cv2.xphoto.oilPainting(img, size=7, dynRatio=1)
    
    # 処理後の画像をエンコード
    _, buffer = cv2.imencode('.jpg', oil_painting)
    return buffer.tobytes()

def lambda_handler(event, context):
    s3_client = boto3.client('s3')
    
    # イベントからバケット名とオブジェクトキーを抽出
    for record in event['Records']:
        source_bucket = record['s3']['bucket']['name']
        source_key = unquote_plus(record['s3']['object']['key'])
        
        try:
            # S3からオブジェクトを取得
            response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
            image_bytes = response['Body'].read()
            
            # Oil Paintingフィルタを適用
            processed_image = apply_oil_painting(image_bytes)
            
            # 出力バケットにアップロード
            output_bucket = os.environ['OUTPUT_BUCKET']
            output_key = f"processed_{source_key}"  # 例として "processed_" プレフィックスを追加
            
            s3_client.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=processed_image,
                ContentType='image/jpeg'
            )
            
            print(f"Successfully processed {source_key} and uploaded to {output_bucket}/{output_key}")
            
        except Exception as e:
            print(f"Error processing object {source_key} from bucket {source_bucket}. Error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': str(e)})
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Processing completed successfully.'})
    }
