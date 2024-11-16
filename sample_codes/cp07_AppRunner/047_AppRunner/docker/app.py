# app.py

import gradio as gr
import torch
from torchvision import models, transforms
from PIL import Image
import requests
import json
import os

# 事前学習済みのResNet-50モデルをロード
model = models.resnet50(pretrained=True)
model.eval()

# クラスラベルのロード（ImageNet）
LABELS_URL = "https://raw.githubusercontent.com/anishathalye/imagenet-simple-labels/master/imagenet-simple-labels.json"
labels = json.loads(requests.get(LABELS_URL).text)

# 画像の前処理
def preprocess(image):
    preprocess_transform = transforms.Compose([
        transforms.Resize(256),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(
            mean=[0.485, 0.456, 0.406],  # ImageNetの平均
            std=[0.229, 0.224, 0.225]    # ImageNetの標準偏差
        )
    ])
    return preprocess_transform(image).unsqueeze(0)  # バッチ次元を追加

# 予測関数
def classify_image(image):
    input_tensor = preprocess(image)
    with torch.no_grad():
        outputs = model(input_tensor)
    probabilities = torch.nn.functional.softmax(outputs[0], dim=0)
    top5_prob, top5_catid = torch.topk(probabilities, 5)
    results = {}
    for i in range(top5_prob.size(0)):
        results[labels[top5_catid[i]]] = top5_prob[i].item()
    return results

# Gradioインターフェースの設定
iface = gr.Interface(
    fn=classify_image,
    inputs=gr.Image(type="pil"),
    outputs=gr.Label(num_top_classes=5),
    title="画像分類アプリケーション",
    description="事前学習済みのResNet-50モデルを使用して、アップロードした画像を分類します。"
)

if __name__ == "__main__":
    iface.launch(server_name="0.0.0.0", server_port=8080, auth=(os.environ["USERNAME"], os.environ["PASSWORD"]))
